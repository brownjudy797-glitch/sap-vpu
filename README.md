# SAP-VPU

SAP-VPU means **Sparse-Aware Adaptive-Precision Vector Processing Unit**.

This is the clean project workspace for the CV32E40X/CV-X-IF based SAP-VPU research direction. The old `nutvpu` repository remains the NutShell-bound prototype and baseline.

## Direction

- Host core: CV32E40X through CV-X-IF.
- Accelerator: sparse-aware adaptive-precision vector coprocessor.
- Workload: TinyViT and edge vision transformer inference.
- Baseline: legacy NutShell + VPU prototype in `~/Program/nutvpu`.

## First Milestones

1. Fetch CV32E40X into `third_party/cv32e40x`.
2. Build a minimal CV32E40X ROM/RAM/UART/OBI SoC.
3. Attach SAP-VPU through the CV-X-IF adapter.
4. Port RV32 bare-metal `hello`, then `vpu_prec_test`, then TinyViT ops.

## Useful Commands

```bash
make plan-check
make corev-fetch
make lint-adapter
```

