#!/usr/bin/env python3
"""Validate and pack the tracked TinyViT FC2 K=512 activation slices."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import tempfile
from typing import Any

from prepare_tinyvit_fc1_k128 import (
    CHUNK_K,
    FC2_OUTPUT_CHANNELS,
    TOKENS,
    chunk_words,
    fc2_lowest_l1_group_masks,
    fc2_masked_window_outputs,
    require_matrix,
)


SCHEMA = "sap-vpu-tinyvit-fc2-k512-int8-v1"
PAIR_SCHEMA = "sap-vpu-tinyvit-fc2-k512-pairs-int8-v1"
INPUT_CHANNELS = 512
CHUNKS = INPUT_CHANNELS // CHUNK_K
GLOBAL_DROP_COUNT = 16
GROUP_LANES = 4
LAYER_OUTPUT_CHANNELS = 128
REPRESENTATIVE_OUTPUT_PAIRS = ((0, 1), (42, 43), (84, 85), (126, 127))


def layer_policy_masks(weights: list[list[int]], policy: str) -> list[list[int]]:
    output_channels = len(weights)
    if output_channels == 0 or output_channels % FC2_OUTPUT_CHANNELS:
        raise ValueError("layer weights must contain an even number of output channels")
    channels = len(weights[0])
    if channels == 0 or channels % CHUNK_K or any(len(row) != channels for row in weights):
        raise ValueError("layer weight rows must have a common K divisible by 8")
    masks = [[0xF] * (channels // CHUNK_K) for _ in range(output_channels // 2)]
    groups = []
    tile_groups = [
        [[] for _ in range(channels // CHUNK_K)] for _ in range(output_channels // 2)
    ]
    groups_per_output = channels // GROUP_LANES
    for output, row in enumerate(weights):
        for group_index in range(groups_per_output):
            base = group_index * GROUP_LANES
            chunk = base // CHUNK_K
            group = (base % CHUNK_K) // GROUP_LANES
            bit = (output % 2) * (CHUNK_K // GROUP_LANES) + group
            entry = (
                sum(abs(value) for value in row[base : base + GROUP_LANES]),
                output * groups_per_output + group_index,
                output // 2,
                chunk,
                bit,
            )
            groups.append(entry)
            tile_groups[output // 2][chunk].append(entry)

    if policy == "tile_local_l1_25":
        selected = []
        for pair in range(output_channels // 2):
            for chunk in range(channels // CHUNK_K):
                selected.append(
                    min(tile_groups[pair][chunk], key=lambda group: (group[0], group[4]))
                )
    else:
        groups.sort(key=lambda group: (group[0], group[1]))
        kind, value = policy.rsplit("_", 1)
        if kind == "layer_global_l1":
            selected = groups[: int(len(groups) * float(value) / 100.0)]
        elif kind == "layer_l1_budget":
            limit = sum(group[0] for group in groups) * float(value) / 100.0
            selected = []
            dropped_l1 = 0
            for group in groups:
                if dropped_l1 + group[0] > limit:
                    break
                selected.append(group)
                dropped_l1 += group[0]
        else:
            raise ValueError(f"unsupported policy: {policy}")

    for _norm, _index, pair, chunk, bit in selected:
        masks[pair][chunk] &= ~(1 << bit)
    return masks


def layer_masks_to_valid_matrix(masks: list[list[int]]) -> list[list[bool]]:
    channels = len(masks[0]) * CHUNK_K
    valid = [[False] * (channels // GROUP_LANES) for _ in range(len(masks) * 2)]
    for pair, pair_masks in enumerate(masks):
        if len(pair_masks) * CHUNK_K != channels:
            raise ValueError("layer masks must have a common K")
        for chunk, mask in enumerate(pair_masks):
            if not isinstance(mask, int) or isinstance(mask, bool) or not 0 <= mask <= 0xF:
                raise ValueError("layer masks must contain four-bit integers")
            for bit in range(4):
                output = pair * 2 + bit // 2
                group = chunk * 2 + bit % 2
                valid[output][group] = bool(mask & (1 << bit))
    return valid


def validate(raw: Any) -> tuple[list[list[int]], list[list[int]], list[list[int]]]:
    if not isinstance(raw, dict) or raw.get("schema") != "sap-vpu-tinyvit-mlp2-int8-v1":
        raise ValueError("invalid parent TinyViT activation fixture")
    fixture = raw.get("fc2_k512")
    if not isinstance(fixture, dict) or fixture.get("schema") != SCHEMA:
        raise ValueError(f"missing {SCHEMA} fixture")
    if fixture.get("chunk_k") != CHUNK_K:
        raise ValueError(f"fc2_k512.chunk_k must be {CHUNK_K}")
    inputs = require_matrix(fixture.get("input_tokens"), "input_tokens", TOKENS, INPUT_CHANNELS)
    weights = require_matrix(
        fixture.get("weights"), "weights", FC2_OUTPUT_CHANNELS, INPUT_CHANNELS
    )
    expected = fixture.get("expected_integer_output")
    if (
        not isinstance(expected, list)
        or len(expected) != TOKENS
        or any(
            not isinstance(row, list)
            or len(row) != FC2_OUTPUT_CHANNELS
            or any(not isinstance(value, int) or isinstance(value, bool) for value in row)
            for row in expected
        )
    ):
        raise ValueError("expected_integer_output must have integer shape [2, 2]")
    calculated = [
        [
            sum(inputs[token][k] * weights[output][k] for k in range(INPUT_CHANNELS))
            for output in range(FC2_OUTPUT_CHANNELS)
        ]
        for token in range(TOKENS)
    ]
    if calculated != expected:
        raise ValueError("FC2 K=512 golden does not match INT8 inputs and weights")
    return inputs, weights, [list(row) for row in expected]


def validate_pairs(raw: Any, inputs: list[list[int]]) -> dict[str, Any]:
    fixture = raw.get("fc2_k512_pairs")
    if not isinstance(fixture, dict) or fixture.get("schema") != PAIR_SCHEMA:
        raise ValueError(f"missing {PAIR_SCHEMA} fixture")
    if fixture.get("chunk_k") != CHUNK_K:
        raise ValueError(f"fc2_k512_pairs.chunk_k must be {CHUNK_K}")
    output_pairs = fixture.get("output_pairs")
    if output_pairs != [list(pair) for pair in REPRESENTATIVE_OUTPUT_PAIRS]:
        raise ValueError("fc2_k512_pairs.output_pairs must match the representative set")
    raw_weights = fixture.get("weights")
    if not isinstance(raw_weights, list) or len(raw_weights) != len(output_pairs):
        raise ValueError("fc2_k512_pairs.weights must contain one matrix per output pair")
    weights = [
        require_matrix(matrix, f"fc2_k512_pairs.weights[{index}]", 2, INPUT_CHANNELS)
        for index, matrix in enumerate(raw_weights)
    ]

    def expected_matrices(value: Any, name: str) -> list[list[list[int]]]:
        if not isinstance(value, list) or len(value) != len(output_pairs):
            raise ValueError(f"{name} must contain one matrix per output pair")
        matrices = []
        for index, matrix in enumerate(value):
            if (
                not isinstance(matrix, list)
                or len(matrix) != TOKENS
                or any(
                    not isinstance(row, list)
                    or len(row) != 2
                    or any(not isinstance(item, int) or isinstance(item, bool) for item in row)
                    for row in matrix
                )
            ):
                raise ValueError(f"{name}[{index}] must have integer shape [2, 2]")
            matrices.append([list(row) for row in matrix])
        return matrices

    dense_expected = expected_matrices(
        fixture.get("expected_integer_output"),
        "fc2_k512_pairs.expected_integer_output",
    )
    for index, matrix in enumerate(weights):
        if masked_aggregate(inputs, matrix, [0xF] * CHUNKS) != dense_expected[index]:
            raise ValueError("representative dense golden does not match INT8 operands")

    raw_policies = fixture.get("policies")
    policy_names = (
        "layer_global_l1_6p25",
        "layer_l1_budget_1pct",
        "layer_global_l1_12p5",
        "layer_l1_budget_5pct",
    )
    if not isinstance(raw_policies, dict) or set(raw_policies) != set(policy_names):
        raise ValueError("fc2_k512_pairs.policies has an unexpected policy set")
    policies = {}
    for name in policy_names:
        policy = raw_policies[name]
        masks = policy.get("masks") if isinstance(policy, dict) else None
        if (
            not isinstance(masks, list)
            or len(masks) != len(output_pairs)
            or any(
                not isinstance(pair_masks, list)
                or len(pair_masks) != CHUNKS
                or any(
                    not isinstance(mask, int)
                    or isinstance(mask, bool)
                    or not 0 <= mask <= 0xF
                    for mask in pair_masks
                )
                for pair_masks in masks
            )
        ):
            raise ValueError(f"fc2_k512_pairs.policies.{name}.masks is invalid")
        expected = expected_matrices(
            policy.get("expected_integer_output"),
            f"fc2_k512_pairs.policies.{name}.expected_integer_output",
        )
        for index, matrix in enumerate(weights):
            if masked_aggregate(inputs, matrix, masks[index]) != expected[index]:
                raise ValueError(f"representative {name} golden does not match its masks")
        policies[name] = {"masks": masks, "expected": expected}
    return {
        "output_pairs": output_pairs,
        "weights": weights,
        "dense_expected": dense_expected,
        "policies": policies,
    }


def masked_aggregate(
    inputs: list[list[int]], weights: list[list[int]], masks: list[int]
) -> list[list[int]]:
    windows = fc2_masked_window_outputs(inputs, weights, masks)
    return [
        [sum(window[token][output] for window in windows) for output in range(FC2_OUTPUT_CHANNELS)]
        for token in range(TOKENS)
    ]


def stream_input_mask(weight_mask: int) -> int:
    input_mask = 0
    for group in range(CHUNK_K // GROUP_LANES):
        if weight_mask & (1 << group) or weight_mask & (1 << (group + 2)):
            input_mask |= (1 << group) | (1 << (group + 2))
    return input_mask


def pack_stream_metadata(masks: list[int]) -> list[int]:
    if len(masks) % 4:
        raise ValueError("stream metadata requires a multiple of four chunks")
    words = []
    for base in range(0, len(masks), 4):
        word = 0
        for offset, weight_mask in enumerate(masks[base : base + 4]):
            byte = (weight_mask << 4) | stream_input_mask(weight_mask)
            word |= byte << (offset * 8)
        words.append(word)
    return words


def pair_policy_counts(masks: list[list[int]]) -> tuple[int, int, int]:
    weight_reads = sum(bin(mask).count("1") for pair_masks in masks for mask in pair_masks)
    input_reads = 0
    for pair_masks in masks:
        if len(pair_masks) != CHUNKS:
            raise ValueError("representative pair masks must contain 64 chunks")
        for mask in pair_masks:
            input_reads += bin(stream_input_mask(mask)).count("1")
    return TOKENS * weight_reads, input_reads + weight_reads, len(masks) * CHUNKS * 4


def write_svh(
    path: Path,
    inputs: list[list[int]],
    weights: list[list[int]],
    dense_expected: list[list[int]],
    pairs: dict[str, Any],
) -> None:
    policies = {
        "GLOBAL_L1_6P25": fc2_lowest_l1_group_masks(weights, drop_count=GLOBAL_DROP_COUNT),
        "L1_BUDGET_2PCT": fc2_lowest_l1_group_masks(weights, l1_budget=0.02),
    }
    lines = ["/* Generated by prepare_tinyvit_fc2_k512.py; do not edit. */"]
    for name, words in (
        ("TINYVIT_FC2_K512_INPUT_WORDS", chunk_words(inputs, INPUT_CHANNELS)),
        ("TINYVIT_FC2_K512_WEIGHT_WORDS", chunk_words(weights, INPUT_CHANNELS)),
    ):
        lines.append(f"localparam logic [31:0] {name} [0:{len(words) - 1}] = '{{")
        lines.append("  " + ", ".join(f"32'h{word:08x}" for word in words))
        lines.append("};")
    for name, masks in policies.items():
        lines.append(f"localparam logic [3:0] TINYVIT_FC2_K512_{name}_MASKS [0:{len(masks) - 1}] = '{{")
        lines.append("  " + ", ".join(f"4'h{mask:x}" for mask in masks))
        lines.append("};")
        metadata = pack_stream_metadata(masks)
        lines.append(
            f"localparam logic [31:0] TINYVIT_FC2_K512_{name}_STREAM_METADATA_WORDS "
            f"[0:{len(metadata) - 1}] = '{{"
        )
        lines.append("  " + ", ".join(f"32'h{word:08x}" for word in metadata))
        lines.append("};")
    expected = {
        "DENSE": dense_expected,
        **{name: masked_aggregate(inputs, weights, masks) for name, masks in policies.items()},
    }
    for name, matrix in expected.items():
        values = [value for row in matrix for value in row]
        lines.append(f"localparam logic [31:0] TINYVIT_FC2_K512_{name}_EXPECTED [0:3] = '{{")
        lines.append("  " + ", ".join(f"32'h{value & 0xffffffff:08x}" for value in values))
        lines.append("};")

    pair_count = len(pairs["output_pairs"])
    lines.append(f"localparam int unsigned TINYVIT_FC2_K512_PAIR_COUNT = {pair_count};")
    output_channels = [channel for pair in pairs["output_pairs"] for channel in pair]
    lines.append(
        f"localparam logic [7:0] TINYVIT_FC2_K512_PAIR_OUTPUT_CHANNELS [0:{len(output_channels) - 1}] = '{{"
    )
    lines.append("  " + ", ".join(f"8'd{channel}" for channel in output_channels))
    lines.append("};")
    pair_weight_words = [
        word for matrix in pairs["weights"] for word in chunk_words(matrix, INPUT_CHANNELS)
    ]
    lines.append(
        f"localparam logic [31:0] TINYVIT_FC2_K512_PAIR_WEIGHT_WORDS [0:{len(pair_weight_words) - 1}] = '{{"
    )
    lines.append("  " + ", ".join(f"32'h{word:08x}" for word in pair_weight_words))
    lines.append("};")
    pair_policies = {
        "LAYER_GLOBAL_L1_6P25": pairs["policies"]["layer_global_l1_6p25"],
        "LAYER_L1_BUDGET_1PCT": pairs["policies"]["layer_l1_budget_1pct"],
        "LAYER_GLOBAL_L1_12P5": pairs["policies"]["layer_global_l1_12p5"],
        "LAYER_L1_BUDGET_5PCT": pairs["policies"]["layer_l1_budget_5pct"],
    }
    for name, policy in pair_policies.items():
        masks = [mask for pair_masks in policy["masks"] for mask in pair_masks]
        lines.append(
            f"localparam logic [3:0] TINYVIT_FC2_K512_PAIR_{name}_MASKS [0:{len(masks) - 1}] = '{{"
        )
        lines.append("  " + ", ".join(f"4'h{mask:x}" for mask in masks))
        lines.append("};")
        metadata = [
            word
            for pair_masks in policy["masks"]
            for word in pack_stream_metadata(pair_masks)
        ]
        lines.append(
            f"localparam logic [31:0] TINYVIT_FC2_K512_PAIR_{name}_STREAM_METADATA_WORDS "
            f"[0:{len(metadata) - 1}] = '{{"
        )
        lines.append("  " + ", ".join(f"32'h{word:08x}" for word in metadata))
        lines.append("};")
    pair_expected = {
        "DENSE": pairs["dense_expected"],
        **{name: policy["expected"] for name, policy in pair_policies.items()},
    }
    for name, matrices in pair_expected.items():
        values = [value for matrix in matrices for row in matrix for value in row]
        lines.append(
            f"localparam logic [31:0] TINYVIT_FC2_K512_PAIR_{name}_EXPECTED [0:{len(values) - 1}] = '{{"
        )
        lines.append("  " + ", ".join(f"32'h{value & 0xffffffff:08x}" for value in values))
        lines.append("};")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def self_test() -> None:
    root = Path(__file__).resolve().parents[1]
    raw = json.loads(
        (root / "sw/baremetal/fixtures/tinyvit_mlp2_activation.json").read_text(encoding="ascii")
    )
    inputs, weights, expected = validate(raw)
    pairs = validate_pairs(raw, inputs)
    assert expected == [[4760, -5014], [-1239, -7509]]
    assert len(chunk_words(inputs, INPUT_CHANNELS)) == 256
    assert len(chunk_words(weights, INPUT_CHANNELS)) == 256
    global_masks = fc2_lowest_l1_group_masks(weights, drop_count=GLOBAL_DROP_COUNT)
    budget_masks = fc2_lowest_l1_group_masks(weights, l1_budget=0.02)
    assert len(global_masks) == CHUNKS
    assert len(pack_stream_metadata(global_masks)) == CHUNKS // 4
    assert sum(4 - bin(mask).count("1") for mask in global_masks) == GLOBAL_DROP_COUNT
    assert 0 < sum(4 - bin(mask).count("1") for mask in budget_masks) < CHUNKS * 4
    assert global_masks == budget_masks
    assert masked_aggregate(inputs, weights, global_masks) == [[4659, -4532], [-909, -6957]]
    assert masked_aggregate(inputs, weights, [0xF] * CHUNKS) == expected
    synthetic = [list(range(1 + output * 8, 9 + output * 8)) for output in range(4)]
    synthetic_masks = layer_policy_masks(synthetic, "layer_global_l1_25")
    assert sum(4 - bin(mask).count("1") for row in synthetic_masks for mask in row) == 2
    assert sum(not value for row in layer_masks_to_valid_matrix(synthetic_masks) for value in row) == 2
    assert layer_policy_masks([[1] * 8 for _ in range(4)], "layer_global_l1_25") == [
        [0xC],
        [0xF],
    ]
    assert pair_policy_counts([[0xF] * CHUNKS for _ in REPRESENTATIVE_OUTPUT_PAIRS]) == (
        2048,
        2048,
        1024,
    )
    assert pair_policy_counts(pairs["policies"]["layer_global_l1_6p25"]["masks"]) == (
        1868,
        1956,
        1024,
    )
    assert pair_policy_counts(pairs["policies"]["layer_l1_budget_1pct"]["masks"]) == (
        1922,
        1985,
        1024,
    )
    assert pair_policy_counts(pairs["policies"]["layer_global_l1_12p5"]["masks"]) == (
        1740,
        1886,
        1024,
    )
    assert pair_policy_counts(pairs["policies"]["layer_l1_budget_5pct"]["masks"]) == (
        1730,
        1881,
        1024,
    )
    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / "fixture.svh"
        write_svh(output, inputs, weights, expected, pairs)
        generated = output.read_text(encoding="ascii")
        assert "TINYVIT_FC2_K512_INPUT_WORDS [0:255]" in generated
        assert "TINYVIT_FC2_K512_WEIGHT_WORDS [0:255]" in generated
        assert "TINYVIT_FC2_K512_GLOBAL_L1_6P25_MASKS [0:63]" in generated
        assert "TINYVIT_FC2_K512_L1_BUDGET_2PCT_MASKS [0:63]" in generated
        assert "TINYVIT_FC2_K512_GLOBAL_L1_6P25_STREAM_METADATA_WORDS [0:15]" in generated
        assert "TINYVIT_FC2_K512_PAIR_COUNT = 4" in generated
        assert "TINYVIT_FC2_K512_PAIR_WEIGHT_WORDS [0:1023]" in generated
        assert "TINYVIT_FC2_K512_PAIR_LAYER_GLOBAL_L1_6P25_MASKS [0:255]" in generated
        assert "TINYVIT_FC2_K512_PAIR_LAYER_GLOBAL_L1_12P5_STREAM_METADATA_WORDS [0:63]" in generated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path, nargs="?")
    parser.add_argument("--svh", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            if args.fixture or args.svh:
                parser.error("--self-test does not accept fixture output arguments")
            self_test()
        elif not args.fixture or not args.svh:
            parser.error("fixture and --svh are required")
        else:
            raw = json.loads(args.fixture.read_text(encoding="ascii"))
            inputs, weights, expected = validate(raw)
            write_svh(args.svh, inputs, weights, expected, validate_pairs(raw, inputs))
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"TinyViT FC2 K=512 fixture failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
