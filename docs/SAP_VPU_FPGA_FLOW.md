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

The default run executes 128 fixture-driven INT8 MLP2 inferences with shape
2x4x4x2. Each inference uses two M=2, N=2, K=4 FC1 tiles, a software-boundary
ReLU/repack step, and one M=2, N=2, K=4 FC2 tile. Override
`FPGA_SUBSYSTEM_ITERATIONS` only when a longer activity window is required.

Run the matched K=128 FC2 dense/sparse policy matrix against the same current
subsystem checkpoint:

```sh
make fpga-vpu-subsystem-policy-power-matrix
```

The matrix runs `fc2_dense`, `fc2_global_l1_6p25`, and
`fc2_l1_budget_2pct`. Each policy executes 32 identical 2x128x2 workloads;
only descriptor metadata and the resulting group skips differ.

Run the full-input-dimension K=512 FC2 matrix with the same netlist and routed
checkpoint:

```sh
make fpga-vpu-subsystem-k512-policy-power-matrix
```

This target uses eight 2x512x2 workloads per policy, keeping the activity window
at 512 tiles. Its operands are quantized real TinyViT GELU activations and the
complete 512-channel FC2 weight rows for two selected outputs.

Run the four representative full-layer output pairs with matched activity:

```sh
make fpga-vpu-subsystem-k512-pair-policy-power-matrix
```

Each policy executes two four-pair sets, again totaling 512 tiles. The output
pairs are `(0,1)`, `(42,43)`, `(84,85)`, and `(126,127)`; sparse input metadata
also suppresses a K4 token read when neither output uses that group.

Run the selected policies through the autonomous stream path:

```sh
make fpga-vpu-subsystem-k512-stream-policy-power-matrix
```

This uses the same four pairs and 512-tile capture size, but each pair is one
`VTSTREAM` command with final-only writeback. The compared policies are dense,
12.5% layer-global L1, and the 5% L1-budget policy that produces 13.40% full-
layer group sparsity in the host study.

Run the DeiT-Tiny FC1 stream policies first on four representative output pairs,
then on all 768 output channels for two image-derived tokens:

```sh
make fpga-vpu-subsystem-deit-policy-power-matrix
make fpga-vpu-subsystem-deit-full-output-power-matrix
```

The full-output target uses runtime-loaded hex memories instead of expanding the
36,864-word weight fixture as SystemVerilog constants. This avoids an XSim
2023.2 LLVM elaboration crash without changing the synthesized subsystem or
the measured routed checkpoint.

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
- `work/fpga/vpu_subsystem_140_policy_power/<policy>/fpga_vpu_subsystem_power.csv`
- `work/fpga/vpu_subsystem_140_k512_policy_power/<policy>/fpga_vpu_subsystem_power.csv`
- `work/fpga/vpu_subsystem_140_k512_pair_policy_power/<policy>/fpga_vpu_subsystem_power.csv`
- `work/fpga/vpu_subsystem_140_deit_policy_power/<policy>/fpga_vpu_subsystem_power.csv`
- `work/fpga/vpu_subsystem_140_current_deit_full_output_power/<policy>/fpga_vpu_subsystem_power.csv`
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
- ReLU and hidden-word repacking between FC1 and FC2 are performed at the
  testbench software boundary. Their CPU energy is not included in the
  subsystem power result.
- The K=128 policy matrix uses the same current post-synthesis netlist, routed
  checkpoint, 140 MHz clock, iteration count, output stores, and model fixture
  for all policies. It changes descriptor metadata only. Compare dynamic energy
  per workload; per-VDOT energy increases when fixed scheduler overhead is
  divided by fewer issued VDOTs.
- The K=512 matrix covers the complete FC2 input dimension but only two tokens
  and two output channels. It starts from captured model GELU values, so FC1,
  GELU generation, output bias, CPU, and external memory energy are excluded.
- The runner requires a passing RAM read/write/result check, at least 99% routed
  net annotation, High confidence, and no Vivado clock/reset activity warning.
- The full-output DeiT matrix uses the current July 27 shared-multiplier
  checkpoint at `work/fpga/vpu_subsystem_140_current`: 3037 LUTs, 1761 FFs,
  no DSP/BRAM, and +0.061 ns WNS. It annotates 7203/7223 nets with High
  confidence, so the area, timing, and workload activity evidence refer to the
  same implementation.
- Generated reports remain under ignored `work/` and must not be committed.
- These are standalone VPU-core or VPU-subsystem reports, not board-validated
  or full-SoC reports.

## Local Checkpoint

Current local Artix-7 `xc7a35tcsg324-1`, Vivado 2023.2, standalone
`sap_vpu_core` evidence for the 0-DSP datapath:

| Source | Clock MHz | Worst slack ns | LUT | FF | DSP | BRAM | Power W | Status |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `work/fpga/vpu_core_sliced_125` | 125 | 0.418 | 1814 | 729 | 0 | 0 | 0.089 | pass |
| `work/fpga/vpu_core_sliced_130` | 130 | 0.176 | 1814 | 733 | 0 | 0 | 0.090 | pass |
| `work/fpga/vpu_core_sliced_135` | 135 | 0.301 | 1816 | 732 | 0 | 0 | 0.090 | pass |
| `work/fpga/vpu_core_current_140` | 140 | 0.074 | 1862 | 788 | 0 | 0 | 0.083 | pass |
| `work/fpga/vpu_core_sharedmul_140_mapped` | 140 | 0.598 | 1310 | 725 | 0 | 0 | 0.082 | pass |
| `work/fpga/vpu_core_win_141mhz` | 141 | -0.036 | 1822 | 742 | 0 | 0 | 0.091 | fail |
| `work/fpga/vpu_core_sliced_145` | 145 | -0.008 | 1824 | 749 | 0 | 0 | 0.092 | fail |

Treat `vpu_core_sharedmul_140_mapped` as the current reproducible standalone
VPU-core FPGA timing checkpoint. Its precision datapath selects already
sign-extended INT8/INT4/INT2 operands before one signed 8x8 multiply per lane,
instead of describing three parallel multipliers and selecting their results.
Against `vpu_core_current_140`, this reduces LUTs by 552 (29.6%), FFs by 63
(8.0%), and improves WNS by 0.524 ns. Do not claim 145 MHz or higher until a
positive-slack run is generated for this same RTL and mapping style.

Older local Windows runs at 150 MHz and 200 MHz used a DSP-mapped implementation
and are not part of the current no-DSP sliced VPU-core table.

Current matched-RTL out-of-context comparison at 140 MHz, plus the earlier
100 MHz checkpoint:

| Top | Clock MHz | Worst slack ns | LUT | FF | DSP | BRAM | Status |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `sap_vpu_core` | 100 | 2.191 | 1817 | 729 | 0 | 0 | pass |
| `sap_vpu_subsystem` | 100 | 1.816 | 2741 | 1332 | 0 | 0 | pass |
| `sap_vpu_core` | 140 | 0.074 | 1862 | 788 | 0 | 0 | pass |
| `sap_vpu_subsystem` pre-stream | 140 | 0.025 | 2523 | 1303 | 0 | 0 | pass |
| `sap_vpu_subsystem` stream, pre-shared-multiplier | 140 | 0.021 | 3067 | 1656 | 0 | 0 | pass |
| `sap_vpu_core` shared-multiplier | 140 | 0.598 | 1310 | 725 | 0 | 0 | pass |
| `sap_vpu_subsystem` stream, shared-multiplier | 140 | 0.061 | 3037 | 1761 | 0 | 0 | pass |

The current stream subsystem adds 544 LUTs (+21.6%) and 353 FFs (+27.1%) over
the pre-stream subsystem while retaining 140 MHz timing. It includes the
64-block sequencer, packed-metadata cache, payload-read skip, accumulation, and
final writeback. Both builds use `Explore`; these are OOC IP results, not full-
SoC or board timing signoff.

At subsystem level the shared-multiplier change reduces LUTs by only 30
(1.0%), increases FFs by 105 (6.3%), and improves WNS by 0.040 ns relative to
the preceding stream checkpoint. Vivado rebalanced logic across the flattened
subsystem, so the standalone-core LUT reduction must not be presented as an
equal full-subsystem area reduction.

The earlier pre-group-skip MLP2 checkpoint remains a flow baseline:

| MLP2 iterations | Tiles | VDOTs | RAM reads | RAM writes | Duration ps | Nets matched | Confidence | Total W | Dynamic W | Dynamic pJ/MLP2 | Dynamic pJ/tile | Dynamic pJ/VDOT |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 128 | 384 | 1536 | 1536 | 1536 | 167,290,637 | 6452/6461 (99.86%) | High | 0.082 | 0.013 | 16,990.455 | 5,663.485 | 1,415.871 |

That checkpoint maps real-image activations and quantized `fc1/fc2` weight
slices from timm TinyViT-5M through three autonomous read-compute-write tiles
per fixture. The checkpoint/image SHA-256 values, preprocessing, model, layer,
and exact tensor slices are recorded in the fixture. Software-boundary
requantization/ReLU/repacking, external RAM, CPU, interconnect, and board power
are excluded. It is therefore not end-to-end TinyViT energy. The 0.001 W report
resolution also prevents using the unchanged 0.013 W rounded dynamic result as
a fixture-to-fixture power claim. It must not be mixed with the current sparse
policy matrix below because the RTL checkpoint differs.

Pre-stream K=128 FC2 gate-SAIF matrix on the July 24 group-skip RTL and matched
140 MHz routed checkpoint:

| Policy | Iterations | Tiles | VDOTs | RAM reads | RAM writes | Duration ps | Nets matched | Dynamic W | Dynamic pJ/workload | Energy reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `fc2_dense` | 32 | 512 | 4096 | 4096 | 2048 | 413,203,981 | 6142/6200 (99.06%) | 0.014 | 180,776.742 | baseline |
| `fc2_global_l1_6p25` | 32 | 512 | 3840 | 3968 | 2048 | 395,834,637 | 6142/6200 (99.06%) | 0.014 | 173,177.654 | 4.20% |
| `fc2_l1_budget_2pct` | 32 | 512 | 3904 | 4000 | 2048 | 400,176,973 | 6142/6200 (99.06%) | 0.014 | 175,077.426 | 3.15% |

All three gate simulations check exact aggregate outputs and expected
VDOT/read/write counts before power analysis. Global 6.25% group sparsity removes
6.25% of VDOTs and 3.125% of RAM reads; the error-budget policy removes 4.6875%
of VDOTs and 2.344% of RAM reads. Vivado rounds all three dynamic-power values
to 0.014 W, so the supported claim is lower matched-workload latency and dynamic
energy, not a separately resolved average-power reduction.

Pre-stream full-input-dimension K=512 FC2 gate-SAIF matrix on the same routed
checkpoint:

| Policy | Iterations | Tiles | VDOTs | RAM reads | RAM writes | Duration ps | Nets matched | Dynamic W | Dynamic pJ/workload | Energy reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `fc2_k512_dense` | 8 | 512 | 4096 | 4096 | 2048 | 413,203,981 | 6142/6200 (99.06%) | 0.014 | 723,106.967 | baseline |
| `fc2_k512_global_l1_6p25` | 8 | 512 | 3840 | 3968 | 2048 | 395,834,637 | 6142/6200 (99.06%) | 0.014 | 692,710.615 | 4.20% |
| `fc2_k512_l1_budget_2pct` | 8 | 512 | 3840 | 3968 | 2048 | 395,834,637 | 6142/6200 (99.06%) | 0.014 | 692,710.615 | 4.20% |

For this fixture, the 2% L1-budget rule selects the same 16 of 256 groups as
the global 6.25% rule, so their masks, outputs, transaction counts, and activity
are identical. The result proves full-K descriptor consumption and matched
energy reduction; it is not a multi-image accuracy result or full-layer output
coverage.

Pre-stream representative-output-pair K=512 matrix on the same checkpoint. Each
row executes 512 tiles and annotates 6142/6200 nets (99.06%) with High
confidence:

| Policy | Sets | VDOTs | RAM reads | RAM writes | Duration ps | Dynamic W | Dynamic pJ/four-pair set | Reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `fc2_k512_pairs_dense` | 2 | 4096 | 4096 | 2048 | 413,203,981 | 0.014 | 2,892,427.867 | baseline |
| `fc2_k512_pairs_global_l1_6p25` | 2 | 3736 | 3912 | 2048 | 388,749,773 | 0.014 | 2,721,248.411 | 5.92% |
| `fc2_k512_pairs_l1_budget_1pct` | 2 | 3844 | 3970 | 2048 | 396,106,033 | 0.014 | 2,772,742.231 | 4.14% |

The global and budget policies reduce representative-slice VDOTs by 8.79% and
6.15%, respectively. Vivado rounds all dynamic values to 0.014 W, so the energy
percentage follows the matched capture-duration reduction; no resolved average-
dynamic-power delta is claimed. These four output pairs are not a full-layer or
end-to-end inference power measurement.

Current autonomous-stream representative-pair matrix on the updated 140 MHz
checkpoint. Every row executes two four-pair sets (512 tiles), maps 7167/7230
nets (99.13%), and reports High confidence:

| Policy | VDOTs | RAM reads | RAM writes | Duration ps | Dynamic W | Dynamic pJ/set | Reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Dense stream | 4096 | 4128 | 32 | 377,665,389 | 0.015 | 2,832,490.418 | baseline |
| Global L1 12.5% | 3480 | 3940 | 32 | 337,698,757 | 0.015 | 2,532,740.678 | 10.58% |
| L1 budget 5% (13.40% sparse) | 3460 | 3930 | 32 | 336,341,777 | 0.015 | 2,522,563.328 | 10.94% |

The selected policies reduce VDOTs by 15.04%/15.53% and total reads, including
descriptor and metadata traffic, by 4.55%/4.80%. Dense and sparse stream rows
all write 16 final words per set, 98.44% fewer than the pre-stream partial-write
path. Vivado rounds every dynamic value to 0.015 W, so the supported result is
matched-workload latency and dynamic-energy reduction, not lower resolved
average power. The four pairs and single modified FC2 layer remain the claim
boundary.

DeiT-Tiny `blocks.5.mlp.fc1` full-output autonomous-stream matrix on the current
July 27 140 MHz shared-multiplier checkpoint (3037 LUTs, 1761 FFs, +0.061 ns
WNS, post-route DCP SHA-256
`e95e3a8c9feae3bfd90069c0f309ee39533ed1424f06586ec0b643d0168c5027`).
Each row covers two image-derived tokens and all 768 output channels, executes
9,216 K8 tiles, maps 7203/7223 nets (99.72%), and reports High confidence:

| Policy | VDOTs | RAM reads | RAM writes | Duration ps | Dynamic W | Dynamic energy uJ | Reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Dense stream | 73,728 | 75,264 | 1,536 | 6,828,891,149 | 0.016 | 109.262 | baseline |
| Global L1 12.5% | 64,512 | 72,764 | 1,536 | 6,237,847,797 | 0.016 | 99.806 | 8.66% |
| L1 budget 5% (12.01% sparse) | 64,874 | 72,989 | 1,536 | 6,262,723,383 | 0.016 | 100.204 | 8.29% |

Global and budget reduce VDOTs by 12.50%/12.01% and total reads by
3.32%/3.02%. On this image, global L1 consumes 0.40% less measured dynamic
energy than the budget policy; budget-policy value therefore comes from its
cross-sample error guardrail, not a single-sample energy advantage. Vivado
rounds all dynamic-power values to 0.016 W, so the supported claim is lower
matched-workload latency and energy, not resolved average-power reduction.
The result excludes the other 196 tokens, bias, GELU, later layers, external
RAM, CPU, interconnect, and board power.

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

## Davinci A7-200T Board Bring-up

The board target is the ALINX Davinci Pro Artix-7 board used by the legacy
`nutvpu` project:

| Signal | Pin | I/O standard |
| --- | --- | --- |
| 50 MHz clock | R4 | LVCMOS15 |
| Active-low reset | U7 | LVCMOS15 |
| LEDs 0..3 | V9, Y8, Y7, W7 | LVCMOS15 |
| UART RX/TX | E14, D17 | LVCMOS33 |

Build and run the board smoke with:

```bash
make fpga-davinci-hello
make fpga-davinci-board-smoke DAVINCI_UART_PORT=COM5
make fpga-davinci-vpu
make fpga-davinci-vpu-board-smoke DAVINCI_UART_PORT=COM5
make fpga-davinci-tiled-gemm-dma
make fpga-davinci-tiled-gemm-dma-board-smoke DAVINCI_UART_PORT=COM5
make fpga-davinci-tiled-gemm-dma DAVINCI_CLOCK_MHZ=70
make fpga-davinci-tiled-gemm-dma-board-smoke DAVINCI_CLOCK_MHZ=70 DAVINCI_UART_PORT=COM5
make fpga-davinci-deit-tile DAVINCI_CLOCK_MHZ=70
make fpga-davinci-deit-tile-board-smoke DAVINCI_CLOCK_MHZ=70 DAVINCI_UART_PORT=COM5
```

The first July 27 implementations target `xc7a200tfbg484-2` and use the
board's 50 MHz input directly. These results precede the registered CV-X-IF
command buffer added during the later clock sweep:

| ROM image | WNS ns | LUT | FF | RAMB36 | DSP48E1 | Board result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Hello | +0.168 | 7601 | 4555 | 1 | 3 | `SAP-VPU hello\n` |
| VPU instruction smoke | +0.507 | 7660 | 4558 | 1 | 3 | `P000000E4I02B7BFF5SF` |
| Tiled-GEMM DMA smoke | +0.965 | 7799 | 4558 | 1 | 3 | `P00000280IBFF51050SF` |

The different WNS and LUT values include ROM-content optimization and should
not be interpreted as workload-dependent hardware PPA. The DSPs belong to the
complete CV32E40X SoC; the standalone SAP-VPU OOC checkpoint remains a 0-DSP
implementation. Vivado default-activity power is 0.162-0.163 W total and
0.016-0.017 W dynamic with Medium confidence. These estimates are not
workload-annotated and are not paper power results.

The later current-RTL clock sweep registers one accepted CV-X-IF command in the
adapter before dispatching it to SAP-VPU. This adds one launch cycle while
preserving the one-in-flight contract and removes a 16.501 ns CPU-to-VPU
combinational path. The full RV32IMC SoC then reaches the following boundary:

| Core clock | WNS ns | LUT | FF | RAMB36 | DSP48E1 | Board result |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 70 MHz | +0.142 | 7936 | 4646 | 1 | 3 | Pass: `P00000280IBFF51050SF` |
| 80 MHz | -1.499 | - | - | - | - | Not programmed; timing failed |

The 70 MHz implementation required post-route `AggressiveExplore`; its initial
route WNS was -0.351 ns. At 80 MHz the remaining 13.931 ns path is inside the
CV32E40X load/store/multiply forwarding network and ends at the adapter operand
register. No false path or multicycle exception is applied. The 70 MHz Vivado
default-activity estimate is 0.287 W total and 0.140 W dynamic with Medium
confidence; it is not workload-annotated and is not a paper power result.

A model-derived bring-up image first checked one `M=2, N=2, K=8` tile from the
DeiT-Tiny `blocks.5.mlp.fc1` fixture and exposed the shared-RAM arbitration
deadlock described below. A dense-only image then covered the complete K=192
input dimension for two tokens and output channels 0/1. The current image uses
representative channels 510/511, where global-L1 and budget metadata differ,
and executes dense plus both sparse policies on the same operands:

| Policy | Exact INT32 outputs | Active VDOTs | Total DMA reads | Operand reads saved |
| --- | --- | ---: | ---: | ---: |
| Dense | `-1248, 265, -2325, 407` | 192 | 196 | 0 |
| Global L1 12.5% | `-1086, 239, -2144, 305` | 154 | 182 | 21 |
| L1 budget 5% | `-1086, 356, -2144, 484` | 158 | 184 | 19 |

The firmware checks every output and counter; the SoC RTL smoke also checks
562 aggregate DMA reads. Sparse metadata costs seven reads per operation, so
21/19 avoided operand reads produce net reductions of 14/12 total reads. The
three-policy image passes the real board at 70 MHz:

| Item | Result |
| --- | --- |
| Fixture source | `timm/deit_tiny_patch16_224.fb_in1k`, checkpoint SHA-256 `a1311bcf4f24e3c95adaa75535db67bc4412d95535b98f7c1dfd1164dda41c97` |
| Timing / utilization | +0.107 ns WNS; 8070 LUT, 4635 FF, 1 RAMB36, 3 DSP48E1 |
| JTAG / UART | `xc7a200t_0` startup HIGH; COM5 status `P000001FCI02B7BFF5SF` |
| Default-activity power | 0.273 W total / 0.134 W dynamic, Medium confidence; not a paper power result |
| Artifacts | `work/fpga/davinci_deit_fc1_k192_sparse_70/` |

This test exposed a real shared-RAM arbitration deadlock: a speculative CPU
load following `VTSTORE` could permanently block the older VPU result write.
The SoC now gives bounded VPU DMA requests priority over CPU data requests.
Both the full-K model-derived image and the original tiled-GEMM DMA regression
pass after the fix. This evidence proves the complete K=192 input dimension for
two FC1 outputs, not all 768 outputs or end-to-end DeiT inference.

The follow-up instrumented image emits cycle, active-VDOT, and DMA-saved
counters in fixed-width hexadecimal after each policy. RTL and real-board UART
match exactly:

| Policy | UART counters `(cycles, active, saved)` | Time at 70 MHz | Cycle reduction |
| --- | --- | ---: | ---: |
| Dense | `000009CB,000000C0,00000000` | 35.81 us | baseline |
| Global L1 12.5% | `0000086E,0000009A,00000015` | 30.83 us | 13.92% |
| L1 budget 5% | `00000894,0000009E,00000013` | 31.37 us | 12.41% |

The cycle interval starts immediately before `VTSTREAM` and ends after four
CPU output checks; it is a controlled kernel interval rather than end-to-end
inference latency. The image passes at +0.025 ns WNS with 8087 LUTs, 4635 FFs,
one RAMB36, three CPU DSPs, and 0 DRC errors. Its ignored artifacts are in
`work/fpga/davinci_deit_fc1_k192_sparse_uart_70/`.

The same generated `TILE_*` fixture contract also runs TinyViT FC2 output
channels 0/1 over the complete K=512 dimension. RTL and real-board UART again
match exactly:

| Policy | UART counters `(cycles, active, saved)` | Time at 70 MHz | Cycle reduction |
| --- | --- | ---: | ---: |
| Dense | `000019E4,00000200,00000000` | 94.69 us | baseline |
| Global L1 12.5% | `00001805,000001CA,0000001B` | 87.84 us | 7.23% |
| L1 budget 5% | `000017A4,000001C0,00000020` | 86.46 us | 8.69% |

The image passes at +0.054 ns WNS with 8512 LUTs, 4641 FFs, one RAMB36,
three CPU DSPs, and 0 DRC errors. Its 3,308-byte ROM image and generated RAM
layout fit the existing 4 KiB memories. Artifacts are in
`work/fpga/davinci_tinyvit_fc2_k512_sparse_uart_70/`. Resource differences
between the DeiT and TinyViT images include ROM-content optimization and are
not a model-dependent accelerator-area claim.

The board-smoke targets program `xc7a200t_0` over JTAG and open the CH340
`COM5` UART at 115200 baud. Hello requires `SAP-VPU hello\n`; basic non-UART
workloads discard pre-program capture and require a post-program diagnostic
packet ending in `SF`. The instrumented model-tile targets instead retain bytes
that arrive during JTAG completion and require the unique final budget-counter
fields, because discarding after programming would erase the one-shot report.
Each ignored build directory stores
`board_smoke_summary.csv` and `board_smoke_uart.txt`.
The runner stages only the bitstream and programming Tcl in Windows `%TEMP%`
so LabTools does not initialize from a WSL UNC working directory.

The VPU image validates `VSET`, `VMOV`, INT8/INT4 `VDOT`, sparse bitmap, lane
control, and readable/clearable counters. The tiled-GEMM DMA image additionally
validates CPU RAM initialization, autonomous input/weight reads, K5/K8/tail and
sparse tiles, result writes, and instruction/MAC/DMA skip counters.

The first implementation exposed two synthesis-specific issues that RTL
simulation did not reveal. The 4 KiB SoC RAM initially became 32768 FFs and a
large asynchronous read mux, exceeding the A200T LUT budget; CPU and VPU data
requests are mutually exclusive, so a shared synchronous port now infers one
RAMB36. Vivado also lost initialization on automatically duplicated multi-read
ROM ports. Explicit instruction/data ROM copies plus removal of the invalid
VPU-to-ROM error path make both required ROM ports deterministic.

Vivado reports 32 non-fatal DRC warnings, including `REQP-1839` on asynchronous
reset sources feeding inferred BRAM address logic. There are zero DRC errors,
the bitstream is generated, and the board smoke passes, but this warning should
be reviewed before treating the board implementation as signoff-quality.

## Cross-Model Current-DCP Gate-SAIF

`make fpga-vpu-subsystem-cross-model-energy-summary` validates and combines the
current TinyViT and DeiT power matrices. Every row uses the same current
post-synth/post-route subsystem checkpoints, reports 7203/7223 annotated nets
(99.72%) with High confidence, passes gate simulation, and has clean power logs.

| Model | Workload | Policy | VDOTs | Reads | Duration us | Dynamic energy uJ | Reduction |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| TinyViT-5M | 2 tokens x 8 outputs x K=512 | Dense | 2,048 | 2,064 | 188.833 | 3.021323 | baseline |
| TinyViT-5M | 2 tokens x 8 outputs x K=512 | Global L1 12.5% | 1,740 | 1,970 | 168.849 | 2.701590 | 10.58% |
| TinyViT-5M | 2 tokens x 8 outputs x K=512 | L1 budget 5% | 1,730 | 1,965 | 168.171 | 2.690734 | 10.94% |
| DeiT-Tiny | 2 tokens x 768 outputs x K=192 | Dense | 73,728 | 75,264 | 6,828.891 | 109.262258 | baseline |
| DeiT-Tiny | 2 tokens x 768 outputs x K=192 | Global L1 12.5% | 64,512 | 72,764 | 6,237.848 | 99.805565 | 8.66% |
| DeiT-Tiny | 2 tokens x 768 outputs x K=192 | L1 budget 5% | 64,874 | 72,989 | 6,262.723 | 100.203574 | 8.29% |

Vivado resolves 0.016 W dynamic power for every row, so the supported result is
matched-workload energy reduction, not resolved average-power reduction. Compare
policies within one model only because TinyViT and DeiT cover different output
counts. Generated Markdown and CSV are under ignored
`work/fpga/vpu_subsystem_140_current_cross_model_energy/`.

## Next FPGA Steps

1. Treat the current 70 MHz board and 140 MHz OOC gate-SAIF evidence as frozen;
   artifact hashes and commands are in the evidence manifest.
2. Do not expand the stream engine until labeled accuracy or a broader model
   suite shows that the selected policy generalizes beyond the current guardrail.
