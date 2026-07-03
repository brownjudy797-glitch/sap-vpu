# SAP-VPU TinyViT Smoke Record

## Scope

This record captures the current TinyViT MLP/GEMM smoke evidence in the
SAP-VPU platform. It is a reproducibility checkpoint, not a paper-facing final
result table.

Current boundary:

- The workload is a small deterministic bare-metal smoke kernel, not full
  TinyViT end-to-end inference.
- The dense speedup is local to this smoke run and should not be cited as a
  final performance claim.
- The traffic numbers are packed-register estimates, not SRAM/cache traffic.
- FPGA and ASIC PPA are not covered by this record.

## Reproduction

Run from the repository root after fetching `third_party/cv32e40x`:

```sh
make tinyvit-summary SIM_DIR=/home/rime/Program/sap-vpu/work/sim_tinyvit_ablation
```

The command rebuilds the RV32 bare-metal TinyViT smoke, runs the CV32E40X
minimal SoC simulation, emits `work/tinyvit/tinyvit_smoke_counters.csv`, and
prints the Markdown summary.

Focused summary-only command:

```sh
python3 scripts/summarize_tinyvit_counters.py work/tinyvit/tinyvit_smoke_counters.csv
```

## Current Smoke Table

| Kernel | Precision | Sparse | Output | Cycles | Dense speedup | Skip ratio | Active lanes | Operand bytes | Weight bytes | Partial sum bytes | Total bytes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dense | int8 | none | 150 | 42 | 1.000 | 0.000 | 4 | 16 | 16 | 16 | 48 |
| static_lowbit | int4 | none | 24 | 52 | 0.808 | 0.000 | 8 | 8 | 8 | 8 | 24 |
| adaptive | int4 | bitmap | 12 | 53 | 0.792 | 0.800 | 4 | 8 | 8 | 8 | 24 |
| no_sparse_skip | int4 | none | 12 | 53 | 0.792 | 0.800 | 4 | 8 | 8 | 8 | 24 |
| no_lane_gating | int4 | bitmap | 12 | 53 | 0.792 | 0.800 | 8 | 8 | 8 | 8 | 24 |
| no_precision_gating | int8 | bitmap | 12 | 52 | 0.808 | 0.000 | 4 | 8 | 8 | 8 | 24 |

## Evidence Covered

The current smoke covers the next paper-roadmap evidence hooks:

- Static INT8 dense baseline.
- Static low-bit INT4 policy.
- Adaptive INT4 bitmap sparse and lane policy.
- Three policy-level ablations: no sparse skip, no lane gating, and no
  precision gating.
- Counter export for cycles, instruction count, MAC active count, skip count,
  sparse state, lane state, and packed-register traffic estimate.

## Interpretation

This table verifies the experiment plumbing and counter visibility. The absolute
cycle numbers are dominated by tiny smoke-kernel setup overhead, so they are not
yet useful as performance claims.

Use this record to justify that SAP-VPU now has a repeatable TinyViT-oriented
kernel path. The next evidence step should expand the kernel shape or iteration
count before making performance comparisons.
