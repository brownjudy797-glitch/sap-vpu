# SAP-VPU FPGA Flow

## Scope

This flow captures the reproducible FPGA evidence path for SAP-VPU. It supports
the standalone `sap_vpu_core` and the complete `sap_vpu_subsystem`, but not the
full CV32E40X SoC. Use it for VPU utilization, timing, and switching-power
evidence within those boundaries.

Do not cite these reports as board-validated full-system results. Full SoC and
board smoke evidence should be added after this standalone core flow is stable.

## Default Target

Default Make variables:

```sh
FPGA_PART=xc7a35tcsg324-1
FPGA_CLOCK_MHZ=100
FPGA_TOP=sap_vpu_core
FPGA_OUT_OF_CONTEXT=0
FPGA_BUILD_DIR=work/fpga/vpu_core
```

The default part is an Artix-7 A35T-class target. Override `FPGA_PART` for the
actual board or device used in Vivado.

## Commands

Run Vivado batch synthesis, placement, routing, and reports:

```sh
make fpga-vpu-synth FPGA_PART=xc7a35tcsg324-1 FPGA_CLOCK_MHZ=100
```

Run the complete VPU subsystem as internal SoC IP. Out-of-context mode is
required because the raw subsystem interface has 223 top-level I/O bits, more
than the selected package's 210 user I/Os:

```sh
make fpga-vpu-synth \
  FPGA_TOP=sap_vpu_subsystem \
  FPGA_OUT_OF_CONTEXT=1 \
  FPGA_CLOCK_MHZ=140 \
  FPGA_BUILD_DIR=work/fpga/vpu_subsystem_140
```

Run the complete subsystem post-synthesis read-compute-write smoke, convert its
VCD to SAIF, and annotate the matched 140 MHz routed checkpoint:

```sh
make fpga-vpu-subsystem-saif-power
```

The default run executes 128 identical INT8 M=2, N=2, K=4 tiles. Override
`FPGA_SUBSYSTEM_ITERATIONS` only when a longer activity window is required.

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

The policy runner defaults to the 140 MHz checkpoint, but can be pointed at a
different matched checkpoint and functional netlist. The XSim clock is derived
from `FPGA_POLICY_CLOCK_MHZ`, so it must match the routed DCP constraint:

```sh
make fpga-vpu-policy-power-matrix \
  FPGA_POLICY_DCP=work/fpga/example/checkpoints/post_route.dcp \
  FPGA_POLICY_NETLIST=work/fpga/example_funcsim/sap_vpu_core_funcsim.v \
  FPGA_POLICY_CLOCK_MHZ=135 \
  FPGA_POLICY_POWER_DIR=work/fpga/example_policy_power
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
- `work/fpga/vpu_subsystem_140_saif_power/sap_vpu_subsystem_gate.vcd`
- `work/fpga/vpu_subsystem_140_saif_power/sap_vpu_subsystem_gate.saif`
- `work/fpga/vpu_subsystem_140_saif_power/fpga_vpu_subsystem_power.csv`
- `work/fpga/vpu_subsystem_140_saif_power/power/reports/post_route_saif_power.rpt`
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
- The gate-level smoke uses `FPGA_POLICY_CLOCK_MHZ` and records activity only
  after reset release. Its frequency must match the routed checkpoint; the
  runner rejects Vivado `Power 33-332/334` clock-consistency warnings.
- The policy matrix records each 512-VDOT window after policy setup and after
  the setup response has retired; capture ends after the final VDOT response
  retires. It reports runtime policy switching activity, not RTL variants with
  sparse, lane, or precision hardware removed.
- Matrix comparison should use dynamic power and SAIF-derived dynamic pJ/VDOT.
  Vivado reports power to 0.001 W here, so a table entry equal at that precision
  is not evidence that the underlying policies have identical power.
- Timing pass/fail is checked at the requested `FPGA_CLOCK_MHZ`; the Tcl exits
  nonzero on negative post-route worst slack.
- Complete-subsystem results use Vivado out-of-context implementation because
  `sap_vpu_subsystem` is internal SoC IP, not a package pin-level top. Vivado
  warns that `HD.CLK_SRC` and `HD.PARTPIN_LOCS` are absent in this mode, so the
  numbers support internal comparative PPA only, not board timing signoff.
- The subsystem gate-SAIF flow covers the subsystem command path, four-word
  register scratchpads, tiled GEMM scheduler, core, and OBI read/write pins. Its
  testbench memory model is outside the synthesized checkpoint, so the result
  excludes RAM-array, CPU, interconnect, and board power.
- The runner requires a passing RAM read/write/result check, at least 99% routed
  net annotation, High confidence, and no Vivado clock/reset activity warning.
- Generated reports remain under ignored `work/` and must not be committed.
- These are standalone VPU-core or VPU-subsystem reports, not board-validated
  or full-SoC reports.

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

Current same-mode out-of-context comparison for the complete subsystem:

| Top | Clock MHz | Worst slack ns | LUT | FF | DSP | BRAM | Status |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `sap_vpu_core` | 100 | 2.191 | 1817 | 729 | 0 | 0 | pass |
| `sap_vpu_subsystem` | 100 | 1.816 | 2741 | 1332 | 0 | 0 | pass |
| `sap_vpu_core` | 140 | 0.090 | 1817 | 742 | 0 | 0 | pass |
| `sap_vpu_subsystem` | 140 | 0.091 | 2752 | 1332 | 0 | 0 | pass |

At 140 MHz, adding the tiled scheduler, four-word register scratchpads, and OBI
data mover costs 935 LUTs (+51.5%) and 590 FFs (+79.5%) relative to the core in
the same OOC flow. The near-equal WNS is a comparative IP result; it is not a
claim that full-SoC or board timing is unchanged. Vectorless power rounds to
0.082 W for both 140 MHz runs and is therefore not used as evidence of equal
power.

Current complete-subsystem gate-SAIF checkpoint on the same 140 MHz routed
design:

| Tiles | Shape | VDOTs | RAM reads | RAM writes | Duration ps | Nets matched | Confidence | Total W | Dynamic W | Static W | Dynamic pJ/tile |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: |
| 128 | INT8 M=2, N=2, K=4 | 512 | 512 | 512 | 55,761,165 | 6452/6461 (99.86%) | High | 0.080 | 0.011 | 0.068 | 4,791.975 |

This is a deterministic repeated-tile activity checkpoint. It proves that the
autonomous read-compute-write datapath can drive a high-coverage FPGA power
run; it is not end-to-end TinyViT energy or evidence that external memory is
free. The 0.001 W report resolution also prevents using the difference from the
0.082 W vectorless estimate as a power-reduction claim.

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

## Rejected Operand-Isolation Trial

An experimental RTL variant that masked inputs of unselected precision
multipliers was evaluated and then removed. It passed at 135 MHz with +0.019 ns
WNS and used 2062 LUTs / 746 FFs, but failed at 140 MHz with -0.092 ns WNS.
Its complete 135 MHz gate-SAIF matrix had 4855/4862 matched nets, High
confidence, and no consistent policy-level dynamic-power reduction at Vivado's
0.001 W reporting resolution. It is not part of the current design or a
paper-facing result.

## Next FPGA Steps

1. Re-run both 140 MHz OOC checkpoints after any RTL datapath change.
2. Broaden the runtime activity from this deterministic tile to a larger MLP
   shape before treating dynamic-power differences below Vivado report
   resolution as evidence.
3. Add a structured sparse scheduling path that eliminates whole inactive VDOT
   operations before claiming sparse speedup from the TinyViT kernel.
4. Add a board-level top and constraints only after the subsystem report remains
   reproducible.
