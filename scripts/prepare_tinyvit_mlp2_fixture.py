#!/usr/bin/env python3
"""Validate and materialize a fixed-shape INT8 TinyViT MLP projection fixture."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import sys
import tempfile
from typing import Any


SCHEMA = "sap-vpu-tinyvit-mlp2-int8-v1"
TOKENS = 2
INPUT_CHANNELS = 4
HIDDEN_CHANNELS = 4
OUTPUT_CHANNELS = 2
ITERATIONS = 16


def fail(message: str) -> ValueError:
    return ValueError(f"invalid TinyViT MLP2 fixture: {message}")


def require_mapping(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise fail(f"{name} must be an object")
    return value


def require_string(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise fail(f"{name} must be a non-empty string")
    return value


def require_matrix(value: Any, name: str, rows: int, columns: int) -> list[list[int]]:
    if not isinstance(value, list) or len(value) != rows:
        raise fail(f"{name} must have shape [{rows}, {columns}]")
    matrix: list[list[int]] = []
    for row_index, row in enumerate(value):
        if not isinstance(row, list) or len(row) != columns:
            raise fail(f"{name}[{row_index}] must have {columns} entries")
        checked_row: list[int] = []
        for column_index, element in enumerate(row):
            if not isinstance(element, int) or isinstance(element, bool):
                raise fail(f"{name}[{row_index}][{column_index}] must be an integer")
            if not -128 <= element <= 127:
                raise fail(f"{name}[{row_index}][{column_index}] must fit signed INT8")
            checked_row.append(element)
        matrix.append(checked_row)
    return matrix


def validate_fixture(raw: Any) -> dict[str, Any]:
    fixture = require_mapping(raw, "root")
    if fixture.get("schema") != SCHEMA:
        raise fail(f"schema must be {SCHEMA!r}")

    provenance = require_mapping(fixture.get("provenance"), "provenance")
    kind = require_string(provenance.get("kind"), "provenance.kind")
    if kind not in {"smoke", "checkpoint"}:
        raise fail("provenance.kind must be 'smoke' or 'checkpoint'")
    for key in ("model_id", "layer_id", "checkpoint_sha256"):
        require_string(provenance.get(key), f"provenance.{key}")
    if kind == "checkpoint" and not re.fullmatch(r"[0-9a-fA-F]{64}", provenance["checkpoint_sha256"]):
        raise fail("checkpoint provenance requires a 64-character checkpoint_sha256")

    quantization = require_mapping(fixture.get("quantization"), "quantization")
    if quantization.get("scheme") != "symmetric-int8":
        raise fail("quantization.scheme must be 'symmetric-int8'")
    for key in ("input_zero_point", "fc1_weight_zero_point", "fc2_weight_zero_point"):
        if quantization.get(key) != 0:
            raise fail(f"quantization.{key} must be zero")
    for key in ("input_scale", "fc1_weight_scale", "fc2_weight_scale"):
        value = quantization.get(key)
        if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or value <= 0:
            raise fail(f"quantization.{key} must be a finite positive number")

    return {
        "schema": SCHEMA,
        "provenance": provenance,
        "quantization": quantization,
        "input_tokens": require_matrix(fixture.get("input_tokens"), "input_tokens", TOKENS, INPUT_CHANNELS),
        "fc1_weights": require_matrix(fixture.get("fc1_weights"), "fc1_weights", HIDDEN_CHANNELS, INPUT_CHANNELS),
        "fc2_weights": require_matrix(fixture.get("fc2_weights"), "fc2_weights", OUTPUT_CHANNELS, HIDDEN_CHANNELS),
    }


def dot(lhs: list[int], rhs: list[int]) -> int:
    return sum(left * right for left, right in zip(lhs, rhs))


def pack_int8(values: list[int], name: str) -> int:
    if len(values) != 4:
        raise ValueError(f"{name} must contain four values")
    packed = 0
    for index, value in enumerate(values):
        packed |= (value & 0xff) << (8 * index)
    return packed


def evaluate(fixture: dict[str, Any]) -> tuple[list[int], int, list[list[int]]]:
    words = [pack_int8(row, f"input_tokens[{index}]") for index, row in enumerate(fixture["input_tokens"])]
    words.extend(pack_int8(row, f"fc1_weights[{index}]") for index, row in enumerate(fixture["fc1_weights"]))
    words.extend(pack_int8(row, f"fc2_weights[{index}]") for index, row in enumerate(fixture["fc2_weights"]))

    outputs: list[list[int]] = []
    total = 0
    for token_index, token in enumerate(fixture["input_tokens"]):
        hidden = [max(0, dot(token, weight)) for weight in fixture["fc1_weights"]]
        for hidden_index, value in enumerate(hidden):
            if value > 127:
                raise fail(f"ReLU hidden activation token {token_index}, channel {hidden_index} exceeds signed INT8")
        output = [dot(hidden, weight) for weight in fixture["fc2_weights"]]
        outputs.append(output)
        total += sum(output)

    expected = total * ITERATIONS
    if not -(1 << 31) <= expected < (1 << 31):
        raise fail("expected accumulated output must fit signed 32-bit")
    return words, expected, outputs


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="ascii")


def write_artifacts(fixture: dict[str, Any], asm_path: Path, svh_path: Path, metadata_path: Path) -> None:
    words, expected, outputs = evaluate(fixture)
    names = ("token0", "token1", "hidden_weight0", "hidden_weight1", "hidden_weight2", "hidden_weight3", "output_weight0", "output_weight1")
    asm_lines = [
        "/* Generated by prepare_tinyvit_mlp2_fixture.py; do not edit. */",
        f".equ TINYVIT_MLP2_EXPECTED_OUTPUT, {expected}",
    ]
    for index, (name, word) in enumerate(zip(names, words)):
        asm_lines.extend((f"li t0, 0x{word:08x} /* {name} */", f"sw t0, TILE_MLP2_BASE + {index * 4}(a1)"))
    write_text(asm_path, "\n".join(asm_lines) + "\n")
    write_text(
        svh_path,
        "// Generated by prepare_tinyvit_mlp2_fixture.py; do not edit.\n"
        f"localparam logic [31:0] TINYVIT_MLP2_EXPECTED_OUTPUT = 32'h{expected & 0xffffffff:08x};\n",
    )
    metadata = {
        "schema": SCHEMA,
        "provenance": fixture["provenance"],
        "quantization": fixture["quantization"],
        "shape": {"tokens": TOKENS, "input_channels": INPUT_CHANNELS, "hidden_channels": HIDDEN_CHANNELS, "output_channels": OUTPUT_CHANNELS},
        "iterations": ITERATIONS,
        "per_token_integer_output": outputs,
        "expected_accumulated_integer_output": expected,
    }
    metadata_path.parent.mkdir(parents=True, exist_ok=True)
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="ascii")


def self_test() -> int:
    root = Path(__file__).resolve().parents[1]
    fixture = validate_fixture(json.loads((root / "sw/baremetal/fixtures/tinyvit_mlp2_smoke.json").read_text(encoding="utf-8")))
    words, expected, outputs = evaluate(fixture)
    assert words == [0x04030201, 0x01020304, 0x01010101, 0x00010001, 0x01000100, 0x0000FFFF, 0x01010101, 0x00010001]
    assert expected == 1120
    assert outputs == [[20, 16], [20, 14]]
    with tempfile.TemporaryDirectory() as temporary_directory:
        temporary = Path(temporary_directory)
        write_artifacts(fixture, temporary / "fixture.inc", temporary / "fixture.svh", temporary / "fixture.json")
        assert "TINYVIT_MLP2_EXPECTED_OUTPUT, 1120" in (temporary / "fixture.inc").read_text(encoding="ascii")
        assert "32'h00000460" in (temporary / "fixture.svh").read_text(encoding="ascii")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path, nargs="?", help="JSON fixture to validate and materialize")
    parser.add_argument("--asm", type=Path, help="generated assembler include path")
    parser.add_argument("--svh", type=Path, help="generated SystemVerilog include path")
    parser.add_argument("--metadata", type=Path, help="generated metadata JSON path")
    parser.add_argument("--self-test", action="store_true", help="validate the tracked smoke fixture and generator")
    args = parser.parse_args()
    if args.self_test:
        if args.fixture or args.asm or args.svh or args.metadata:
            parser.error("--self-test does not accept fixture output arguments")
    elif not (args.fixture and args.asm and args.svh and args.metadata):
        parser.error("fixture, --asm, --svh, and --metadata are required")
    return args


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    try:
        fixture = validate_fixture(json.loads(args.fixture.read_text(encoding="utf-8")))
        write_artifacts(fixture, args.asm, args.svh, args.metadata)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
