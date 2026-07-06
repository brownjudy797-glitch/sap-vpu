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
| Paper workload | TinyViT MLP smoke now repeats a four-block, 2-token x 2-output-channel policy tile 16 times and exports INT8/INT4/INT2 policy, structured and unstructured sparse policy counters, ablations, dense/adaptive reuse rows, and observed RAM tile traffic; current numbers remain smoke-only evidence. | `make tinyvit-summary`, `docs/SAP_VPU_TINYVIT_SMOKE_RECORD.md` |

The next milestone is not another interface feature. The next milestone is a
larger TinyViT-style kernel shape with clearer separation between compute,
sparsity policy, and memory-traffic evidence.

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

1. **TinyViT MLP/GEMM kernel smoke**
   - Add a bare-metal kernel that executes a small deterministic MLP/GEMM-like
     workload through SAP-VPU custom instructions.
   - Keep the first kernel small enough for ROM/RAM simulation and exact golden
     checking.
   - Verify output values and exit code in the existing CORE-V SoC test style.

2. **Kernel counters**
   - Read counters after each kernel variant: cycle, instruction count, active
     MAC count, skipped elements, sparse bitmap state, and active lane state.
   - Save results in generated output under `work/` or `results/`, not as source
     claims until reproduced.

3. **Policy variants**
   - Static INT8 dense baseline.
   - Static low-bit baseline: INT4 and, where numerically meaningful, INT2.
   - Adaptive policy: precision plus sparse bitmap plus lane setting chosen from
     a simple importance rule.

4. **Ablation variants**
   - Full SAP-VPU policy.
   - No sparse skip: dense bitmap with the same precision.
   - No lane gating: all lanes active with the same sparse bitmap.
   - No precision gating: fixed INT8 with the same sparse/lane policy.

5. **Result tables**
   - Main TinyViT kernel table: cycles, speedup, active MACs, skipped elements,
     effective skip ratio, and output correctness.
   - Policy table: dense INT8 vs low-bit vs adaptive policy.
   - Ablation table: full vs disabled sparse/lane/precision features.
   - Memory-awareness table: observed RAM tile operand reads, weight reads, and
     partial sum traffic for each kernel variant.

6. **Hardware evidence**
   - Run FPGA smoke/timing only after the kernel path is stable.
   - Run ASIC Nangate45 area/timing/power after RTL behavior and ablation points
     are locked.
   - State SRAM blackbox or macro assumptions before using PPA numbers.

## TinyViT Kernel Plan

The first paper-facing kernel should model a TinyViT MLP block rather than the
whole network. It should be deterministic, small, and repeatable:

- Input shape: a fixed token-vector tile that fits the minimal SoC memory model.
- Compute shape: packed dot products representing MLP/GEMM inner loops.
- Precision modes: INT8, INT4, INT2 where packing and expected values are exact.
- Sparsity modes: dense, structured bitmap, and at least one unstructured bitmap.
- Output check: compare against a golden scalar result and fail through MMIO exit
  code on mismatch.

Do not add a complex scheduler for the first kernel. A simple hand-written
bare-metal kernel is enough if it gives exact correctness and counter evidence.

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
| Sparsity | Dense bitmap | Structured and unstructured bitmap | skip count, cycles |
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
