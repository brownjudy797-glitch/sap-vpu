# SAP-VPU TinyViT Smoke Record

## Scope

This record captures the current TinyViT MLP/GEMM smoke evidence in the
SAP-VPU platform. It is a reproducibility checkpoint, not a paper-facing final
result table.

Current boundary:

- The workload is a small deterministic bare-metal smoke kernel, not full
  TinyViT end-to-end inference.
- Each row repeats the same micro-tile 16 times to reduce one-time setup
  overhead, but the kernel is still a smoke workload.
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
| dense | int8 | none | 2400 | 466 | 1.000 | 0.000 | 4 | 256 | 256 | 256 | 768 |
| static_lowbit | int4 | none | 384 | 325 | 1.434 | 0.000 | 8 | 128 | 128 | 128 | 384 |
| adaptive | int4 | bitmap | 192 | 341 | 1.367 | 0.800 | 4 | 128 | 128 | 128 | 384 |
| no_sparse_skip | int4 | none | 192 | 326 | 1.429 | 0.800 | 4 | 128 | 128 | 128 | 384 |
| no_lane_gating | int4 | bitmap | 192 | 341 | 1.367 | 0.800 | 8 | 128 | 128 | 128 | 384 |
| no_precision_gating | int8 | bitmap | 192 | 340 | 1.371 | 0.000 | 4 | 128 | 128 | 128 | 384 |

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

This table verifies the experiment plumbing and counter visibility. The 16-round
repeat makes cycle counts less dominated by setup overhead than the first
single-tile smoke, but the workload is still too small for final performance
claims.

Use this record to justify that SAP-VPU now has a repeatable TinyViT-oriented
kernel path. The next evidence step should broaden the kernel shape, add more
realistic MLP dimensions, and separate compute effects from memory traffic
before making performance comparisons.
