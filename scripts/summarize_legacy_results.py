#!/usr/bin/env python3
"""Summarize legacy nutvpu result CSVs without copying them into this repo."""

from __future__ import annotations

import csv
from pathlib import Path
import sys


def rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def as_float(row: dict[str, str], key: str) -> float:
    return float(row[key])


def main() -> int:
    result_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "../nutvpu/results").expanduser()
    result_dir = result_dir.resolve()
    needed = {
        "sparse": result_dir / "tinyvit_mlp_sparse_comparison_2026-06-14.csv",
        "zero_bypass": result_dir / "tinyvit_mlp_rtl_zero_bypass_comparison_2026-06-14.csv",
        "area": result_dir / "dc_rtl_zero_bypass_comparison_2026-06-14.csv",
    }
    missing = [str(path) for path in needed.values() if not path.exists()]
    if missing:
      print("Missing legacy result files:")
      for path in missing:
          print(f"- {path}")
      return 2

    sparse_rows = rows(needed["sparse"])
    best_sparse = max(sparse_rows, key=lambda row: as_float(row, "speedup"))
    worst_sparse = min(sparse_rows, key=lambda row: as_float(row, "speedup"))

    zero_rows = rows(needed["zero_bypass"])
    zero_speedups = [as_float(row, "software_rtl_speedup") for row in zero_rows]
    active_changes = sorted({row["active_cycle_change_pct"] for row in zero_rows})

    area_rows = {row["metric"]: row for row in rows(needed["area"])}
    total_area = area_rows["total_cell_area"]

    print("# Legacy nutvpu Result Summary")
    print()
    print(f"Source: `{result_dir}`")
    print()
    print("| Evidence | Summary |")
    print("| --- | --- |")
    print(
        "| Structured sparse best case | "
        f"{best_sparse['layer']} {best_sparse['precision']} {best_sparse['mode']} "
        f"sparsity_x10={best_sparse['target_sparsity_x10']} "
        f"speedup={best_sparse['speedup']}x, cycle_reduction={best_sparse['cycle_reduction_pct']}% |"
    )
    print(
        "| Sparse worst case | "
        f"{worst_sparse['layer']} {worst_sparse['precision']} {worst_sparse['mode']} "
        f"sparsity_x10={worst_sparse['target_sparsity_x10']} "
        f"speedup={worst_sparse['speedup']}x, cycle_reduction={worst_sparse['cycle_reduction_pct']}% |"
    )
    print(
        "| RTL zero-bypass software speedup | "
        f"min={min(zero_speedups):.3f}x, avg={sum(zero_speedups) / len(zero_speedups):.3f}x, "
        f"max={max(zero_speedups):.3f}x; active_cycle_change_pct={','.join(active_changes)} |"
    )
    print(
        "| DC total cell area delta | "
        f"{total_area['baseline_2026-06-12']} -> {total_area['rtl_zero_bypass_2026-06-14']} "
        f"({total_area['change_pct']}%) |"
    )
    print()
    print("Use these numbers as legacy baseline anchors only; paper-facing claims need reproduction in sap-vpu or an explicitly equivalent flow.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
