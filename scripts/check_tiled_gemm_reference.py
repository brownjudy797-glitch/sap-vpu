#!/usr/bin/env python3
"""Check the bounded SAP-VPU tiled-GEMM numerical and address contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from prepare_tinyvit_fc1_k128 import chunk_words
from prepare_tinyvit_fc2_k512 import pack_stream_metadata, stream_input_mask
from prepare_tinyvit_mlp2_fixture import validate_fixture


def transpose(matrix: list[list[int]]) -> list[list[int]]:
    return [list(column) for column in zip(*matrix)]


def row_major_byte_address(base: int, row: int, column: int, stride: int) -> int:
    if min(base, row, column) < 0 or stride <= 0 or column >= stride:
        raise ValueError("invalid row-major address")
    return base + row * stride + column


def tiled_gemm(
    lhs: list[list[int]],
    rhs: list[list[int]],
    *,
    tile_m: int = 2,
    tile_n: int = 2,
    tile_k: int = 4,
    lhs_base: int = 0x1000,
    rhs_base: int = 0x2000,
) -> tuple[list[list[int]], dict[str, int | list[int]]]:
    if not lhs or not lhs[0] or not rhs or not rhs[0]:
        raise ValueError("matrices must be non-empty")
    if min(tile_m, tile_n, tile_k) <= 0:
        raise ValueError("tile dimensions must be positive")

    m_size = len(lhs)
    k_size = len(lhs[0])
    n_size = len(rhs[0])
    if any(len(row) != k_size for row in lhs):
        raise ValueError("lhs must be rectangular")
    if len(rhs) != k_size or any(len(row) != n_size for row in rhs):
        raise ValueError("rhs shape must be K x N")

    output = [[0 for _ in range(n_size)] for _ in range(m_size)]
    lhs_addresses: list[int] = []
    rhs_addresses: list[int] = []
    tile_count = 0

    for m_base in range(0, m_size, tile_m):
        for n_base in range(0, n_size, tile_n):
            for k_base in range(0, k_size, tile_k):
                m_limit = min(m_base + tile_m, m_size)
                n_limit = min(n_base + tile_n, n_size)
                k_limit = min(k_base + tile_k, k_size)
                tile_count += 1

                for row in range(m_base, m_limit):
                    for inner in range(k_base, k_limit):
                        lhs_addresses.append(row_major_byte_address(lhs_base, row, inner, k_size))
                for inner in range(k_base, k_limit):
                    for column in range(n_base, n_limit):
                        rhs_addresses.append(row_major_byte_address(rhs_base, inner, column, n_size))

                for row in range(m_base, m_limit):
                    for column in range(n_base, n_limit):
                        partial = sum(lhs[row][inner] * rhs[inner][column] for inner in range(k_base, k_limit))
                        output[row][column] += partial

    if any(not -(1 << 31) <= value < (1 << 31) for row in output for value in row):
        raise OverflowError("tiled GEMM result exceeds signed 32-bit accumulation")
    return output, {
        "tile_count": tile_count,
        "lhs_addresses": lhs_addresses,
        "rhs_addresses": rhs_addresses,
    }


def requantize_int8(accumulator: int, multiplier: int, shift: int, *, relu: bool = False) -> int:
    if multiplier < 0 or shift < 0:
        raise ValueError("requantization multiplier and shift must be non-negative")
    product = accumulator * multiplier
    if shift:
        rounding = 1 << (shift - 1)
        product = (product + rounding) >> shift if product >= 0 else -((-product + rounding) >> shift)
    if relu:
        product = max(0, product)
    return max(-128, min(127, product))


def mask_output_pair(weights: list[list[int]], masks: list[int]) -> list[list[int]]:
    if len(weights) != 2 or any(len(row) != len(weights[0]) for row in weights):
        raise ValueError("transformer fixture weights must contain one equal-length output pair")
    if not weights[0] or len(weights[0]) % 8 or len(masks) != len(weights[0]) // 8:
        raise ValueError("transformer fixture masks must cover every K8 chunk")

    masked = [row.copy() for row in weights]
    for chunk, mask in enumerate(masks):
        if not isinstance(mask, int) or not 0 <= mask <= 0xF:
            raise ValueError("transformer fixture masks must be 4-bit integers")
        for output in range(2):
            for half in range(2):
                if not mask & (1 << (2 * output + half)):
                    start = chunk * 8 + half * 4
                    masked[output][start : start + 4] = [0] * 4
    return masked


def check_transformer_fixtures(path: Path) -> int:
    raw = json.loads(path.read_text(encoding="ascii"))
    if raw.get("schema") != "sap-vpu-transformer-linear-fixtures-v1":
        raise ValueError("invalid transformer fixture document schema")
    models = raw.get("models")
    if not isinstance(models, dict) or not models:
        raise ValueError("transformer fixture document has no models")

    for name, model in models.items():
        fixture = model.get("fixture") if isinstance(model, dict) else None
        if not isinstance(fixture, dict) or fixture.get("schema") != "sap-vpu-transformer-linear-int8-v1":
            raise ValueError(f"{name}: invalid linear fixture schema")
        inputs = fixture.get("input_tokens")
        weights = fixture.get("weights")
        expected = fixture.get("expected_integer_output")
        if not isinstance(inputs, list) or not isinstance(weights, list):
            raise ValueError(f"{name}: missing input or weight matrix")
        dense, _ = tiled_gemm(inputs, transpose(weights), tile_k=8)
        if dense != expected:
            raise ValueError(f"{name}: dense tiled GEMM mismatch")
        for policy, values in fixture.get("policies", {}).items():
            if not isinstance(values, dict):
                raise ValueError(f"{name}/{policy}: invalid sparse policy")
            masked = mask_output_pair(weights, values.get("masks", []))
            sparse, _ = tiled_gemm(inputs, transpose(masked), tile_k=8)
            if sparse != values.get("expected_integer_output"):
                raise ValueError(f"{name}/{policy}: sparse tiled GEMM mismatch")

        representative = fixture.get("representative_pairs")
        if not isinstance(representative, dict):
            raise ValueError(f"{name}: missing representative output pairs")
        output_pairs = representative.get("output_pairs")
        pair_weights = representative.get("weights")
        pair_expected = representative.get("expected_integer_output")
        if (
            not isinstance(output_pairs, list)
            or not output_pairs
            or not isinstance(pair_weights, list)
            or not isinstance(pair_expected, list)
            or len(pair_weights) != len(output_pairs)
            or len(pair_expected) != len(output_pairs)
            or any(not isinstance(pair, list) or len(pair) != 2 for pair in output_pairs)
        ):
            raise ValueError(f"{name}: representative output pair shape is invalid")
        for pair, values, expected_values in zip(output_pairs, pair_weights, pair_expected):
            dense, _ = tiled_gemm(inputs, transpose(values), tile_k=8)
            if dense != expected_values:
                raise ValueError(f"{name}/outputs-{pair}: dense tiled GEMM mismatch")
        for policy, values in representative.get("policies", {}).items():
            if not isinstance(values, dict):
                raise ValueError(f"{name}/{policy}: invalid representative sparse policy")
            masks = values.get("masks")
            expected_values = values.get("expected_integer_output")
            if (
                not isinstance(masks, list)
                or not isinstance(expected_values, list)
                or len(masks) != len(output_pairs)
                or len(expected_values) != len(output_pairs)
            ):
                raise ValueError(f"{name}/{policy}: representative sparse shape is invalid")
            for pair, pair_values, pair_masks, pair_expected_values in zip(
                output_pairs, pair_weights, masks, expected_values
            ):
                masked = mask_output_pair(pair_values, pair_masks)
                sparse, _ = tiled_gemm(inputs, transpose(masked), tile_k=8)
                if sparse != pair_expected_values:
                    raise ValueError(
                        f"{name}/{policy}/outputs-{pair}: sparse tiled GEMM mismatch"
                    )
    return len(models)


def write_deit_stream_svh(source: Path, output: Path) -> None:
    raw = json.loads(source.read_text(encoding="ascii"))
    model = raw.get("models", {}).get("deit_tiny")
    fixture = model.get("fixture") if isinstance(model, dict) else None
    if not isinstance(fixture, dict):
        raise ValueError("transformer fixture document has no deit_tiny fixture")
    inputs = fixture["input_tokens"]
    representative = fixture.get("representative_pairs")
    if not isinstance(representative, dict):
        raise ValueError("DeiT stream fixture has no representative output pairs")
    weights = representative["weights"]
    pair_count = len(weights)
    channels = len(weights[0][0])
    chunks = channels // 8
    token_count = len(inputs)
    if channels != 192 or not token_count or not pair_count:
        raise ValueError("DeiT stream fixture must contain N=2, K=192 pairs")
    if chunks % 4:
        raise ValueError("DeiT stream metadata must contain a multiple of four K8 chunks")
    padded_inputs = inputs + ([[0] * channels] if token_count % 2 else [])
    token_pair_count = len(padded_inputs) // 2

    lines = ["/* Generated by check_tiled_gemm_reference.py; do not edit. */"]
    output.parent.mkdir(parents=True, exist_ok=True)

    def add_memory(name: str, values: list[int], width: int = 32) -> None:
        lines.append(f"logic [{width - 1}:0] {name} [0:{len(values) - 1}];")
        words = [
            f"{value & ((1 << width) - 1):0{width // 4}x}"
            for value in values
        ]
        (output.parent / f"{name.lower()}.hex").write_text(
            "\n".join(words) + "\n", encoding="ascii"
        )

    lines.append(f"localparam int unsigned DEIT_TINY_STREAM_K_BLOCKS = {chunks};")
    lines.append(f"localparam int unsigned DEIT_TINY_STREAM_PAIR_COUNT = {pair_count};")
    lines.append(f"localparam int unsigned DEIT_TINY_STREAM_TOKEN_COUNT = {token_count};")
    lines.append(f"localparam int unsigned DEIT_TINY_STREAM_TOKEN_PAIR_COUNT = {token_pair_count};")
    lines.append(f"localparam int unsigned DEIT_TINY_STREAM_TOKEN_PAIR_INPUT_BYTES = {chunks * 16};")
    lines.append(f"localparam int unsigned DEIT_TINY_STREAM_PAIR_WEIGHT_BYTES = {chunks * 16};")
    lines.append(f"localparam int unsigned DEIT_TINY_STREAM_PAIR_METADATA_BYTES = {chunks};")
    add_memory(
        "DEIT_TINY_STREAM_INPUT_WORDS",
        [
            word
            for token_base in range(0, len(padded_inputs), 2)
            for word in chunk_words(padded_inputs[token_base : token_base + 2], channels)
        ],
    )
    add_memory(
        "DEIT_TINY_STREAM_WEIGHT_WORDS",
        [word for pair_weights in weights for word in chunk_words(pair_weights, channels)],
    )
    add_memory(
        "DEIT_TINY_STREAM_DENSE_EXPECTED",
        [
            value
            for matrix in representative["expected_integer_output"]
            for row in matrix + ([[0, 0]] if token_count % 2 else [])
            for value in row
        ],
    )
    lines.append(
        f"localparam int unsigned DEIT_TINY_STREAM_DENSE_VDOTS = "
        f"{token_pair_count * pair_count * chunks * 8};"
    )
    lines.append(
        f"localparam int unsigned DEIT_TINY_STREAM_DENSE_READS = "
        f"{token_pair_count * pair_count * (4 + chunks * 8)};"
    )
    lines.append(
        f"localparam int unsigned DEIT_TINY_STREAM_WRITES = "
        f"{token_pair_count * pair_count * 4};"
    )

    for label, policy_name in (
        ("GLOBAL_L1_12P5", "layer_global_l1_12.5"),
        ("L1_BUDGET_5", "layer_l1_budget_5"),
    ):
        policy = representative.get("policies", {}).get(policy_name)
        if not isinstance(policy, dict):
            raise ValueError(f"DeiT stream fixture is missing {policy_name}")
        masks = policy.get("masks")
        if (
            not isinstance(masks, list)
            or len(masks) != pair_count
            or any(len(pair_masks) != chunks for pair_masks in masks)
        ):
            raise ValueError(f"DeiT stream fixture has invalid {policy_name} masks")
        metadata = [
            word for pair_masks in masks for word in pack_stream_metadata(pair_masks)
        ]
        weight_reads = sum(
            bin(mask).count("1") for pair_masks in masks for mask in pair_masks
        )
        input_reads = sum(
            bin(stream_input_mask(mask)).count("1")
            for pair_masks in masks
            for mask in pair_masks
        )
        add_memory(f"DEIT_TINY_STREAM_{label}_METADATA_WORDS", metadata)
        add_memory(
            f"DEIT_TINY_STREAM_{label}_EXPECTED",
            [
                value
                for matrix in policy["expected_integer_output"]
                for row in matrix + ([[0, 0]] if token_count % 2 else [])
                for value in row
            ],
        )
        lines.append(
            f"localparam int unsigned DEIT_TINY_STREAM_{label}_VDOTS = "
            f"{token_pair_count * weight_reads * 2};"
        )
        lines.append(
            f"localparam int unsigned DEIT_TINY_STREAM_{label}_READS = "
            f"{token_pair_count * (pair_count * 5 + len(metadata) + input_reads + weight_reads)};"
        )
        lines.append(
            f"localparam int unsigned DEIT_TINY_STREAM_{label}_SAVED_READS = "
            f"{token_pair_count * (pair_count * chunks * 8 - input_reads - weight_reads)};"
        )

    output.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_deit_board_asm_include(source: Path, output: Path) -> None:
    raw = json.loads(source.read_text(encoding="ascii"))
    model = raw.get("models", {}).get("deit_tiny")
    fixture = model.get("fixture") if isinstance(model, dict) else None
    provenance = model.get("provenance") if isinstance(model, dict) else None
    if not isinstance(fixture, dict) or not isinstance(provenance, dict):
        raise ValueError("transformer fixture document has no deit_tiny fixture")

    lhs = fixture.get("input_tokens", [])[:2]
    representative = fixture.get("representative_pairs")
    if not isinstance(representative, dict):
        raise ValueError("DeiT board fixture has no representative output pairs")
    try:
        pair_index = representative["output_pairs"].index([510, 511])
        weights = representative["weights"][pair_index]
        dense_expected = representative["expected_integer_output"][pair_index]
    except (KeyError, ValueError, IndexError) as error:
        raise ValueError("DeiT board fixture has no output pair 510/511") from error
    channels = len(lhs[0]) if lhs else 0
    if (
        len(lhs) != 2
        or len(weights) != 2
        or channels != 192
        or any(len(row) != channels for row in lhs + weights)
    ):
        raise ValueError("DeiT board tile requires two M/N rows with K=192")
    if any(not isinstance(value, int) or not -128 <= value <= 127 for row in lhs + weights for value in row):
        raise ValueError("DeiT board tile values must be signed INT8")

    expected, _ = tiled_gemm(lhs, transpose(weights), tile_k=8)
    if expected != dense_expected:
        raise ValueError("DeiT board dense golden output mismatch")
    lhs_words = chunk_words(lhs, channels)
    rhs_words = chunk_words(weights, channels)
    policies = {}
    for label, policy_name in (
        ("GLOBAL", "layer_global_l1_12.5"),
        ("BUDGET", "layer_l1_budget_5"),
    ):
        policy = representative.get("policies", {}).get(policy_name)
        if not isinstance(policy, dict):
            raise ValueError(f"DeiT board fixture is missing {policy_name}")
        masks = policy["masks"][pair_index]
        policy_expected = policy["expected_integer_output"][pair_index]
        masked, _ = tiled_gemm(lhs, transpose(mask_output_pair(weights, masks)), tile_k=8)
        if masked != policy_expected:
            raise ValueError(f"DeiT board {policy_name} golden output mismatch")
        weight_reads = sum(mask.bit_count() for mask in masks)
        input_reads = sum(stream_input_mask(mask).bit_count() for mask in masks)
        policies[label] = {
            "expected": policy_expected,
            "metadata": pack_stream_metadata(masks),
            "mac_active": 2 * weight_reads,
            "dma_saved": channels - input_reads - weight_reads,
        }
    lines = [
        "/* Generated by check_tiled_gemm_reference.py; do not edit. */",
        f"/* Model: {provenance.get('model_id', 'unknown')} */",
        f"/* Layer: {provenance.get('layer', 'unknown')} */",
        f"/* Checkpoint SHA256: {provenance.get('checkpoint_sha256', 'unknown')} */",
        ".equ TILE_OUTPUT_0, 510",
        ".equ TILE_OUTPUT_1, 511",
        f".equ TILE_K_BLOCKS, {channels // 8}",
        f".equ TILE_MATRIX_WORDS, {len(lhs_words)}",
        f".equ TILE_METADATA_WORDS, {len(policies['GLOBAL']['metadata'])}",
        ".equ LHS_BASE, 0x00010000",
        f".equ RHS_BASE, 0x{0x10000 + len(lhs_words) * 4:08x}",
        f".equ OUT_BASE, 0x{0x10000 + 2 * len(lhs_words) * 4:08x}",
        f".equ DESC_BASE, 0x{0x10010 + 2 * len(lhs_words) * 4:08x}",
        f".equ GLOBAL_META_BASE, 0x{0x10024 + 2 * len(lhs_words) * 4:08x}",
        f".equ BUDGET_META_BASE, 0x{0x10024 + 2 * len(lhs_words) * 4 + len(policies['GLOBAL']['metadata']) * 4:08x}",
        f".equ TILE_DENSE_MAC_ACTIVE, {channels}",
        ".equ TILE_DENSE_DMA_SAVED, 0",
    ]
    for row in range(2):
        for column in range(2):
            lines.append(f".equ TILE_DENSE_EXPECT_{row}{column}, {expected[row][column]}")
    for label, values in policies.items():
        lines.append(f".equ TILE_{label}_MAC_ACTIVE, {values['mac_active']}")
        lines.append(f".equ TILE_{label}_DMA_SAVED, {values['dma_saved']}")
        for row in range(2):
            for column in range(2):
                lines.append(
                    f".equ TILE_{label}_EXPECT_{row}{column}, "
                    f"{values['expected'][row][column]}"
                )
    lines.extend(["", '  .section .rodata, "a"', "  .balign 4", "tile_lhs_words:"])
    lines.extend(f"  .word 0x{word:08x}" for word in lhs_words)
    lines.extend(["", "tile_rhs_words:"])
    lines.extend(f"  .word 0x{word:08x}" for word in rhs_words)
    for label, values in policies.items():
        lines.extend(["", f"tile_{label.lower()}_metadata_words:"])
        lines.extend(f"  .word 0x{word:08x}" for word in values["metadata"])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="ascii")


def self_test() -> None:
    root = Path(__file__).resolve().parents[1]
    for filename, expected in (
        ("tinyvit_mlp2_smoke.json", [[20, 16], [20, 14]]),
        ("tinyvit_mlp2_checkpoint.json", [[-2286, -240], [10391, -7315]]),
        ("tinyvit_mlp2_activation.json", [[0, 0], [2722, 6528]]),
    ):
        fixture = validate_fixture(
            json.loads((root / "sw/baremetal/fixtures" / filename).read_text(encoding="utf-8"))
        )
        hidden_acc, _ = tiled_gemm(fixture["input_tokens"], transpose(fixture["fc1_weights"]))
        shift = fixture["quantization"].get("fc1_output_requant_shift", 0)
        hidden = [[requantize_int8(value, 1, shift, relu=True) for value in row] for row in hidden_acc]
        output, _ = tiled_gemm(hidden, transpose(fixture["fc2_weights"]))
        assert output == expected

    tail_lhs = [[1, 2, 3, 4, 5], [5, 4, 3, 2, 1], [-1, 0, 1, 0, -1]]
    tail_rhs = [[1, 0, 2], [0, 1, 2], [1, 1, 0], [2, 0, 1], [0, 2, 1]]
    tail_output, trace = tiled_gemm(tail_lhs, tail_rhs)
    assert tail_output == [[12, 15, 15], [12, 9, 21], [0, -1, -3]]
    assert trace["tile_count"] == 8
    assert len(trace["lhs_addresses"]) == 30
    assert len(trace["rhs_addresses"]) == 30
    assert set(trace["lhs_addresses"]) == set(range(0x1000, 0x100F))
    assert set(trace["rhs_addresses"]) == set(range(0x2000, 0x200F))

    accumulated, _ = tiled_gemm([[127] * 5], [[127] for _ in range(5)])
    assert accumulated == [[80645]]
    assert requantize_int8(5, 1, 1) == 3
    assert requantize_int8(-5, 1, 1) == -3
    assert requantize_int8(300, 1, 1) == 127
    assert requantize_int8(-10, 1, 0, relu=True) == 0
    assert mask_output_pair([[1] * 8, [2] * 8], [0x9]) == [
        [1, 1, 1, 1, 0, 0, 0, 0],
        [0, 0, 0, 0, 2, 2, 2, 2],
    ]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path, nargs="?")
    parser.add_argument("--svh", type=Path)
    parser.add_argument("--board-inc", type=Path)
    args = parser.parse_args()
    self_test()
    if args.fixture:
        count = check_transformer_fixtures(args.fixture)
        if args.svh:
            write_deit_stream_svh(args.fixture, args.svh)
        if args.board_inc:
            write_deit_board_asm_include(args.fixture, args.board_inc)
        print(f"transformer tiled GEMM fixture check: PASS ({count} models)")
    elif args.svh or args.board_inc:
        parser.error("--svh and --board-inc require a transformer fixture")
    else:
        print("tiled GEMM reference self-test: PASS")
