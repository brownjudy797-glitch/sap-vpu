#!/usr/bin/env python3
"""Check the bounded SAP-VPU tiled-GEMM numerical and address contract."""

from __future__ import annotations

import json
from pathlib import Path

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


def self_test() -> None:
    root = Path(__file__).resolve().parents[1]
    fixture = validate_fixture(
        json.loads((root / "sw/baremetal/fixtures/tinyvit_mlp2_smoke.json").read_text(encoding="utf-8"))
    )
    hidden_acc, _ = tiled_gemm(fixture["input_tokens"], transpose(fixture["fc1_weights"]))
    hidden = [[requantize_int8(value, 1, 0, relu=True) for value in row] for row in hidden_acc]
    output, _ = tiled_gemm(hidden, transpose(fixture["fc2_weights"]))
    assert output == [[20, 16], [20, 14]]

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


if __name__ == "__main__":
    self_test()
    print("tiled GEMM reference self-test: PASS")
