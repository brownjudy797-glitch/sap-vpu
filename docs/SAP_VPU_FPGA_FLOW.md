# SAP-VPU FPGA Flow

## Scope

This flow captures the first reproducible FPGA evidence path for SAP-VPU. It
currently targets the standalone `sap_vpu_core`, not the full CV32E40X SoC.
Use it for VPU-core utilization, timing, and default-switching power evidence.

Do not cite these reports as board-validated full-system results. Full SoC and
board smoke evidence should be added after this standalone core flow is stable.

## Default Target

Default Make variables:

```sh
FPGA_PART=xc7a35tcsg324-1
FPGA_CLOCK_MHZ=100
FPGA_BUILD_DIR=work/fpga/vpu_core
```

The default part is an Artix-7 A35T-class target. Override `FPGA_PART` for the
actual board or device used in Vivado.

## Commands

Run Vivado batch synthesis, placement, routing, and reports:

```sh
make fpga-vpu-synth FPGA_PART=xc7a35tcsg324-1 FPGA_CLOCK_MHZ=100
```

Summarize generated reports:

```sh
make fpga-vpu-summary
```

The flow writes:

- `work/fpga/vpu_core/fpga_vpu_summary.csv`
- `work/fpga/vpu_core/reports/post_synth_utilization.rpt`
- `work/fpga/vpu_core/reports/post_synth_timing_summary.rpt`
- `work/fpga/vpu_core/reports/post_route_utilization.rpt`
- `work/fpga/vpu_core/reports/post_route_timing_summary.rpt`
- `work/fpga/vpu_core/reports/post_route_power.rpt`
- `work/fpga/vpu_core/checkpoints/post_synth.dcp`
- `work/fpga/vpu_core/checkpoints/post_route.dcp`

## Current Evidence Boundary

- The local WSL environment used for this repository checkpoint did not expose a
  `vivado` command, so the flow entry is committed before report generation.
- `report_power` uses Vivado default switching unless an activity file is added.
- Timing pass/fail is checked at the requested `FPGA_CLOCK_MHZ`; the Tcl exits
  nonzero on negative post-route worst slack.
- Generated reports remain under ignored `work/` and must not be committed.

## Next FPGA Steps

1. Run `make fpga-vpu-synth` on the Vivado machine for the actual Artix-7 board
   or target part.
2. Save the command, Vivado version, part, target clock, timing slack,
   utilization, and power summary in the dated work record.
3. Add a board-level top and constraints only after the standalone VPU-core
   report is reproducible.
