# SAP-VPU IEEE Paper Roadmap

## Paper Argument

In edge TinyViT inference, SAP-VPU shows that a sparse-aware adaptive-precision RISC-V vector coprocessor can be attached through CV-X-IF, supported by TinyViT kernel measurements and FPGA/ASIC evidence, with the boundary that SAP-VPU is not a full RVV processor and does not modify CV32E40X internals.

## Contribution Spine

1. **Portable attachment**: CV32E40X hosts SAP-VPU through CV-X-IF; NutShell remains the legacy baseline.
2. **Low-power datapath**: the VPU combines INT8/INT4/INT2 packed dot-product execution, sparse bitmap skip, and lane/operand/precision gating.
3. **TinyViT evidence chain**: evaluation focuses on MLP/GEMM-heavy TinyViT kernels, mixed-precision policy, sparse structured cases, and PPA ablations.

## Engineering Milestones

| Phase | Deliverable | Acceptance evidence |
| --- | --- | --- |
| 1. Baseline ledger | Trace old `nutvpu` ISA, tests, scripts, and CSV summaries without vendoring old sources. | `make legacy-summary` and `docs/SAP_VPU_BASELINE_LEDGER.md`. |
| 2. CORE-V bring-up | Fetch CV32E40X into ignored `third_party/`, then build a minimal ROM/RAM/UART/OBI SoC. | RV32 `hello` under the CORE-V SoC. |
| 3. CV-X-IF integration | Map CV-X-IF issue/result structs to the flattened SAP-VPU command contract. | Adapter sim covers decode, kill, backpressure, id, and exception propagation. |
| 4. VPU migration | Move the NutVPU-proven instruction groups into SAP-VPU. | `VSET`, `VMOV`, `VDOT`, `VREADCNT`, then precision/sparse/lane counter ops. |
| 5. Paper experiments | Reproduce TinyViT kernel performance and PPA in the paper-facing flow. | Main result table, ablation table, FPGA timing table, ASIC PPA/power table. |

## Minimum Submission Evidence

- Functional: adapter/core Verilator tests plus bare-metal `hello`, `vpu_prec_test`, and TinyViT MLP kernel.
- Performance: dense vs sparse, INT8 vs INT4 vs INT2, structured vs unstructured sparsity.
- Ablation: full SAP-VPU vs no sparse skip vs no lane gating vs no precision gating.
- Hardware: Artix-7 smoke/timing and Nangate45 area/timing/power, with SRAM blackbox assumptions stated when used.
- Claims: no 200 MHz FPGA claim, no full RVV claim, no CV32E40X-core-modification claim without direct evidence.

## Manuscript Skeleton

1. **Introduction**: edge ViT pressure, RVV/general accelerator cost, custom coprocessor portability gap, SAP-VPU response.
2. **Method**: CV-X-IF attachment, ISA contract, packed adaptive-precision datapath, sparse/gating logic, software mapping.
3. **Experiments**: workflow validation, TinyViT kernel results, baselines, ablations, FPGA/ASIC PPA, failure cases.
4. **Discussion**: where SAP-VPU is useful, where full RVV or larger accelerators remain better, and what remains platform-dependent.
