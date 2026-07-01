# SAP-VPU Baseline Ledger

This ledger records which legacy `nutvpu` artifacts are allowed to inform the SAP-VPU paper-facing rewrite. It does not vendor legacy sources or generated results into this repository.

## Legacy Source Anchors

| Legacy path | Role in SAP-VPU |
| --- | --- |
| `~/Program/nutvpu/NutShell/src/main/scala/nutcore/backend/fu/VPU.scala` | Main source for the proven NutShell-bound VPU control/dataflow. |
| `~/Program/nutvpu/nexus-am/tests/` | Bare-metal regression source for precision, GEMM, TinyViT ops, and stress tests. |
| `~/Program/nutvpu/scripts/run_vpu_sw_regression.sh` | Baseline software regression driver. |
| `~/Program/nutvpu/scripts/run_synth.sh` | Baseline RTL generation and Synopsys DC synthesis flow. |
| `~/Program/nutvpu/results/` | Legacy result CSVs used only as starting evidence anchors. |

## Current Legacy Evidence Snapshot

Run:

```bash
make legacy-summary
```

Current local snapshot from `~/Program/nutvpu/results`:

| Evidence | Snapshot |
| --- | --- |
| Structured sparse best case | `fc2 INT8 sparse_structured sparsity_x10=750`, `2.563x` speedup, `60.98%` cycle reduction. |
| Sparse worst case | `fc1 INT8 sparse_unstructured sparsity_x10=500`, `0.981x` speedup, `-1.93%` cycle reduction. |
| RTL zero-bypass software/RTL speedup | min `1.876x`, average `2.168x`, max `2.729x`; active cycles changed by `-33.333%`. |
| DC total cell area delta | `69609.539654` to `69931.931656`, `+0.463%`. |

## Reproduction Policy

- Treat these values as baseline anchors, not final paper numbers.
- Reproduce final TinyViT/PPA claims in `sap-vpu` or document a flow-equivalence argument.
- Keep generated directories ignored: `work/`, `reports/`, `results/`, `logs/`, `netlist/`, `third_party/`.
- If a legacy number cannot be reproduced, weaken the paper claim or move it to background context.
