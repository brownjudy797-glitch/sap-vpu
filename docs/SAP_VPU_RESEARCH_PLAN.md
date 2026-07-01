# SAP-VPU Research Plan

SAP-VPU means **Sparse-Aware Adaptive-Precision Vector Processing Unit**.

## Positioning

SAP-VPU is a CV32E40X/CV-X-IF attached vector coprocessor for low-power TinyViT and edge vision transformer inference.

The legacy NutShell-bound prototype remains in `~/Program/nutvpu` and is used only as a baseline and source of validated VPU ideas.

## Core Claims

1. **Portable RISC-V coprocessor attachment**
   - Use CV-X-IF instead of editing the scalar core.
   - Keep the scalar core as host, not the paper contribution.

2. **Adaptive precision**
   - INT8/INT4/INT2 execution modes.
   - Mixed-precision TinyViT policy evaluation.

3. **Sparse-aware low-power execution**
   - Bitmap sparse skip.
   - Lane gating and operand/precision gating.

4. **TinyViT workload focus**
   - Main workloads: TinyViT ops and MLP/GEMM kernels.
   - CNN accelerators remain classic comparison baselines.

## First Implementation Slice

- Fetch CV32E40X into `third_party/cv32e40x`.
- Build a minimal CV32E40X SoC with ROM, RAM, UART, and OBI interconnect.
- Connect `cvxif_sap_vpu_adapter` to the CV-X-IF issue/result path.
- Initially support `VSET`, `VMOV`, `VDOT`, and `VREADCNT`.

## Non-Goals

- No full RVV implementation.
- No CV32E40X core-source modification.
- No cache coherence in the first slice.
- No 200 MHz FPGA claim before timing and board evidence.

