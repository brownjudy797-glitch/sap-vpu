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
- The current gate-level SAIF power run emits Vivado clock-consistency warnings
  and a reset-activity warning. Keep these warnings with any cited number.
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
| `work/fpga/vpu_core_sliced_140_funcsim_saif_power` | post-synth functional XSim gate SAIF | 4673/4691 (99.6%) | High | 0.081 | 0.010 | 0.070 | standalone VPU activity |

Do not use the RTL-SAIF smoke number as a final FPGA energy result; use it only
to show that the Vivado activity import path exists. The gate-level SAIF number
is the current best local FPGA activity-power checkpoint, but it still needs the
clock/reset warnings and standalone-core boundary reported with it.

## Next FPGA Steps

1. Re-run the 140 MHz checkpoint after any RTL datapath change.
2. Reduce or explain the gate-level SAIF clock/reset warnings before using the
   activity-power number in a paper table.
3. Add a board-level top and constraints only after the standalone VPU-core
   report remains reproducible.
