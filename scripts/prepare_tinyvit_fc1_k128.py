#!/usr/bin/env python3
"""Validate and pack the tracked TinyViT FC1 K=128 activation slice."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import tempfile
from typing import Any

from prepare_tinyvit_mlp2_fixture import pack_int8


SCHEMA = "sap-vpu-tinyvit-fc1-k128-int8-v1"
TOKENS = 2
INPUT_CHANNELS = 128
OUTPUT_CHANNELS = 32
WINDOW_OUTPUT_CHANNELS = 16
CHUNK_K = 8
OUTPUT_TILE_CHANNELS = 2
POSTPROCESS_BOUNDARY = "cv32e40x-int32-bias-q16-requant-int8-gelu-lut"
FC2_OUTPUT_CHANNELS = 2
FC2_BOUNDARY = "sap-vpu-int8-fc2-k8-chunked-partial-no-bias"
OUTPUT_WINDOWS = OUTPUT_CHANNELS // WINDOW_OUTPUT_CHANNELS
WINDOW_ID_RAM_WORD = 0x3C
INPUT_RAM_WORD = 0x40
WEIGHT_RAM_WORD = 0x80
FC2_WEIGHT_RAM_WORD = 0x288


def require_matrix(value: Any, name: str, rows: int, columns: int) -> list[list[int]]:
    if not isinstance(value, list) or len(value) != rows:
        raise ValueError(f"{name} must have shape [{rows}, {columns}]")
    matrix: list[list[int]] = []
    for row_index, row in enumerate(value):
        if not isinstance(row, list) or len(row) != columns:
            raise ValueError(f"{name}[{row_index}] must have {columns} entries")
        if any(not isinstance(item, int) or isinstance(item, bool) or not -128 <= item <= 127 for item in row):
            raise ValueError(f"{name}[{row_index}] entries must be signed INT8")
        matrix.append(row)
    return matrix


def signed_round_shift(value: int, multiplier: int, shift: int) -> int:
    scaled = value * multiplier
    rounded = (abs(scaled) + (1 << (shift - 1))) >> shift
    return -rounded if scaled < 0 else rounded


def validate(
    raw: Any,
) -> tuple[
    list[list[int]],
    list[list[int]],
    list[list[int]],
    list[int],
    int,
    int,
    list[int],
    list[list[int]],
    list[list[int]],
    list[list[int]],
]:
    if not isinstance(raw, dict) or raw.get("schema") != "sap-vpu-tinyvit-mlp2-int8-v1":
        raise ValueError("invalid parent TinyViT activation fixture")
    fixture = raw.get("fc1_k128")
    if not isinstance(fixture, dict) or fixture.get("schema") != SCHEMA:
        raise ValueError(f"missing {SCHEMA} fixture")
    if fixture.get("chunk_k") != CHUNK_K:
        raise ValueError(f"fc1_k128.chunk_k must be {CHUNK_K}")
    inputs = require_matrix(fixture.get("input_tokens"), "input_tokens", TOKENS, INPUT_CHANNELS)
    weights = require_matrix(fixture.get("weights"), "weights", OUTPUT_CHANNELS, INPUT_CHANNELS)
    expected = fixture.get("expected_integer_output")
    if not isinstance(expected, list) or len(expected) != TOKENS:
        raise ValueError(f"expected_integer_output must have shape [{TOKENS}, {OUTPUT_CHANNELS}]")
    expected = [list(row) for row in expected]
    if any(len(row) != OUTPUT_CHANNELS or any(not isinstance(item, int) for item in row) for row in expected):
        raise ValueError(f"expected_integer_output must have integer shape [{TOKENS}, {OUTPUT_CHANNELS}]")
    calculated = [
        [sum(inputs[token][k] * weights[output][k] for k in range(INPUT_CHANNELS)) for output in range(OUTPUT_CHANNELS)]
        for token in range(TOKENS)
    ]
    if calculated != expected:
        raise ValueError("expected_integer_output does not match the INT8 matrices")
    postprocess = fixture.get("software_postprocess")
    if not isinstance(postprocess, dict) or postprocess.get("boundary") != POSTPROCESS_BOUNDARY:
        raise ValueError("missing CV32E40X bias/GELU software postprocess")
    bias = postprocess.get("bias_accumulator")
    if (
        not isinstance(bias, list)
        or len(bias) != OUTPUT_CHANNELS
        or any(not isinstance(item, int) or isinstance(item, bool) for item in bias)
    ):
        raise ValueError(f"bias_accumulator must have {OUTPUT_CHANNELS} integer entries")
    multiplier = postprocess.get("requant_multiplier")
    shift = postprocess.get("requant_shift")
    if not isinstance(multiplier, int) or isinstance(multiplier, bool) or multiplier <= 0:
        raise ValueError("requant_multiplier must be a positive integer")
    if not isinstance(shift, int) or isinstance(shift, bool) or not 1 <= shift <= 30:
        raise ValueError("requant_shift must be between 1 and 30")
    lut = postprocess.get("gelu_lut")
    if (
        not isinstance(lut, list)
        or len(lut) != 256
        or any(not isinstance(item, int) or isinstance(item, bool) or not -128 <= item <= 127 for item in lut)
    ):
        raise ValueError("gelu_lut must contain 256 signed INT8 entries")
    preactivation = require_matrix(
        postprocess.get("expected_preactivation_int8"),
        "expected_preactivation_int8",
        TOKENS,
        OUTPUT_CHANNELS,
    )
    gelu = require_matrix(
        postprocess.get("expected_gelu_int8"),
        "expected_gelu_int8",
        TOKENS,
        OUTPUT_CHANNELS,
    )
    for token in range(TOKENS):
        for output in range(OUTPUT_CHANNELS):
            requantized = max(
                -128,
                min(127, signed_round_shift(expected[token][output] + bias[output], multiplier, shift)),
            )
            if requantized != preactivation[token][output]:
                raise ValueError("expected_preactivation_int8 does not match integer postprocess")
            if lut[requantized + 128] != gelu[token][output]:
                raise ValueError("expected_gelu_int8 does not match gelu_lut")
    fc2 = fixture.get("fc2_partial")
    if not isinstance(fc2, dict) or fc2.get("boundary") != FC2_BOUNDARY:
        raise ValueError("missing SAP-VPU chunked FC2 partial")
    if fc2.get("chunk_k") != CHUNK_K:
        raise ValueError(f"fc2_partial.chunk_k must be {CHUNK_K}")
    fc2_weights = require_matrix(
        fc2.get("weights"),
        "fc2_partial.weights",
        FC2_OUTPUT_CHANNELS,
        OUTPUT_CHANNELS,
    )
    fc2_expected = fc2.get("expected_integer_output")
    if not isinstance(fc2_expected, list) or len(fc2_expected) != TOKENS:
        raise ValueError("fc2_partial.expected_integer_output must have two rows")
    fc2_expected = [list(row) for row in fc2_expected]
    if any(
        len(row) != FC2_OUTPUT_CHANNELS
        or any(not isinstance(item, int) or isinstance(item, bool) for item in row)
        for row in fc2_expected
    ):
        raise ValueError("fc2_partial.expected_integer_output must have integer shape [2, 2]")
    calculated_fc2 = [
        [
            sum(gelu[token][k] * fc2_weights[output][k] for k in range(OUTPUT_CHANNELS))
            for output in range(FC2_OUTPUT_CHANNELS)
        ]
        for token in range(TOKENS)
    ]
    if calculated_fc2 != fc2_expected:
        raise ValueError("FC2 partial golden does not match GELU activations and weights")
    return inputs, weights, expected, bias, multiplier, shift, lut, gelu, fc2_weights, fc2_expected


def chunk_words(matrix: list[list[int]], channels: int = INPUT_CHANNELS) -> list[int]:
    words: list[int] = []
    for chunk_base in range(0, channels, CHUNK_K):
        for row_index, row in enumerate(matrix):
            words.append(pack_int8(row[chunk_base : chunk_base + 4], f"row{row_index}_chunk{chunk_base}"))
            words.append(pack_int8(row[chunk_base + 4 : chunk_base + 8], f"row{row_index}_chunk{chunk_base + 4}"))
    return words


def fc2_window_outputs(gelu: list[list[int]], weights: list[list[int]]) -> list[list[list[int]]]:
    return [
        [
            [
                sum(gelu[token][k] * weights[output][k] for k in range(base, base + WINDOW_OUTPUT_CHANNELS))
                for output in range(FC2_OUTPUT_CHANNELS)
            ]
            for token in range(TOKENS)
        ]
        for base in range(0, OUTPUT_CHANNELS, WINDOW_OUTPUT_CHANNELS)
    ]


def write_include(
    path: Path,
    expected: list[list[int]],
    bias: list[int],
    multiplier: int,
    shift: int,
    lut: list[int],
    gelu: list[list[int]],
    fc2_weights: list[list[int]],
) -> None:
    lines = [
        "/* Generated by prepare_tinyvit_fc1_k128.py; do not edit. */",
        f".equ TINYVIT_FC1_K128_CHUNKS, {INPUT_CHANNELS // CHUNK_K}",
        f".equ TINYVIT_FC1_K128_OUTPUT_WINDOWS, {OUTPUT_WINDOWS}",
        f".equ TINYVIT_FC1_K128_OUTPUT_TILES, {WINDOW_OUTPUT_CHANNELS // OUTPUT_TILE_CHANNELS}",
        f".equ TINYVIT_FC1_K128_OUTPUT_CHANNELS, {OUTPUT_CHANNELS}",
        f".equ TINYVIT_FC1_K128_WEIGHT_CHUNK_STRIDE, {WINDOW_OUTPUT_CHANNELS * CHUNK_K}",
        f".equ TINYVIT_FC1_K128_GELU_REQUANT_MULTIPLIER, {multiplier}",
        f".equ TINYVIT_FC1_K128_GELU_REQUANT_SHIFT, {shift}",
        f".equ TINYVIT_FC1_K128_GELU_REQUANT_ROUND, {1 << (shift - 1)}",
        f".equ TINYVIT_FC2_K8_CHUNKS, {WINDOW_OUTPUT_CHANNELS // CHUNK_K}",
    ]
    lines.extend((".section .rodata", ".balign 4", "tinyvit_fc1_k128_expected:"))
    for output_base in range(0, OUTPUT_CHANNELS, OUTPUT_TILE_CHANNELS):
        for token in range(TOKENS):
            for output in range(output_base, output_base + OUTPUT_TILE_CHANNELS):
                lines.append(f"  .word {expected[token][output]}")
    lines.extend((".balign 4", "tinyvit_fc1_k128_bias:"))
    lines.extend(f"  .word {value}" for value in bias)
    lines.extend(("tinyvit_fc1_k128_gelu_expected:",))
    for output_base in range(0, OUTPUT_CHANNELS, OUTPUT_TILE_CHANNELS):
        for token in range(TOKENS):
            for output in range(output_base, output_base + OUTPUT_TILE_CHANNELS):
                lines.append(f"  .byte {gelu[token][output]}")
    lines.extend(("tinyvit_fc1_k128_gelu_lut:",))
    lines.extend(f"  .byte {value}" for value in lut)
    lines.extend((".balign 4", "tinyvit_fc2_k8_expected:"))
    for window in fc2_window_outputs(gelu, fc2_weights):
        for row in window:
            lines.extend(f"  .word {value}" for value in row)
    lines.append(".section .text.start")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_ram_hex(
    path: Path,
    inputs: list[list[int]],
    weights: list[list[int]],
    fc2_weights: list[list[int]],
    window: int,
) -> None:
    base = window * WINDOW_OUTPUT_CHANNELS
    weight_window = weights[base : base + WINDOW_OUTPUT_CHANNELS]
    fc2_weight_window = [row[base : base + WINDOW_OUTPUT_CHANNELS] for row in fc2_weights]
    sections = (
        (WINDOW_ID_RAM_WORD, [window]),
        (INPUT_RAM_WORD, chunk_words(inputs)),
        (WEIGHT_RAM_WORD, chunk_words(weight_window)),
        (FC2_WEIGHT_RAM_WORD, chunk_words(fc2_weight_window, WINDOW_OUTPUT_CHANNELS)),
    )
    lines: list[str] = []
    for address, words in sections:
        lines.append(f"@{address:08x}")
        lines.extend(f"{word:08x}" for word in words)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def self_test() -> None:
    root = Path(__file__).resolve().parents[1]
    raw = json.loads((root / "sw/baremetal/fixtures/tinyvit_mlp2_activation.json").read_text(encoding="ascii"))
    inputs, weights, expected, bias, multiplier, shift, lut, gelu, fc2_weights, fc2_expected = validate(raw)
    assert expected[0][:4] == [-9095, -3141, 1800, 372]
    assert expected[0][-4:] == [198, 816, 3664, 1989]
    assert expected[1][:4] == [3440, -3172, 5054, -13]
    assert expected[1][-4:] == [1311, 2540, 3951, 3695]
    assert len(chunk_words(inputs)) == 64
    assert len(chunk_words(weights)) == 1024
    assert bias[:4] == [-3302, -3547, -1956, -1551]
    assert bias[-4:] == [-4185, -4120, -592, -3046]
    assert multiplier == 313
    assert shift == 16
    assert gelu[0][:4] == [0, -3, 0, -2]
    assert gelu[0][-4:] == [-4, -4, 11, -2]
    assert gelu[1][:4] == [1, -3, 11, -3]
    assert gelu[1][-4:] == [-4, -3, 12, 2]
    assert fc2_weights[0][:4] == [12, 17, -50, 86]
    assert fc2_weights[0][-4:] == [-5, -122, 37, -99]
    assert fc2_weights[1][:4] == [0, 65, 27, -64]
    assert fc2_weights[1][-4:] == [56, 90, 1, 16]
    assert fc2_expected == [[5422, -1028], [1670, -906]]
    window_outputs = fc2_window_outputs(gelu, fc2_weights)
    assert window_outputs == [
        [[1647, 196], [-512, -69]],
        [[3775, -1224], [2182, -837]],
    ]
    assert [
        [sum(window[token][output] for window in window_outputs) for output in range(FC2_OUTPUT_CHANNELS)]
        for token in range(TOKENS)
    ] == fc2_expected
    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / "fixture.inc"
        write_include(
            output,
            expected,
            bias,
            multiplier,
            shift,
            lut,
            gelu,
            fc2_weights,
        )
        generated = output.read_text(encoding="ascii")
        assert ".equ TINYVIT_FC1_K128_CHUNKS, 16" in generated
        assert ".equ TINYVIT_FC1_K128_OUTPUT_WINDOWS, 2" in generated
        assert ".equ TINYVIT_FC1_K128_OUTPUT_TILES, 8" in generated
        assert ".equ TINYVIT_FC2_K8_CHUNKS, 2" in generated
        assert "tinyvit_fc2_k8_expected:" in generated
        assert "tinyvit_fc1_k128_inputs:" not in generated
        assert "tinyvit_fc1_k128_weights:" not in generated
        assert "tinyvit_fc2_k8_weights:" not in generated
        for window in range(OUTPUT_WINDOWS):
            ram_output = Path(directory) / f"fixture_ram_window{window}.hex"
            write_ram_hex(ram_output, inputs, weights, fc2_weights, window)
            generated_ram = ram_output.read_text(encoding="ascii")
            expected_ram_lines = 5 + len(chunk_words(inputs)) + len(
                chunk_words(weights[window * WINDOW_OUTPUT_CHANNELS : (window + 1) * WINDOW_OUTPUT_CHANNELS])
            ) + len(
                chunk_words(
                    [
                        row[window * WINDOW_OUTPUT_CHANNELS : (window + 1) * WINDOW_OUTPUT_CHANNELS]
                        for row in fc2_weights
                    ],
                    WINDOW_OUTPUT_CHANNELS,
                )
            )
            assert len(generated_ram.splitlines()) == expected_ram_lines
            assert f"@0000003c\n{window:08x}\n" in generated_ram
            assert "@00000040\n" in generated_ram
            assert "@00000080\n" in generated_ram
            assert "@00000288\n" in generated_ram


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path, nargs="?")
    parser.add_argument("--asm", type=Path)
    parser.add_argument("--ram-hex", type=Path)
    parser.add_argument("--window", type=int, choices=range(OUTPUT_WINDOWS))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            if args.fixture or args.asm or args.ram_hex or args.window is not None:
                parser.error("--self-test does not accept fixture output arguments")
            self_test()
        elif not args.fixture or not args.asm or not args.ram_hex or args.window is None:
            parser.error("fixture, --asm, --ram-hex, and --window are required")
        else:
            inputs, weights, expected, bias, multiplier, shift, lut, gelu, fc2_weights, fc2_expected = validate(
                json.loads(args.fixture.read_text(encoding="ascii"))
            )
            write_include(
                args.asm,
                expected,
                bias,
                multiplier,
                shift,
                lut,
                gelu,
                fc2_weights,
            )
            write_ram_hex(args.ram_hex, inputs, weights, fc2_weights, args.window)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"TinyViT FC1 K=128 fixture failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
