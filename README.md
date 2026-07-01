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
make lint
make sim
make encoding-check
make legacy-summary
```

## Current Engineering Slice

- `rtl/sap_vpu_pkg.sv`: shared SAP-VPU opcode, operation, precision, and counter constants.
- `rtl/sap_vpu_core.sv`: first front-door SAP-VPU execution model for adapter and software bring-up.
- `platforms/corev/rtl/cvxif_sap_vpu_adapter.sv`: flattened CV-X-IF-to-SAP-VPU command adapter.
- `sw/baremetal/sap_vpu_custom.h`: bare-metal custom-0 encoding helpers.
- `docs/SAP_VPU_PAPER_ROADMAP.md`: IEEE-hardware-paper evidence plan.
- `docs/SAP_VPU_BASELINE_LEDGER.md`: traceable legacy `nutvpu` evidence map.
