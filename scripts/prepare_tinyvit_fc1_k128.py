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
OUTPUT_CHANNELS = 16
CHUNK_K = 8
OUTPUT_TILE_CHANNELS = 2
POSTPROCESS_BOUNDARY = "cv32e40x-int32-bias-q16-requant-int8-gelu-lut"
FC2_OUTPUT_CHANNELS = 2
FC2_BOUNDARY = "sap-vpu-int8-fc2-k8-chunked-partial-no-bias"
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
        raise ValueError("expected_integer_output must have shape [2, 2]")
    expected = [list(row) for row in expected]
    if any(len(row) != OUTPUT_CHANNELS or any(not isinstance(item, int) for item in row) for row in expected):
        raise ValueError("expected_integer_output must have integer shape [2, 2]")
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
        raise ValueError("bias_accumulator must have sixteen integer entries")
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


def write_include(
    path: Path,
    expected: list[list[int]],
    bias: list[int],
    multiplier: int,
    shift: int,
    lut: list[int],
    gelu: list[list[int]],
    fc2_expected: list[list[int]],
) -> None:
    lines = [
        "/* Generated by prepare_tinyvit_fc1_k128.py; do not edit. */",
        f".equ TINYVIT_FC1_K128_CHUNKS, {INPUT_CHANNELS // CHUNK_K}",
        f".equ TINYVIT_FC1_K128_OUTPUT_TILES, {OUTPUT_CHANNELS // OUTPUT_TILE_CHANNELS}",
        f".equ TINYVIT_FC1_K128_OUTPUT_CHANNELS, {OUTPUT_CHANNELS}",
        f".equ TINYVIT_FC1_K128_WEIGHT_CHUNK_STRIDE, {OUTPUT_CHANNELS * CHUNK_K}",
        f".equ TINYVIT_FC1_K128_GELU_REQUANT_MULTIPLIER, {multiplier}",
        f".equ TINYVIT_FC1_K128_GELU_REQUANT_SHIFT, {shift}",
        f".equ TINYVIT_FC1_K128_GELU_REQUANT_ROUND, {1 << (shift - 1)}",
        f".equ TINYVIT_FC2_K8_CHUNKS, {OUTPUT_CHANNELS // CHUNK_K}",
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
    for row in fc2_expected:
        lines.extend(f"  .word {value}" for value in row)
    lines.append(".section .text.start")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_ram_hex(
    path: Path,
    inputs: list[list[int]],
    weights: list[list[int]],
    fc2_weights: list[list[int]],
) -> None:
    sections = (
        (INPUT_RAM_WORD, chunk_words(inputs)),
        (WEIGHT_RAM_WORD, chunk_words(weights)),
        (FC2_WEIGHT_RAM_WORD, chunk_words(fc2_weights, OUTPUT_CHANNELS)),
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
    assert expected == [
        [-15845, -5456, 3075, 943, -1370, 715, 11209, -8424, -4475, -3972, 11381, -5131, 3375, -5134, 1806, -1236],
        [6267, -5774, 8916, 191, -3782, 2786, 5524, -16160, -10913, -5946, 6177, 5379, -1361, -598, 270, 1400],
    ]
    assert len(chunk_words(inputs)) == 64
    assert len(chunk_words(weights)) == 512
    assert bias == [
        -5833, -6266, -3455, -2741, -6652, -11972, -10559, 2681,
        -9777, -9621, -5934, -9119, -5243, -5035, -13484, -10168,
    ]
    assert multiplier == 387
    assert shift == 16
    assert gelu == [
        [-1, -6, -1, -5, -8, -6, 2, -9, -4, -5, 24, -4, -5, -7, -6, -6],
        [2, -6, 24, -6, -7, -8, -8, -5, -1, -3, 1, -7, -9, -9, -5, -8],
    ]
    assert fc2_weights == [
        [12, 17, -50, 86, 10, -48, 51, -69, 13, 14, 127, -23, -28, -6, -28, 36],
        [0, 65, 27, -64, 59, -28, 18, -32, -40, 101, 40, -23, -29, 67, -66, 50],
    ]
    assert fc2_expected == [[3589, 402], [-1152, -5]]
    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / "fixture.inc"
        ram_output = Path(directory) / "fixture_ram.hex"
        write_include(
            output,
            expected,
            bias,
            multiplier,
            shift,
            lut,
            gelu,
            fc2_expected,
        )
        write_ram_hex(ram_output, inputs, weights, fc2_weights)
        generated = output.read_text(encoding="ascii")
        generated_ram = ram_output.read_text(encoding="ascii")
        assert ".equ TINYVIT_FC1_K128_CHUNKS, 16" in generated
        assert ".equ TINYVIT_FC1_K128_OUTPUT_TILES, 8" in generated
        assert ".equ TINYVIT_FC2_K8_CHUNKS, 2" in generated
        assert "tinyvit_fc2_k8_expected:" in generated
        assert "tinyvit_fc1_k128_inputs:" not in generated
        assert "tinyvit_fc1_k128_weights:" not in generated
        assert "tinyvit_fc2_k8_weights:" not in generated
        expected_ram_lines = 3 + len(chunk_words(inputs)) + len(chunk_words(weights)) + len(
            chunk_words(fc2_weights, OUTPUT_CHANNELS)
        )
        assert len(generated_ram.splitlines()) == expected_ram_lines
        assert "@00000040\n" in generated_ram
        assert "@00000080\n" in generated_ram
        assert "@00000288\n" in generated_ram


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path, nargs="?")
    parser.add_argument("--asm", type=Path)
    parser.add_argument("--ram-hex", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            if args.fixture or args.asm or args.ram_hex:
                parser.error("--self-test does not accept fixture output arguments")
            self_test()
        elif not args.fixture or not args.asm or not args.ram_hex:
            parser.error("fixture, --asm, and --ram-hex are required")
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
                fc2_expected,
            )
            write_ram_hex(args.ram_hex, inputs, weights, fc2_weights)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"TinyViT FC1 K=128 fixture failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
