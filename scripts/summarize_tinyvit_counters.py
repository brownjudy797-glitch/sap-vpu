#!/usr/bin/env python3
"""Summarize TinyViT smoke counter CSV as a small Markdown table."""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path
import sys


REQUIRED_COLUMNS = (
    "kernel",
    "precision",
    "sparse",
    "output",
    "mac_active",
    "skip",
    "sparse_state",
    "lane_state",
    "cycle_delta",
    "instret_delta",
)

PRECISION_LANES = {
    "int8": 4,
    "int4": 8,
    "int2": 16,
}


@dataclass(frozen=True)
class ProductCounts:
    vector_lanes: int
    issued_total: int
    active_total: int
    skipped_total: int


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        missing = [column for column in REQUIRED_COLUMNS if column not in (reader.fieldnames or [])]
        if missing:
            raise ValueError(f"missing columns: {', '.join(missing)}")
        return list(reader)


def as_int(row: dict[str, str], key: str) -> int:
    return int(row[key], 0)


def skip_ratio(row: dict[str, str]) -> float:
    counts = product_counts(row)
    active = counts.active_total
    skipped = counts.skipped_total
    total = active + skipped
    return skipped / total if total else 0.0


def vector_lanes(row: dict[str, str]) -> int:
    try:
        return PRECISION_LANES[row["precision"].lower()]
    except KeyError as exc:
        raise ValueError(f"unsupported precision: {row['precision']}") from exc


def product_counts(row: dict[str, str]) -> ProductCounts:
    lanes = vector_lanes(row)
    dot_ops = as_int(row, "mac_active")
    skipped_total = as_int(row, "skip")
    issued_total = dot_ops * lanes
    return ProductCounts(
        vector_lanes=lanes,
        issued_total=issued_total,
        active_total=issued_total - skipped_total,
        skipped_total=skipped_total,
    )


def dense_cycles(rows: list[dict[str, str]]) -> int:
    for row in rows:
        if row["kernel"] == "dense":
            cycles = as_int(row, "cycle_delta")
            if cycles <= 0:
                break
            return cycles
    raise ValueError("missing nonzero dense baseline cycle count")


def traffic_bytes(row: dict[str, str]) -> tuple[int, int, int]:
    dot_ops = as_int(row, "mac_active")
    operand_bytes = dot_ops * 4
    weight_bytes = dot_ops * 4
    partial_sum_bytes = dot_ops * 4
    return operand_bytes, weight_bytes, partial_sum_bytes


def self_test() -> int:
    rows = [
        {
            "kernel": "dense",
            "precision": "int8",
            "sparse": "none",
            "mac_active": "64",
            "sparse_state": "0",
            "lane_state": "4",
        },
        {
            "kernel": "adaptive",
            "precision": "int4",
            "sparse": "bitmap",
            "mac_active": "32",
            "sparse_state": "15",
            "lane_state": "4",
        },
        {
            "kernel": "no_lane_gating",
            "precision": "int4",
            "sparse": "bitmap",
            "mac_active": "32",
            "sparse_state": "15",
            "lane_state": "8",
        },
    ]
    rows[0]["skip"] = "0"
    rows[1]["skip"] = "128"
    rows[2]["skip"] = "128"
    assert product_counts(rows[0]) == ProductCounts(4, 256, 256, 0)
    assert product_counts(rows[1]) == ProductCounts(8, 256, 128, 128)
    assert product_counts(rows[2]) == ProductCounts(8, 256, 128, 128)
    assert skip_ratio(rows[1]) == 0.5
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()

    csv_path = Path(sys.argv[1] if len(sys.argv) > 1 else "work/tinyvit/tinyvit_smoke_counters.csv")
    if not csv_path.exists():
        print(f"Missing TinyViT counter CSV: {csv_path}", file=sys.stderr)
        return 2

    try:
        rows = read_rows(csv_path)
    except ValueError as exc:
        print(f"Invalid TinyViT counter CSV: {exc}", file=sys.stderr)
        return 2

    if not rows:
        print(f"Empty TinyViT counter CSV: {csv_path}", file=sys.stderr)
        return 2

    try:
        baseline_cycles = dense_cycles(rows)
    except ValueError as exc:
        print(f"Invalid TinyViT counter CSV: {exc}", file=sys.stderr)
        return 2

    print("# TinyViT Kernel Counter Summary")
    print()
    print(f"Source: `{csv_path}`")
    print()
    print("| Kernel | Precision | Sparse | Output | MAC active | Skip | Skip ratio | Sparse state | Lane state | Cycles | Instructions |")
    print("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for row in rows:
        print(
            f"| {row['kernel']} | {row['precision']} | {row['sparse']} | "
            f"{as_int(row, 'output')} | {as_int(row, 'mac_active')} | {as_int(row, 'skip')} | "
            f"{skip_ratio(row):.3f} | {as_int(row, 'sparse_state')} | {as_int(row, 'lane_state')} | "
            f"{as_int(row, 'cycle_delta')} | {as_int(row, 'instret_delta')} |"
        )
    print()
    print("## Compute Shape Draft")
    print()
    print("| Kernel | Vector lanes | VDOT ops | Active products | Skipped products | Active products/cycle |")
    print("| --- | ---: | ---: | ---: | ---: | ---: |")
    for row in rows:
        counts = product_counts(row)
        cycles = as_int(row, "cycle_delta")
        products_per_cycle = counts.active_total / cycles if cycles else 0.0
        print(
            f"| {row['kernel']} | {counts.vector_lanes} | {as_int(row, 'mac_active')} | "
            f"{counts.active_total} | {counts.skipped_total} | {products_per_cycle:.3f} |"
        )
    print()
    print("## Paper Table Draft")
    print()
    print("| Kernel | Precision | Sparse | Output | Cycles | Dense speedup | Skip ratio | Active lanes | Operand bytes | Weight bytes | Partial sum bytes | Total bytes |")
    print("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for row in rows:
        cycles = as_int(row, "cycle_delta")
        speedup = baseline_cycles / cycles if cycles else 0.0
        operand_bytes, weight_bytes, partial_sum_bytes = traffic_bytes(row)
        total_bytes = operand_bytes + weight_bytes + partial_sum_bytes
        print(
            f"| {row['kernel']} | {row['precision']} | {row['sparse']} | "
            f"{as_int(row, 'output')} | {cycles} | {speedup:.3f} | "
            f"{skip_ratio(row):.3f} | {as_int(row, 'lane_state')} | "
            f"{operand_bytes} | {weight_bytes} | {partial_sum_bytes} | {total_bytes} |"
        )
    print()
    print("Dense speedup is local to this smoke counter run; use this as table plumbing, not as a paper claim.")
    print("Skip ratio is product-level: skipped products divided by active plus skipped products.")
    print("Traffic is a packed-register estimate for the smoke kernel, not a final SRAM/cache traffic model.")
    print()
    print("Use this smoke table as a functional counter sanity check only; paper-facing tables need expanded kernels and policies.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
