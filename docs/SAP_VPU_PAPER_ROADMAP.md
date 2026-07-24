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
| VPU instruction path | Bare-metal custom-0 smoke covers base, precision, sparse, lane, and counter ops. The core now returns an all-zero effective-bitmap VDOT without entering its multiply/reduction pipeline and exposes a group-skip counter. | `make sim-core`, `make vpu-smoke` |
| Tiled GEMM path | A bounded M<=2, N<=2, K<=8 scheduler remains the compute tile. `VTDMA` and `VTSTORE` retain explicit tile control. `VTSTREAM` autonomously executes up to 64 K8 tiles, caches packed per-block metadata, skips invalid payload reads/VDOTs, accumulates four INT32 outputs, and writes only the final tile. Across four representative K=512 output pairs, dense/global-12.5%/budget-13.40% streams pass at `2048/1740/1730` VDOTs, `2064/1970/1965` reads, and 16 writes. | `make tiled-gemm-rtl-check`, `make tiled-gemm-dma-soc-smoke`, `make sim-subsystem-k512-stream` |
| Paper workload | TinyViT policy smokes cover INT8/INT4/INT2, bitmap and software-scheduled sparsity, ablations, counters, reuse, and RAM traffic. The host policy study covers all 512 inputs and 128 outputs for 6,272 tokens from eight images. It now injects the target FC2's emulated INT8/sparse output into the remaining float network: 12.5% global and 13.40% L1-budget policies retain 8/8 top-1 agreement, while 25% policies do not. Four evenly spaced output pairs carry full-layer masks through exact K=512 subsystem RTL and gate-SAIF checks. Runtime window swapping, labeled ImageNet accuracy, all-layer sparsity, and end-to-end inference power remain outside the claim; GELU is not claimed as VPU hardware. | `make tinyvit-fc1-k128-smoke`, `make sim-subsystem-k512-pair-policies`, `make tinyvit-sparsity-study`, `docs/SAP_VPU_MODEL_MAPPING_CONTRACT.md` |
| FPGA evidence | The current stream-enabled `sap_vpu_subsystem` passes Artix-7 OOC implementation at 140 MHz using 3067 LUTs/1656 FFs with +0.021 ns WNS and no DSP/BRAM. The selected four-output-pair stream matrix annotates 7167/7230 routed nets with High confidence. Global-12.5% and budget-13.40% reduce VDOTs by 15.04%/15.53%, total reads by 4.55%/4.80%, and reported dynamic energy per set by 10.58%/10.94%. Vivado rounds all policy dynamic power to 0.015 W, so no average-power delta is claimed. External RAM, CPU, full SoC, and board power remain outside the claim. | `make fpga-vpu-synth`, `make fpga-vpu-subsystem-k512-stream-policy-power-matrix`, `docs/SAP_VPU_FPGA_FLOW.md` |
| ASIC evidence | The accepted TSMC28 `tt0p9v85c`, 10 ns gate/SAIF checkpoint remains historical standalone-core evidence. A July 24 audit found no newer DC/PrimeTime or Library Compiler; Nangate Liberty cannot be compiled locally, and current core mapping also crashes DC L-2016.03-SP1 during Pass 1. No current core or subsystem ASIC PPA is claimed. | `docs/SAP_VPU_ASIC_FLOW.md` |

The complete stream-enabled `sap_vpu_subsystem`, including the tiled scheduler,
bounded scratchpads, OBI data mover, packed metadata, and final writeback, now
has matched FPGA OOC and gate-SAIF evidence. ASIC front-end checks pass, but
complete mapping is blocked by the local DC/library combination. Larger SRAM
banks and double buffering remain later work rather than current claims.
Software bias/GELU execution, FC2 window partials, and their checked host-side
sum are now covered for the K=128, 128-output slice. One executable runs against
eight generated 16-channel model images while the simulated SoC RAM remains
4 KiB. This proves bounded host-loaded window reuse and host aggregation, not
runtime window swapping or an external-memory loader. The separate gate path now
accumulates all 512 FC2 input channels from captured GELU values and measures a
matched subsystem dynamic-energy reduction. The separate host study now covers
the full 512x128 FC2 matrix over eight images; it supplies numerical and traffic
evidence, not full-model accuracy or end-to-end energy.

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

1. Move current core/subsystem ASIC mapping to a compatible DC plus validated
   timing-library installation before publishing any new ASIC area delta.
2. Run labeled validation and at least one additional Transformer model before
   generalizing the selected single-layer TinyViT policy.
3. Replace register scratchpads with explicit SRAM-macro assumptions only after
   capacity and traffic experiments justify the change.
4. Add a constrained board top after the internal-IP timing result remains
   reproducible.

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
