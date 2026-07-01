# SAP-VPU Literature Matrix

## Comparison Axes

| Axis | SAP-VPU Use |
| --- | --- |
| Host core | CV32E40X main platform; NutShell legacy baseline; CV32E40P/Ibex references. |
| Interface | CV-X-IF coprocessor interface. |
| Precision | INT8, INT4, INT2, mixed precision. |
| Sparsity | Bitmap skip and dense baseline. |
| Workload | TinyViT ops and MLP/GEMM kernels. |
| Platform | Artix-7 FPGA for function/fmax; ASIC synthesis for PPA. |

## Literature Anchors

| Work | Category | Relevance |
| --- | --- | --- |
| CV32E40X eXtension Interface | CORE-V interface | Main coprocessor attachment path. |
| CORE-V XIF specification | Interface specification | Adapter contract target. |
| SPEED | RISC-V multiprecision vector | Closest multiprecision RISC-V vector comparison. |
| RV-SCNN | RISC-V custom AI instruction | Supports custom-instruction edge-AI framing. |
| RISC-V custom SIMD CNN | Custom SIMD accelerator | Relevant domain-specific instruction baseline. |
| Edge ViT accelerator/survey papers | TinyViT/ViT hardware | Workload and evaluation motivation. |

