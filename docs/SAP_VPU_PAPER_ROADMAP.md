# SAP-VPU IEEE Paper Roadmap

## Paper Argument and Boundaries

SAP-VPU targets edge TinyViT inference with a CV32E40X-hosted, CV-X-IF attached
sparse-aware adaptive-precision vector coprocessor. The paper should argue that
this path gives a portable RISC-V custom coprocessor integration route and a
measurable low-power vector datapath for TinyViT MLP/GEMM-heavy kernels.

The paper must keep these boundaries explicit:

- SAP-VPU is not a full RVV implementation.
- SAP-VPU does not modify CV32E40X source code.
- Legacy `nutvpu` numbers are baseline anchors only, not final paper claims.
- FPGA frequency and ASIC PPA claims require reproduction in the SAP-VPU flow.
- Recent daily-report papers are lightweight design references only; their exact
  publication venues are not treated as verified evidence.

## Current Engineering Status

| Area | Status | Evidence |
| --- | --- | --- |
| Legacy baseline | Available as a tracked summary, with old sources kept outside this repo. | `make legacy-summary`, `docs/SAP_VPU_BASELINE_LEDGER.md` |
| Minimal CORE-V SoC | CV32E40X wrapper with ROM, RAM, UART, exit MMIO, and OBI timing smoke. | `make hello-smoke` |
| CV-X-IF attachment | `corev_min_soc` enables `X_EXT` and connects SAP-VPU through the flattened adapter. | `make lint-corev-soc`, `make hello-smoke` |
| VPU instruction path | Bare-metal custom-0 smoke covers base, precision, sparse, lane, and counter ops. | `make vpu-smoke` |
| Tiled GEMM path | A bounded M<=2, N<=2, K<=8 scheduler accumulates up to two packed VDOT blocks per output. `VTDMA` fetches up to four packed words from SoC RAM and `VTSTORE` writes row-major results back over a single-outstanding OBI path. K=3/4/5/8 cases pass. | `make tiled-gemm-rtl-check`, `make tiled-gemm-soc-smoke`, `make tiled-gemm-dma-soc-smoke` |
| Paper workload | TinyViT policy smokes cover INT8/INT4/INT2, bitmap and software-scheduled sparsity, ablations, counters, reuse, and RAM traffic. The default 2x4x4x2 MLP2 fixture now uses quantized `fc1/fc2` slices from the timm TinyViT-5M checkpoint with exact model/layer/hash provenance. Its inputs remain deterministic basis probes and bias/GELU are omitted, so it is checkpoint-weight kernel evidence rather than full-model accuracy evidence. | `make tinyvit-paper-table`, `make tinyvit-fixture-check`, `docs/SAP_VPU_TINYVIT_SMOKE_RECORD.md` |
| FPGA evidence | Standalone core and complete `sap_vpu_subsystem` both pass same-mode Artix-7 OOC implementation at 100/140 MHz. At 140 MHz the subsystem uses 2752 LUTs and 1332 FFs with +0.091 ns WNS. The checkpoint-weight run maps 128 fixed 2x4x4x2 MLP2 slices through 384 autonomous tiles and 1536 VDOTs; its post-synth SAIF annotates 6452/6461 routed nets and reports 0.013 W dynamic power and 16.990 nJ/MLP2. Probe inputs, software ReLU/repacking, external RAM, CPU, and board power remain outside a full inference claim. | `make fpga-vpu-synth`, `make fpga-vpu-subsystem-saif-power`, `docs/SAP_VPU_FPGA_FLOW.md` |
| ASIC evidence | The accepted TSMC28 `tt0p9v85c`, 10 ns gate/SAIF checkpoint remains standalone-core evidence. The complete subsystem passes DC analyze/elaborate/link/checks, but DC L-2016.03-SP1 crashes during mapping under three bounded settings, so no complete-subsystem ASIC PPA is claimed. | `make dc-vpu-precheck`, `docs/SAP_VPU_ASIC_FLOW.md` |

The complete `sap_vpu_subsystem`, including the tiled scheduler, bounded
scratchpads, and OBI read/write data mover, now has FPGA OOC area/timing
evidence. ASIC front-end checks also pass, but complete mapping is blocked by
the local DC/library combination. The current four-word scratchpads prove
autonomous operand fetch, two-block K accumulation, and result writeback, but
larger SRAM banks and double buffering remain later work.
Data-accurate dimensions, bias/GELU, float-error accounting, and a defensible
power-reduction claim also remain subsequent paper-evidence steps.

## Contribution Spine

1. **Portable attachment**: CV32E40X hosts SAP-VPU through CV-X-IF while the
   scalar core remains unmodified.
2. **Adaptive sparse datapath**: SAP-VPU supports packed INT8/INT4/INT2 dot
   products, bitmap sparse skip, lane control, and counter-visible execution.
3. **TinyViT evidence chain**: evaluation focuses on MLP/GEMM-heavy TinyViT
   kernels, adaptive precision policy, sparse/lane gating ablations, and PPA.

## External Reference Use

The 2026-07-01 daily report is useful for ideas, but its papers should not be
fully absorbed into SAP-VPU's claim structure unless their venue, scope, and
results are verified later. Use them only as lightweight design inspiration:

| Reference idea | SAP-VPU use | Limit |
| --- | --- | --- |
| FlexViT-style FPGA ViT acceleration | Borrow the emphasis on GEMM tiling, data reuse, and off-chip traffic awareness. | Do not copy its architecture or claim direct comparability without reading and reproducing details. |
| RaBitQCache-style proxy computation | Consider low-cost importance signals before choosing precision or skip policy. | It targets LLM KV cache, not TinyViT hardware. |
| W4A4/outlier-channel quantization | Consider policy experiments where common channels use low bit width and outliers stay INT8. | Do not add a dual-branch datapath unless TinyViT data proves it is needed. |
| CGRA scratchpad/memory trade-offs | Report memory traffic and operand reuse, not only MAC speedup. | CGRA results are not a direct baseline for a CV-X-IF coprocessor. |
| DinoLink/token pruning | Treat token or channel pruning as one possible structured sparsity source. | It is a workload-policy reference, not core hardware evidence. |

These references should appear, if used, in related work or discussion as
motivation. They should not replace direct comparisons against RISC-V vector,
custom instruction, TinyML, and edge-AI accelerator work.

## Next Engineering Sequence

1. Move complete-subsystem ASIC mapping to a newer compatible DC installation
   or regenerate and validate the TSMC28 `.db`; repeat matched core/subsystem
   10 ns runs before publishing an ASIC area delta.
2. Capture real layer inputs from a reproducible TinyViT image run and add bias,
   GELU, and floating-point error accounting to the checkpoint-weight slice.
3. Extend the validated mapping beyond the fixed 2x4x4x2 dimensions.
4. Replace register scratchpads with explicit SRAM-macro assumptions only after
   capacity and traffic experiments justify the change.

## TinyViT Kernel Plan

The first paper-facing kernel should model a TinyViT MLP block rather than the
whole network. It should be deterministic, small, and repeatable:

- Input shape: a fixed token-vector tile that fits the minimal SoC memory model.
- Compute shape: packed dot products representing MLP/GEMM inner loops.
- Precision modes: INT8, INT4, INT2 where packing and expected values are exact.
- Sparsity modes: dense, structured bitmap, one structured whole-vector
  software schedule, and at least one unstructured bitmap.
- Output check: compare against a golden scalar result and fail through MMIO exit
  code on mismatch.

Keep the first scheduling variant hand-written and auditable. It must account
for software-scheduled skips separately from VPU hardware bitmap skips.

## Adaptive Policy Plan

The initial adaptive policy should be simple and explainable:

- Use a deterministic importance score from the input or weight tile.
- Keep high-importance lanes/channels at INT8.
- Use INT4 or INT2 for lower-importance lanes/channels.
- Use bitmap skip for known-zero or pruned lanes.
- Record the chosen precision, bitmap, lane count, and counter deltas.

This policy is a workload experiment first. Add new hardware only if the software
policy proves a measurable benefit and the existing VPU controls cannot express
it.

## Experiment Matrix

| Experiment | Baseline | Variant | Required output |
| --- | --- | --- | --- |
| Functional kernel | Scalar golden result | SAP-VPU custom instructions | pass/fail, output value |
| Precision | INT8 dense | INT4, INT2 | cycles, error if any, speedup |
| Sparsity | Dense bitmap | Structured/unstructured bitmap and structured whole-vector scheduling | hardware/software skip count, cycles, VDOT count |
| Lane gating | All lanes | Reduced active lanes | cycles, active lane state |
| Full policy | Static INT8 dense | Adaptive precision + sparse + lane | speedup, skip ratio, correctness |
| Ablation | Full policy | no sparse, no lane, no precision | per-feature contribution |
| Hardware | RTL functional flow | FPGA/ASIC reports | fmax, area, timing, power |

## Minimum Submission Evidence

- Functional regression passes: adapter/core tests, `hello-smoke`, `vpu-smoke`,
  and TinyViT kernel smoke.
- Main TinyViT kernel table exists with reproducible commands.
- At least three ablations are reported.
- ASIC PPA table exists with clear memory assumptions.
- FPGA results are limited to frequencies actually passing timing or smoke tests.
- Related work distinguishes SAP-VPU from RVV, CGRA, custom AI instructions, and
  classic DNN accelerators.

## Manuscript Skeleton

1. **Introduction**
   - Edge ViT/TinyViT inference pressure.
   - Why full RVV or a large accelerator can be costly for small edge systems.
   - Why CV-X-IF custom coprocessor attachment is a portable middle path.
   - Summary of SAP-VPU and measured kernel/PPA evidence.

2. **Architecture**
   - CV32E40X + CV-X-IF attachment.
   - SAP-VPU ISA subset and command/result contract.
   - Packed INT8/INT4/INT2 datapath.
   - Sparse bitmap skip, lane control, and counter-visible execution.

3. **Software Mapping**
   - TinyViT MLP/GEMM kernel mapping.
   - Precision and sparse policy.
   - Counter collection and golden checking.

4. **Evaluation**
   - Functional validation.
   - TinyViT kernel performance.
   - Precision/sparse/lane ablations.
   - FPGA timing and ASIC PPA/power when available.

5. **Discussion**
   - Where SAP-VPU is useful.
   - Where full RVV, CGRA, or larger accelerators remain stronger.
   - Which claims depend on future full-model or silicon evidence.

## Submission Checklist

- [ ] All paper-facing numbers are reproduced in SAP-VPU or clearly marked as
      legacy baseline.
- [ ] No unverified daily-report venue is cited as a confirmed publication venue.
- [ ] No claim says SAP-VPU replaces full RVV.
- [ ] No claim says CV32E40X internals were modified.
- [ ] No FPGA frequency is claimed before timing or board evidence.
- [ ] No ASIC power number is reported without activity or power-flow assumptions.
- [ ] TinyViT kernel scripts and expected outputs are reproducible from a clean
      checkout after fetching `third_party/cv32e40x`.
