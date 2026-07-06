#!/usr/bin/env python3
"""Summarize SAP-VPU Vivado FPGA report outputs."""

from __future__ import annotations

import csv
from pathlib import Path
import re
import sys


def read_summary_csv(path: Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise ValueError(f"empty summary CSV: {path}")
    return rows[0]


def find_first_int(patterns: list[str], text: str) -> str:
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.MULTILINE)
        if match:
            return match.group(1)
    return "NA"


def parse_utilization(path: Path) -> dict[str, str]:
    if not path.exists():
        return {"lut": "NA", "ff": "NA", "dsp": "NA", "bram": "NA"}

    text = path.read_text(encoding="utf-8", errors="replace")
    return {
        "lut": find_first_int([r"\|\s*Slice LUTs\s*\|\s*([0-9,]+)\s*\|"], text),
        "ff": find_first_int([r"\|\s*Slice Registers\s*\|\s*([0-9,]+)\s*\|"], text),
        "dsp": find_first_int([r"\|\s*DSPs\s*\|\s*([0-9,]+)\s*\|", r"\|\s*DSP48E1\s*\|\s*([0-9,]+)\s*\|"], text),
        "bram": find_first_int([r"\|\s*Block RAM Tile\s*\|\s*([0-9.]+)\s*\|"], text),
    }


def parse_power(path: Path) -> str:
    if not path.exists():
        return "NA"
    text = path.read_text(encoding="utf-8", errors="replace")
    return find_first_int(
        [
            r"\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)\s*\|",
            r"Total On-Chip Power \(W\)\s*:\s*([0-9.]+)",
        ],
        text,
    )


def main() -> int:
    report_root = Path(sys.argv[1] if len(sys.argv) > 1 else "work/fpga/vpu_core")
    summary_csv = report_root / "fpga_vpu_summary.csv"
    if not summary_csv.exists():
        print(f"Missing FPGA summary CSV: {summary_csv}", file=sys.stderr)
        return 2

    try:
        summary = read_summary_csv(summary_csv)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    report_dir = report_root / "reports"
    util = parse_utilization(report_dir / "post_route_utilization.rpt")
    power_w = parse_power(report_dir / "post_route_power.rpt")

    print("# SAP-VPU FPGA Summary")
    print()
    print(f"Source: `{report_root}`")
    print()
    print("| Top | Part | Clock MHz | Period ns | Worst slack ns | LUT | FF | DSP | BRAM | Power W |")
    print("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    print(
        f"| {summary.get('top', 'NA')} | {summary.get('part', 'NA')} | "
        f"{summary.get('clock_mhz', 'NA')} | {summary.get('clock_period_ns', 'NA')} | "
        f"{summary.get('worst_slack_ns', 'NA')} | {util['lut']} | {util['ff']} | "
        f"{util['dsp']} | {util['bram']} | {power_w} |"
    )
    print()
    print("Power uses Vivado default switching unless a separate activity file is provided.")
    print("Treat standalone `sap_vpu_core` results as VPU-core FPGA evidence, not full SoC evidence.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
