# FPGA Policy Power Matrix Design

## Goal

Generate a reproducible standalone SAP-VPU FPGA gate-level power matrix for the
TinyViT-oriented precision, sparsity, and gating policies already exercised by
the bare-metal kernel.

This evidence isolates VPU compute activity. It is not full CV32E40X SoC,
memory-system, board, or end-to-end TinyViT power.

## Existing Evidence Reused

- The routed 140 MHz `sap_vpu_core` checkpoint:
  `work/fpga/vpu_core_sliced_140/checkpoints/post_route.dcp`.
- The post-synthesis functional netlist:
  `work/fpga/vpu_core_sliced_140_funcsim/sap_vpu_core_funcsim.v`.
- The existing XSim gate testbench handshake and response checks.
- The existing Vivado SAIF power Tcl flow.
- The 512-VDOT policy definitions in `tinyvit_mlp_smoke.S`.

No RTL or CV32E40X source changes are required.

## Matrix

Each row runs 512 VDOT commands using a deterministic 32-VDOT operand stream
repeated 16 times. Policy setup completes before activity capture starts.

| Policy | Precision | Sparse bitmap | Active-lane limit | Expected skipped products | Expected output | Evidence role |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `dense_int8` | INT8 | `0x0f` | 4 | 0 | 12096 | dense baseline |
| `static_int4` | INT4 | `0xff` | 8 | 0 | 14592 | precision policy |
| `static_int2` | INT2 | `0xffff` | 16 | 0 | 5120 | precision policy |
| `adaptive_int4` | INT4 | `0x0f` | 4 | 2048 | 7296 | combined runtime policy |
| `adaptive_sparse75` | INT4 | `0x03` | 2 | 3072 | 3648 | structured sparsity point |
| `adaptive_unstructured` | INT4 | `0x55` | 8 | 2048 | 7296 | unstructured sparsity point |
| `no_sparse` | INT4 | `0xff` | 4 | 2048 | 7296 | runtime policy ablation |
| `no_lane` | INT4 | `0x0f` | 8 | 2048 | 7296 | runtime policy ablation |
| `no_precision` | INT8 | `0x0f` | 4 | 0 | 7296 | runtime policy ablation |

Every row must report `MAC_ACTIVE=512`, the expected accumulated output, and
the configured precision, bitmap, and lane state.

The three `no_*` rows disable one runtime control source by configuration. They
are policy-level switching-activity ablations, not synthesized hardware-removal
ablations. Any paper claim about removing gating logic requires separate RTL
variants and synthesis results.

`dense_x4` is excluded because it only extends the same steady-state VPU
activity. `dense_reuse` and `adaptive_reuse` are excluded because their
difference is CPU/RAM traffic, which is outside a standalone VPU checkpoint.

## Testbench

Extend `sap_vpu_core_gate_tb.sv` instead of creating nine copies.

- With no policy plusarg, retain the existing gate smoke behavior.
- With `policy=<name>`, configure the selected precision, sparse bitmap, and
  lane limit.
- Accept `vcd=<path>` so each policy writes a separate activity file.
- Wait for the Xilinx 100 ns global startup reset as the current smoke does.
- Start VCD recording only after policy setup and its final response have fully
  retired.
- Stop VCD recording only after the 512th VDOT response has fully retired.
- Check every VDOT response, the accumulated output, and the policy counters.
- Print `GATE_POLICY_PASS: <name>` only after all checks pass.
- Reject unknown policy names with `GATE_POLICY_FAIL`.

The operand stream follows the packed INT8, INT4, or INT2 values already used
by the bare-metal TinyViT tile. The standalone driver does not model RAM
traffic.

## Matrix Runner

Add one Windows PowerShell runner because Vivado and XSim are installed on
Windows while `vcd2saif` is installed in WSL.

The runner:

1. Resolves the WSL repository path and validates the DCP, functional netlist,
   testbench, Vivado tools, and `vcd2saif`.
2. Compiles and elaborates the gate snapshot once.
3. Runs the snapshot once per policy with separate VCD and log files.
4. Converts each VCD to SAIF through WSL.
5. Runs the existing Vivado SAIF power Tcl once per policy.
6. Fails on simulation failure, missing or empty artifacts, Vivado failure,
   `Power 33-332`, `Power 33-334`, or less than 99% matched design nets.
7. Validates SAIF `(TIMESCALE 1 ps)` and reads its capture duration.
8. Writes one CSV and one Markdown matrix containing total, dynamic, and static
   power, confidence, matched nets, normalized dynamic power versus
   `dense_int8`, capture duration, and dynamic energy per VDOT.

For the fixed 512-operation window:

```text
dynamic_pj_per_vdot = dynamic_w * duration_ps / 512
```

Dynamic power and dynamic energy per VDOT are the primary comparison metrics;
total power remains visible but is dominated by device static power.

All generated artifacts remain under ignored `work/fpga/`.

## Reproduction Interface

Expose one Make target that calls the PowerShell runner:

```sh
make fpga-vpu-policy-power-matrix
```

The runner keeps the current 140 MHz DCP, functional netlist, and Ubuntu-20.04
layout fixed. Only the Vivado installation and generated output directory need
overrides. The default remains Vivado 2023.2 at the documented Windows path.

## Verification

- Existing gate smoke still passes without plusargs.
- Each of the nine policy simulations prints its policy-specific pass marker.
- Each VCD, SAIF, Vivado log, and power report is non-empty.
- Each Vivado run matches at least 99% of routed design nets.
- No clock-consistency or excessive-reset-activity warning is present.
- Every SAIF uses a 1 ps timescale and all nine capture durations match.
- The summary contains exactly nine policies in the defined order.
- `make plan-check`, `make lint`, and `git diff --check` pass.

## Evidence Boundary

The resulting matrix may be described as a 140 MHz Artix-7 standalone VPU
gate-level, SAIF-annotated runtime policy power comparison with estimated
dynamic energy per VDOT. It must not be described as a hardware-removal
ablation, full-system TinyViT power, board-measured power, or final FPGA energy
efficiency.
