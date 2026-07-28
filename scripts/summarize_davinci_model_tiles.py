#!/usr/bin/env python3
"""Generate cross-model Davinci board tables from verified run artifacts."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path
import re
import sys

from summarize_vivado_reports import parse_utilization, read_summary_csv


UART_RE = re.compile(
    r"^([DGB]),([0-9A-Fa-f]{8}),([0-9A-Fa-f]{8}),([0-9A-Fa-f]{8})$",
    re.MULTILINE,
)
POLICIES = {"D": "Dense", "G": "Global L1 12.5%", "B": "L1 budget 5%"}


@dataclass(frozen=True)
class RunSpec:
    model: str
    layer: str
    k: int
    directory: Path


def parse_uart(text: str) -> dict[str, tuple[int, int, int]]:
    rows: dict[str, tuple[int, int, int]] = {}
    for tag, cycles, active, saved in UART_RE.findall(text):
        if tag in rows:
            raise ValueError(f"duplicate UART policy row: {tag}")
        rows[tag] = tuple(int(value, 16) for value in (cycles, active, saved))
    if set(rows) != set(POLICIES):
        raise ValueError(f"UART policy rows must be D/G/B, got {sorted(rows)}")
    dense_cycles = rows["D"][0]
    if dense_cycles <= 0 or rows["G"][0] >= dense_cycles or rows["B"][0] >= dense_cycles:
        raise ValueError("sparse UART cycles must be positive and lower than dense")
    return rows


def load_run(spec: RunSpec) -> tuple[list[dict[str, str]], dict[str, str]]:
    implementation = read_summary_csv(spec.directory / "fpga_davinci_summary.csv")
    board = read_summary_csv(spec.directory / "board_smoke_summary.csv")
    if board.get("status") != "pass":
        raise ValueError(f"board run did not pass: {spec.directory}")
    if board.get("baud") != implementation.get("uart_baud"):
        raise ValueError(f"UART baud mismatch: {spec.directory}")
    clock_mhz = float(implementation["core_clock_mhz"])
    uart = parse_uart((spec.directory / "board_smoke_uart.txt").read_text(encoding="ascii"))
    util = parse_utilization(spec.directory / "reports" / "post_route_utilization.rpt")
    dense_cycles = uart["D"][0]
    rows = []
    for tag in ("D", "G", "B"):
        cycles, active, saved = uart[tag]
        rows.append(
            {
                "model": spec.model,
                "layer": spec.layer,
                "k": str(spec.k),
                "policy": POLICIES[tag],
                "cycles": str(cycles),
                "latency_us": f"{cycles / clock_mhz:.2f}",
                "active_vdots": str(active),
                "operand_reads_saved": str(saved),
                "cycle_reduction_pct": "0.00" if tag == "D" else f"{100.0 * (dense_cycles - cycles) / dense_cycles:.2f}",
                "clock_mhz": f"{clock_mhz:g}",
                "wns_ns": implementation["worst_slack_ns"],
                "lut": util["lut"],
                "ff": util["ff"],
                "bram": util["bram"],
                "dsp": util["dsp"],
                "board_status": board["status"],
            }
        )
    evidence = {
        "model": spec.model,
        "image": implementation["image"],
        "part": implementation["part"],
        "clock_mhz": f"{clock_mhz:g}",
        "wns_ns": implementation["worst_slack_ns"],
        "lut": util["lut"],
        "ff": util["ff"],
        "bram": util["bram"],
        "dsp": util["dsp"],
        "board_status": board["status"],
    }
    return rows, evidence


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="ascii") as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_markdown(
    path: Path,
    rows: list[dict[str, str]],
    evidence: list[dict[str, str]],
) -> None:
    lines = [
        "# SAP-VPU Cross-Model FPGA Board Results",
        "",
        "## Kernel Metrics",
        "",
        "| Model | Layer | K | Policy | Cycles | Latency us | Active VDOTs | Operand reads saved | Cycle reduction |",
        "| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        reduction = "baseline" if row["policy"] == "Dense" else f"{row['cycle_reduction_pct']}%"
        lines.append(
            f"| {row['model']} | `{row['layer']}` | {row['k']} | {row['policy']} | "
            f"{row['cycles']} | {row['latency_us']} | {row['active_vdots']} | "
            f"{row['operand_reads_saved']} | {reduction} |"
        )
    lines.extend(
        [
            "",
            "## Implementation Evidence",
            "",
            "| Model | Image | Part | Clock MHz | WNS ns | LUT | FF | BRAM | DSP | Board |",
            "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
        ]
    )
    for row in evidence:
        lines.append(
            f"| {row['model']} | `{row['image']}` | `{row['part']}` | {row['clock_mhz']} | "
            f"{row['wns_ns']} | {row['lut']} | {row['ff']} | {row['bram']} | "
            f"{row['dsp']} | {row['board_status']} |"
        )
    lines.extend(
        [
            "",
            "Cycles cover the interval from counter clear before `VTSTREAM` through four CPU output checks.",
            "Resource differences include ROM-content optimization and are not model-dependent accelerator-area claims.",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def self_test() -> None:
    rows = parse_uart(
        "status\nD,00000064,00000020,00000000\n"
        "G,0000005A,0000001C,00000002\nB,00000050,00000018,00000004\n"
    )
    assert rows == {"D": (100, 32, 0), "G": (90, 28, 2), "B": (80, 24, 4)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deit-dir", type=Path)
    parser.add_argument("--tinyvit-dir", type=Path)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--csv", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            return 0
        if not all((args.deit_dir, args.tinyvit_dir, args.markdown, args.csv)):
            parser.error("both run directories and both outputs are required")
        specs = (
            RunSpec("DeiT-Tiny", "blocks.5.mlp.fc1", 192, args.deit_dir),
            RunSpec("TinyViT-5M", "stages.1.blocks.0.mlp.fc2", 512, args.tinyvit_dir),
        )
        rows: list[dict[str, str]] = []
        evidence = []
        for spec in specs:
            run_rows, run_evidence = load_run(spec)
            rows.extend(run_rows)
            evidence.append(run_evidence)
        write_csv(args.csv, rows)
        write_markdown(args.markdown, rows, evidence)
    except (KeyError, OSError, ValueError) as error:
        print(f"Davinci model-tile summary failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
