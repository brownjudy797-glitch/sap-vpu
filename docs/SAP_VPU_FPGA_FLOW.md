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

Run power from an existing routed checkpoint with VPU smoke SAIF activity:

```sh
make fpga-vpu-saif-power \
  FPGA_SAIF_DCP=work/fpga/vpu_core_sliced_140/checkpoints/post_route.dcp \
  FPGA_SAIF_POWER_DIR=work/fpga/vpu_core_sliced_140_saif_power
```

Export a post-synthesis functional simulation netlist from an existing
checkpoint:

```sh
make fpga-vpu-funcsim-netlist \
  FPGA_FUNCSIM_DCP=work/fpga/vpu_core_sliced_140/checkpoints/post_synth.dcp \
  FPGA_FUNCSIM_DIR=work/fpga/vpu_core_sliced_140_funcsim
```

Run the post-synthesis functional netlist under XSim, convert the resulting VCD
to SAIF, and re-run routed-checkpoint power:

```sh
make fpga-vpu-funcsim-saif-power \
  FPGA_SAIF_DCP=work/fpga/vpu_core_sliced_140/checkpoints/post_route.dcp \
  FPGA_FUNCSIM_DIR=work/fpga/vpu_core_sliced_140_funcsim \
  FPGA_FUNCSIM_SAIF_POWER_DIR=work/fpga/vpu_core_sliced_140_funcsim_saif_power
```

Run the 512-VDOT TinyViT-oriented runtime-policy matrix through the same
post-synthesis functional netlist and routed checkpoint:

```sh
make fpga-vpu-policy-power-matrix
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
- `work/fpga/vpu_core_sliced_140_saif_power/reports/post_route_saif_power.rpt`
- `work/fpga/vpu_core_sliced_140_saif_power/reports/post_route_saif_unmatched.rpt`
- `work/fpga/vpu_core_sliced_140_funcsim/sap_vpu_core_funcsim.v`
- `work/fpga/vpu_core_sliced_140_funcsim/fpga_vpu_funcsim_summary.csv`
- `work/fpga/vpu_core_sliced_140_funcsim/xsim_gate/sap_vpu_core_gate_tb.vcd`
- `work/fpga/vpu_core_sliced_140_funcsim/sap_vpu_core_gate.saif`
- `work/fpga/vpu_core_sliced_140_funcsim_saif_power/reports/post_route_saif_power.rpt`
- `work/fpga/vpu_core_policy_power_matrix/fpga_vpu_policy_power_matrix.csv`
- `work/fpga/vpu_core_policy_power_matrix/fpga_vpu_policy_power_matrix.md`
- `work/fpga/vpu_core/checkpoints/post_synth.dcp`
- `work/fpga/vpu_core/checkpoints/post_route.dcp`

## Current Evidence Boundary

- The WSL environment does not expose `vivado` directly. Local FPGA reports were
  generated with Windows Vivado 2023.2 (`D:\Xilinx_2023_02\Vivado\2023.2`) via
  a temporary UNC drive mapping into this repository.
- `report_power` uses Vivado default switching unless an activity file is added.
- `fpga-vpu-saif-power` uses the standalone VPU smoke SAIF, not TinyViT SoC
  activity.
- Current RTL SAIF to routed FPGA checkpoint annotation is low because Vivado
  sees post-synthesis/post-route net names. Treat it as a flow smoke until a
  post-synthesis or post-route simulation activity file is generated.
- `fpga-vpu-funcsim-saif-power` uses a dedicated gate-level smoke driver for
  the exported post-synthesis functional netlist. It is stronger than RTL-SAIF
  smoke because it annotates almost all routed nets, but it is still standalone
  VPU-core activity, not TinyViT or full-SoC activity.
- The gate-level smoke runs at the checkpoint's 140 MHz constraint and records
  activity only after reset release. The current SAIF power run has no Vivado
  clock-consistency or excessive-reset-activity warning.
- The policy matrix records each 512-VDOT window after policy setup and after
  the setup response has retired; capture ends after the final VDOT response
  retires. It reports runtime policy switching activity, not RTL variants with
  sparse, lane, or precision hardware removed.
- Matrix comparison should use dynamic power and SAIF-derived dynamic pJ/VDOT.
  Vivado reports power to 0.001 W here, so a table entry equal at that precision
  is not evidence that the underlying policies have identical power.
- Timing pass/fail is checked at the requested `FPGA_CLOCK_MHZ`; the Tcl exits
  nonzero on negative post-route worst slack.
- Generated reports remain under ignored `work/` and must not be committed.
- These are standalone VPU-core reports, not board-validated or full-SoC
  reports.

## Local Checkpoint

Current local Artix-7 `xc7a35tcsg324-1`, Vivado 2023.2, standalone
`sap_vpu_core` evidence for the current 0-DSP sliced datapath:

| Source | Clock MHz | Worst slack ns | LUT | FF | DSP | BRAM | Power W | Status |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `work/fpga/vpu_core_sliced_125` | 125 | 0.418 | 1814 | 729 | 0 | 0 | 0.089 | pass |
| `work/fpga/vpu_core_sliced_130` | 130 | 0.176 | 1814 | 733 | 0 | 0 | 0.090 | pass |
| `work/fpga/vpu_core_sliced_135` | 135 | 0.301 | 1816 | 732 | 0 | 0 | 0.090 | pass |
| `work/fpga/vpu_core_sliced_140` | 140 | 0.044 | 1820 | 744 | 0 | 0 | 0.091 | pass |
| `work/fpga/vpu_core_win_141mhz` | 141 | -0.036 | 1822 | 742 | 0 | 0 | 0.091 | fail |
| `work/fpga/vpu_core_sliced_145` | 145 | -0.008 | 1824 | 749 | 0 | 0 | 0.092 | fail |

Treat 140 MHz as the current reproducible standalone VPU-core FPGA timing
checkpoint. Do not claim 145 MHz or higher until a positive-slack run is
generated for the same RTL and mapping style.

Older local Windows runs at 150 MHz and 200 MHz used a DSP-mapped implementation
and are not part of the current no-DSP sliced VPU-core table.

Current local SAIF power-flow smoke on the 140 MHz checkpoint:

| Source | Activity file | Nets matched | Confidence | Total power W | Dynamic W | Static W | Status |
| --- | --- | ---: | --- | ---: | ---: | ---: | --- |
| `work/fpga/vpu_core_sliced_140_saif_power` | standalone VPU smoke SAIF | 159/4691 (3%) | Medium | 0.086 | 0.015 | 0.070 | flow smoke only |
| `work/fpga/vpu_core_sliced_140_funcsim_saif_power` | post-synth functional XSim gate SAIF | 4673/4691 (99.6%) | High | 0.087 | 0.017 | 0.070 | standalone VPU activity |

Do not use the RTL-SAIF smoke number as a final FPGA energy result; use it only
to show that the Vivado activity import path exists. The gate-level SAIF number
is the current best local FPGA activity-power checkpoint, but it still carries
the standalone-core boundary and is not representative TinyViT workload power.

Current TinyViT-oriented runtime-policy gate SAIF matrix on the same 140 MHz
checkpoint. Each row has a 18,295,784 ps capture window, `4673/4691` matched
nets, High confidence, and no `Power 33-332/334` warning.

| Policy | Total W | Dynamic W | Static W | Dynamic vs dense | Dynamic pJ/VDOT |
| --- | ---: | ---: | ---: | ---: | ---: |
| `dense_int8` | 0.086 | 0.016 | 0.070 | 1.000 | 571.743 |
| `static_int4` | 0.087 | 0.017 | 0.070 | 1.063 | 607.477 |
| `static_int2` | 0.086 | 0.016 | 0.070 | 1.000 | 571.743 |
| `adaptive_int4` | 0.086 | 0.016 | 0.070 | 1.000 | 571.743 |
| `adaptive_sparse75` | 0.086 | 0.016 | 0.070 | 1.000 | 571.743 |
| `adaptive_unstructured` | 0.086 | 0.016 | 0.070 | 1.000 | 571.743 |
| `no_sparse` | 0.086 | 0.016 | 0.070 | 1.000 | 571.743 |
| `no_lane` | 0.086 | 0.016 | 0.070 | 1.000 | 571.743 |
| `no_precision` | 0.085 | 0.015 | 0.070 | 0.938 | 536.009 |

This is a standalone 140 MHz VPU compute comparison. It is not a
hardware-removal ablation, full-SoC TinyViT power, board power, or energy per
inference.

## Next FPGA Steps

1. Re-run the 140 MHz checkpoint after any RTL datapath change.
2. Broaden the runtime activity from this deterministic tile to a larger MLP
   shape before treating dynamic-power differences below Vivado report
   resolution as evidence.
3. Add a board-level top and constraints only after the standalone VPU-core
   report remains reproducible.
