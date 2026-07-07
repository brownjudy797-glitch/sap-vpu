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
    "operand_reads",
    "weight_reads",
    "ram_tile_reads",
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


def dense_baseline(rows: list[dict[str, str]]) -> dict[str, str]:
    for row in rows:
        if row["kernel"] == "dense":
            if as_int(row, "cycle_delta") <= 0:
                break
            return row
    raise ValueError("missing nonzero dense baseline cycle count")


def dense_speedup(row: dict[str, str], baseline: dict[str, str]) -> float:
    cycles = as_int(row, "cycle_delta")
    baseline_mac = as_int(baseline, "mac_active")
    if cycles <= 0 or baseline_mac <= 0:
        return 0.0
    normalized_dense_cycles = as_int(baseline, "cycle_delta") * as_int(row, "mac_active") / baseline_mac
    return normalized_dense_cycles / cycles


def traffic_bytes(row: dict[str, str]) -> tuple[int, int, int]:
    operand_bytes = as_int(row, "operand_reads") * 4
    weight_bytes = as_int(row, "weight_reads") * 4
    partial_sum_bytes = as_int(row, "mac_active") * 4
    return operand_bytes, weight_bytes, partial_sum_bytes


def validate_traffic(row: dict[str, str]) -> None:
    operand_reads = as_int(row, "operand_reads")
    weight_reads = as_int(row, "weight_reads")
    ram_tile_reads = as_int(row, "ram_tile_reads")
    if operand_reads + weight_reads != ram_tile_reads:
        raise ValueError(
            f"{row['kernel']} operand_reads + weight_reads does not match ram_tile_reads"
        )


def self_test() -> int:
    rows = [
        {
            "kernel": "dense",
            "precision": "int8",
            "sparse": "none",
            "mac_active": "512",
            "sparse_state": "0",
            "lane_state": "4",
            "operand_reads": "256",
            "weight_reads": "512",
            "ram_tile_reads": "768",
        },
        {
            "kernel": "dense_reuse",
            "precision": "int8",
            "sparse": "none",
            "mac_active": "512",
            "sparse_state": "0",
            "lane_state": "4",
            "operand_reads": "256",
            "weight_reads": "256",
            "ram_tile_reads": "512",
        },
        {
            "kernel": "dense_x4",
            "precision": "int8",
            "sparse": "none",
            "mac_active": "2048",
            "sparse_state": "0",
            "lane_state": "4",
            "operand_reads": "1024",
            "weight_reads": "2048",
            "ram_tile_reads": "3072",
        },
        {
            "kernel": "adaptive",
            "precision": "int4",
            "sparse": "bitmap",
            "mac_active": "512",
            "sparse_state": "15",
            "lane_state": "4",
            "operand_reads": "256",
            "weight_reads": "512",
            "ram_tile_reads": "768",
        },
        {
            "kernel": "adaptive_reuse",
            "precision": "int4",
            "sparse": "bitmap_reuse",
            "mac_active": "512",
            "sparse_state": "15",
            "lane_state": "4",
            "operand_reads": "256",
            "weight_reads": "256",
            "ram_tile_reads": "512",
        },
        {
            "kernel": "adaptive_sparse75",
            "precision": "int4",
            "sparse": "bitmap_sparse75",
            "mac_active": "512",
            "sparse_state": "3",
            "lane_state": "2",
            "operand_reads": "256",
            "weight_reads": "512",
            "ram_tile_reads": "768",
        },
        {
            "kernel": "no_lane_gating",
            "precision": "int4",
            "sparse": "bitmap",
            "mac_active": "512",
            "sparse_state": "15",
            "lane_state": "8",
            "operand_reads": "256",
            "weight_reads": "512",
            "ram_tile_reads": "768",
        },
        {
            "kernel": "adaptive_unstructured",
            "precision": "int4",
            "sparse": "bitmap_unstructured",
            "mac_active": "512",
            "sparse_state": "85",
            "lane_state": "8",
            "operand_reads": "256",
            "weight_reads": "512",
            "ram_tile_reads": "768",
        },
        {
            "kernel": "static_int2",
            "precision": "int2",
            "sparse": "none",
            "mac_active": "512",
            "sparse_state": "65535",
            "lane_state": "16",
            "operand_reads": "256",
            "weight_reads": "512",
            "ram_tile_reads": "768",
        },
    ]
    rows[0]["skip"] = "0"
    rows[0]["cycle_delta"] = "100"
    rows[1]["skip"] = "0"
    rows[2]["skip"] = "0"
    rows[2]["cycle_delta"] = "400"
    rows[3]["skip"] = "2048"
    rows[4]["skip"] = "2048"
    rows[5]["skip"] = "3072"
    rows[6]["skip"] = "2048"
    rows[7]["skip"] = "2048"
    rows[8]["skip"] = "0"
    assert product_counts(rows[0]) == ProductCounts(4, 2048, 2048, 0)
    assert product_counts(rows[1]) == ProductCounts(4, 2048, 2048, 0)
    assert product_counts(rows[2]) == ProductCounts(4, 8192, 8192, 0)
    assert product_counts(rows[3]) == ProductCounts(8, 4096, 2048, 2048)
    assert product_counts(rows[4]) == ProductCounts(8, 4096, 2048, 2048)
    assert product_counts(rows[5]) == ProductCounts(8, 4096, 1024, 3072)
    assert product_counts(rows[6]) == ProductCounts(8, 4096, 2048, 2048)
    assert product_counts(rows[7]) == ProductCounts(8, 4096, 2048, 2048)
    assert product_counts(rows[8]) == ProductCounts(16, 8192, 8192, 0)
    assert skip_ratio(rows[3]) == 0.5
    assert skip_ratio(rows[5]) == 0.75
    for row in rows:
        validate_traffic(row)
    assert traffic_bytes(rows[0]) == (1024, 2048, 2048)
    assert traffic_bytes(rows[1]) == (1024, 1024, 2048)
    assert traffic_bytes(rows[2]) == (4096, 8192, 8192)
    assert traffic_bytes(rows[3]) == (1024, 2048, 2048)
    assert dense_speedup(rows[2], rows[0]) == 1.0
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
        baseline = dense_baseline(rows)
        for row in rows:
            validate_traffic(row)
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
    print("## Memory Traffic Draft")
    print()
    print("| Kernel | Operand reads | Weight reads | RAM tile reads | Operand bytes | Weight bytes | Partial sum bytes | Total bytes |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for row in rows:
        operand_bytes, weight_bytes, partial_sum_bytes = traffic_bytes(row)
        total_bytes = operand_bytes + weight_bytes + partial_sum_bytes
        print(
            f"| {row['kernel']} | {as_int(row, 'operand_reads')} | {as_int(row, 'weight_reads')} | "
            f"{as_int(row, 'ram_tile_reads')} | {operand_bytes} | {weight_bytes} | "
            f"{partial_sum_bytes} | {total_bytes} |"
        )
    print()
    print("## Paper Table Draft")
    print()
    print("| Kernel | Precision | Sparse | Output | Cycles | Dense-normalized speedup | Skip ratio | Active lanes | RAM tile reads | Operand bytes | Weight bytes | Partial sum bytes | Total bytes |")
    print("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for row in rows:
        cycles = as_int(row, "cycle_delta")
        speedup = dense_speedup(row, baseline)
        operand_bytes, weight_bytes, partial_sum_bytes = traffic_bytes(row)
        total_bytes = operand_bytes + weight_bytes + partial_sum_bytes
        print(
            f"| {row['kernel']} | {row['precision']} | {row['sparse']} | "
            f"{as_int(row, 'output')} | {cycles} | {speedup:.3f} | "
            f"{skip_ratio(row):.3f} | {as_int(row, 'lane_state')} | "
            f"{as_int(row, 'ram_tile_reads')} | {operand_bytes} | {weight_bytes} | "
            f"{partial_sum_bytes} | {total_bytes} |"
        )
    print()
    print("Dense-normalized speedup scales the dense baseline by VDOT count; use this as table plumbing, not as a paper claim.")
    print("Skip ratio is product-level: skipped products divided by active plus skipped products.")
    print("Traffic uses observed RAM tile operand/weight reads from the testbench plus one partial-sum word per VDOT.")
    print()
    print("Use this smoke table as a functional counter sanity check only; paper-facing tables need expanded kernels and policies.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
