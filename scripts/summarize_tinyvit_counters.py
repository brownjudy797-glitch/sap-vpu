#!/usr/bin/env python3
"""Summarize TinyViT smoke counter CSV as a small Markdown table."""

from __future__ import annotations

import csv
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
    active = as_int(row, "mac_active")
    skipped = as_int(row, "skip")
    total = active + skipped
    return skipped / total if total else 0.0


def dense_cycles(rows: list[dict[str, str]]) -> int:
    for row in rows:
        if row["kernel"] == "dense":
            cycles = as_int(row, "cycle_delta")
            if cycles <= 0:
                break
            return cycles
    raise ValueError("missing nonzero dense baseline cycle count")


def main() -> int:
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
    print("## Paper Table Draft")
    print()
    print("| Kernel | Precision | Sparse | Output | Cycles | Dense speedup | Skip ratio | Active lanes |")
    print("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |")
    for row in rows:
        cycles = as_int(row, "cycle_delta")
        speedup = baseline_cycles / cycles if cycles else 0.0
        print(
            f"| {row['kernel']} | {row['precision']} | {row['sparse']} | "
            f"{as_int(row, 'output')} | {cycles} | {speedup:.3f} | "
            f"{skip_ratio(row):.3f} | {as_int(row, 'lane_state')} |"
        )
    print()
    print("Dense speedup is local to this smoke counter run; use this as table plumbing, not as a paper claim.")
    print()
    print("Use this smoke table as a functional counter sanity check only; paper-facing tables need expanded kernels and policies.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
