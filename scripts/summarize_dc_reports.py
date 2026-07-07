#!/usr/bin/env python3
"""Summarize SAP-VPU Synopsys Design Compiler report outputs."""

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


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def find_first(patterns: list[str], text: str) -> str:
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.MULTILINE)
        if match:
            return match.group(1)
    return "NA"


def parse_area(path: Path) -> dict[str, str]:
    text = read_text(path)
    return {
        "cells": find_first([r"^\s*Number of cells:\s*([0-9.]+)"], text),
        "comb_area": find_first([r"^\s*Combinational area:\s*([0-9.]+)"], text),
        "seq_area": find_first([r"^\s*Noncombinational area:\s*([0-9.]+)"], text),
        "total_area": find_first([r"^\s*Total cell area:\s*([0-9.]+)"], text),
    }


def parse_qor(path: Path) -> dict[str, str]:
    text = read_text(path)
    return {
        "critical_slack": find_first(
            [r"^\s*Critical Path Slack:\s*([-+0-9.]+)"], text
        ),
        "critical_length": find_first(
            [r"^\s*Critical Path Length:\s*([-+0-9.]+)"], text
        ),
        "critical_period": find_first(
            [r"^\s*Critical Path Clk Period:\s*([-+0-9.]+)"], text
        ),
    }


def parse_power(path: Path, top: str) -> dict[str, str]:
    text = read_text(path)
    if not text:
        return {
            "internal_power": "NA",
            "switching_power": "NA",
            "leakage_power": "NA",
            "total_power": "NA",
        }

    total_match = re.search(
        r"^\s*Total\s+([-+0-9.eE]+)\s+(\S+)\s+"
        r"([-+0-9.eE]+)\s+(\S+)\s+"
        r"([-+0-9.eE]+)\s+(\S+)\s+"
        r"([-+0-9.eE]+)\s+(\S+)\s*$",
        text,
        flags=re.MULTILINE,
    )
    if total_match:
        return {
            "internal_power": f"{total_match.group(1)} {total_match.group(2)}",
            "switching_power": f"{total_match.group(3)} {total_match.group(4)}",
            "leakage_power": f"{total_match.group(5)} {total_match.group(6)}",
            "total_power": f"{total_match.group(7)} {total_match.group(8)}",
        }

    escaped_top = re.escape(top)
    match = re.search(
        rf"^\s*{escaped_top}\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+",
        text,
        flags=re.MULTILINE,
    )
    if not match:
        return {
            "internal_power": "NA",
            "switching_power": "NA",
            "leakage_power": "NA",
            "total_power": "NA",
        }
    return {
        "internal_power": match.group(1),
        "switching_power": match.group(2),
        "leakage_power": match.group(3),
        "total_power": match.group(4),
    }


def main() -> int:
    work_root = Path(sys.argv[1] if len(sys.argv) > 1 else "work/dc/tsmc28/vpu_core")
    report_root = Path(sys.argv[2] if len(sys.argv) > 2 else "reports/dc/tsmc28/vpu_core")
    summary_csv = work_root / "dc_vpu_summary.csv"
    if not summary_csv.exists():
        print(f"Missing DC summary CSV: {summary_csv}", file=sys.stderr)
        return 2

    try:
        summary = read_summary_csv(summary_csv)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    top = summary.get("top", "sap_vpu_core")
    area = parse_area(report_root / "area.rpt")
    qor = parse_qor(report_root / "qor.rpt")
    power = parse_power(report_root / "power.rpt", top)

    print("# SAP-VPU TSMC28 DC Summary")
    print()
    print(f"Work: `{work_root}`")
    print(f"Reports: `{report_root}`")
    print()
    print("| Top | Corner | Clock ns | Worst slack ns | Total cell area | Comb area | Seq area | Cells |")
    print("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |")
    print(
        f"| {top} | {summary.get('corner', 'NA')} | "
        f"{summary.get('clock_period_ns', 'NA')} | {summary.get('worst_slack_ns', qor['critical_slack'])} | "
        f"{area['total_area']} | {area['comb_area']} | {area['seq_area']} | {area['cells']} |"
    )
    print()
    print("| Internal power | Switching power | Leakage power | Total power |")
    print("| ---: | ---: | ---: | ---: |")
    print(
        f"| {power['internal_power']} | {power['switching_power']} | "
        f"{power['leakage_power']} | {power['total_power']} |"
    )
    print()
    print(
        "Power is vectorless Design Compiler power unless a separate activity file "
        "is provided. Treat standalone `sap_vpu_core` results as VPU-core ASIC "
        "evidence, not full SoC evidence."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
