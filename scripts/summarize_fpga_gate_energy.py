#!/usr/bin/env python3
"""Generate matched-DCP cross-model gate-SAIF energy tables."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
import hashlib
from pathlib import Path
import sys


@dataclass(frozen=True)
class RunSpec:
    model: str
    layer: str
    workload: str
    directory: Path
    policies: tuple[tuple[str, str], ...]


def read_row(path: Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8-sig") as source:
        rows = list(csv.DictReader(source))
    if len(rows) != 1:
        raise ValueError(f"expected one CSV row: {path}")
    return rows[0]


def require_dcp(summary: dict[str, str], expected: Path, path: Path) -> None:
    actual = summary.get("dcp", "").replace("\\", "/")
    suffix = str(expected).replace("\\", "/")
    if not actual.endswith(suffix):
        raise ValueError(f"DCP mismatch in {path}: {actual}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_run(
    spec: RunSpec,
    post_synth_dcp: Path,
    post_route_dcp: Path,
) -> list[dict[str, str]]:
    rows = []
    for policy_dir, policy_label in spec.policies:
        directory = spec.directory / policy_dir
        summary = read_row(directory / "fpga_vpu_subsystem_power.csv")
        if summary.get("policy") != policy_dir:
            raise ValueError(f"policy mismatch: {directory}")
        if summary.get("confidence") != "High":
            raise ValueError(f"power confidence is not High: {directory}")
        matched = int(summary["nets_matched"])
        design_nets = int(summary["design_nets"])
        if matched * 100 < design_nets * 99:
            raise ValueError(f"SAIF annotation below 99%: {directory}")

        netlist_summary = read_row(directory / "netlist" / "fpga_vpu_funcsim_summary.csv")
        power_summary = read_row(directory / "power" / "fpga_vpu_saif_power_summary.csv")
        require_dcp(netlist_summary, post_synth_dcp, directory)
        require_dcp(power_summary, post_route_dcp, directory)

        xsim_log = (directory / "xsim.log").read_text(encoding="utf-8", errors="replace")
        if f"SUBSYSTEM_GATE_PASS: policy={policy_dir}" not in xsim_log:
            raise ValueError(f"missing gate PASS marker: {directory}")
        power_log = (directory / "vivado_power.log").read_text(encoding="utf-8", errors="replace")
        forbidden = ("ERROR:", "CRITICAL WARNING:", "Power 33-332", "Power 33-334")
        if any(marker in power_log for marker in forbidden):
            raise ValueError(f"power log contains an error or mapping warning: {directory}")

        iterations = int(summary["iterations"])
        rows.append(
            {
                "model": spec.model,
                "layer": spec.layer,
                "workload": spec.workload,
                "policy": policy_label,
                "iterations": str(iterations),
                "vdots_per_iteration": f"{int(summary['vdots']) / iterations:g}",
                "reads_per_iteration": f"{int(summary['ram_reads']) / iterations:g}",
                "writes_per_iteration": f"{int(summary['ram_writes']) / iterations:g}",
                "duration_us_per_iteration": f"{int(summary['duration_ps']) / iterations / 1_000_000:.3f}",
                "dynamic_w": summary["dynamic_w"],
                "dynamic_energy_uj_per_iteration": f"{float(summary['dynamic_pj_per_workload']) / 1_000_000:.6f}",
                "energy_reduction_pct": "0.00",
                "confidence": summary["confidence"],
                "nets_matched": str(matched),
                "design_nets": str(design_nets),
                "annotation_pct": f"{100.0 * matched / design_nets:.2f}",
            }
        )
    dense_energy = float(rows[0]["dynamic_energy_uj_per_iteration"])
    for row in rows[1:]:
        energy = float(row["dynamic_energy_uj_per_iteration"])
        row["energy_reduction_pct"] = f"{100.0 * (dense_energy - energy) / dense_energy:.2f}"
    return rows


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="ascii") as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_markdown(path: Path, rows: list[dict[str, str]], route_sha256: str) -> None:
    lines = [
        "# SAP-VPU Matched-DCP Gate-SAIF Energy Results",
        "",
        "| Model | Workload | Policy | VDOTs | Reads | Duration us | Dynamic W | Dynamic energy uJ | Energy reduction | Annotation |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        reduction = "baseline" if row["policy"] == "Dense" else f"{row['energy_reduction_pct']}%"
        lines.append(
            f"| {row['model']} | {row['workload']} | {row['policy']} | "
            f"{row['vdots_per_iteration']} | {row['reads_per_iteration']} | "
            f"{row['duration_us_per_iteration']} | {row['dynamic_w']} | "
            f"{row['dynamic_energy_uj_per_iteration']} | {reduction} | "
            f"{row['annotation_pct']}% {row['confidence']} |"
        )
    lines.extend(
        [
            "",
            f"Post-route DCP SHA-256: `{route_sha256}`.",
            "",
            "All rows use the same current post-synth/post-route subsystem checkpoints.",
            "Values are normalized per testbench iteration; compare policy reductions within each model.",
            "Absolute DeiT and TinyViT energy is not directly comparable because their output coverage differs.",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def self_test() -> None:
    assert f"{100.0 * (3.0 - 2.7) / 3.0:.2f}" == "10.00"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tinyvit-dir", type=Path)
    parser.add_argument("--deit-dir", type=Path)
    parser.add_argument("--post-synth-dcp", type=Path)
    parser.add_argument("--post-route-dcp", type=Path)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--csv", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            return 0
        required = (
            args.tinyvit_dir,
            args.deit_dir,
            args.post_synth_dcp,
            args.post_route_dcp,
            args.markdown,
            args.csv,
        )
        if not all(required):
            parser.error("all run, DCP, and output paths are required")
        specs = (
            RunSpec(
                "TinyViT-5M",
                "stages.1.blocks.0.mlp.fc2",
                "2 tokens x 8 outputs x K=512",
                args.tinyvit_dir,
                (
                    ("fc2_k512_stream_pairs_dense", "Dense"),
                    ("fc2_k512_stream_pairs_global_l1_12p5", "Global L1 12.5%"),
                    ("fc2_k512_stream_pairs_l1_budget_5pct", "L1 budget 5%"),
                ),
            ),
            RunSpec(
                "DeiT-Tiny",
                "blocks.5.mlp.fc1",
                "2 tokens x 768 outputs x K=192",
                args.deit_dir,
                (
                    ("deit_tiny_stream_dense", "Dense"),
                    ("deit_tiny_stream_global_l1_12p5", "Global L1 12.5%"),
                    ("deit_tiny_stream_l1_budget_5", "L1 budget 5%"),
                ),
            ),
        )
        rows = []
        for spec in specs:
            rows.extend(load_run(spec, args.post_synth_dcp, args.post_route_dcp))
        write_csv(args.csv, rows)
        write_markdown(args.markdown, rows, sha256(args.post_route_dcp))
    except (KeyError, OSError, ValueError) as error:
        print(f"FPGA gate-energy summary failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
