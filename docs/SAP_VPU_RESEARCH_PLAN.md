# SAP-VPU Research Plan

SAP-VPU means **Sparse-Aware Adaptive-Precision Vector Processing Unit**.

## Positioning

SAP-VPU is a CV32E40X/CV-X-IF attached vector coprocessor for low-power TinyViT and edge vision transformer inference.

The legacy NutShell-bound prototype remains in `~/Program/nutvpu` and is used only as a baseline and source of validated VPU ideas.

## Core Claims

1. **Portable RISC-V coprocessor attachment**
   - Use CV-X-IF instead of editing the scalar core.
   - Keep the scalar core as host, not the paper contribution.
   - Keep legacy NutShell results as baseline evidence, not as the paper-facing platform.

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
- Extend the first slice with `VSETPREC`, `VSETSPARSE_BMP`, `VSETLANE`, and `VCLEARCNT` once adapter/core smoke tests cover the base path.

## Current CORE-V Bring-Up Slice

- `corev_min_soc` instantiates `cv32e40x_core` directly and connects a minimal ROM/RAM/UART/exit memory map.
- `hello-build` produces an RV32IMC ELF/bin/hex image with the installed RISC-V binutils.
- `hello-smoke` runs the hello image through the minimal SoC, checks the UART transcript, verifies exit code `1`, and lints the wrapper.

## Paper Evidence Ladder

1. Adapter/core lint and simulation.
2. RV32 bare-metal `hello`.
3. SAP-VPU precision and counter probes.
4. TinyViT MLP/GEMM kernel measurements.
5. Precision, sparse, and gating ablations.
6. FPGA timing and ASIC PPA/power tables.

## Non-Goals

- No full RVV implementation.
- No CV32E40X core-source modification.
- No cache coherence in the first slice.
- No 200 MHz FPGA claim before timing and board evidence.
