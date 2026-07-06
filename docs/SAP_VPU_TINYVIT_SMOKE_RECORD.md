# SAP-VPU TinyViT Smoke Record

## Scope

This record captures the current TinyViT MLP/GEMM smoke evidence in the
SAP-VPU platform. It is a reproducibility checkpoint, not a paper-facing final
result table.

Current boundary:

- The workload is a small deterministic bare-metal smoke kernel, not full
  TinyViT end-to-end inference.
- Each row repeats an eight-block, 2-token x 2-output-channel macro-tile 16 times
  to reduce one-time setup overhead and expose more RAM traffic, but the kernel
  is still a smoke workload.
- The dense speedup is local to this smoke run and should not be cited as a
  final performance claim.
- Operand and weight words are loaded from a deterministic RAM tile. The traffic
  numbers are still smoke-kernel tile traffic, not a final cache/off-chip model.
- The skip ratio is product-level, computed from issued VDOT lanes and the
  hardware skipped-products counter rather than raw VDOT issue count.
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

| Kernel | Precision | Sparse | Output | Cycles | Dense speedup | Skip ratio | Active lanes | RAM tile reads | Operand bytes | Weight bytes | Partial sum bytes | Total bytes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dense | int8 | none | 12096 | 3553 | 1.000 | 0.000 | 4 | 768 | 1024 | 2048 | 2048 | 5120 |
| dense_reuse | int8 | none | 12096 | 2882 | 1.233 | 0.000 | 4 | 512 | 1024 | 1024 | 2048 | 4096 |
| static_lowbit | int4 | none | 14592 | 3573 | 0.994 | 0.000 | 8 | 768 | 1024 | 2048 | 2048 | 5120 |
| static_int2 | int2 | none | 5120 | 3671 | 0.968 | 0.000 | 16 | 768 | 1024 | 2048 | 2048 | 5120 |
| adaptive | int4 | bitmap | 7296 | 3672 | 0.968 | 0.500 | 4 | 768 | 1024 | 2048 | 2048 | 5120 |
| adaptive_reuse | int4 | bitmap_reuse | 7296 | 2807 | 1.266 | 0.500 | 4 | 512 | 1024 | 1024 | 2048 | 4096 |
| adaptive_unstructured | int4 | bitmap_unstructured | 7296 | 3575 | 0.994 | 0.500 | 8 | 768 | 1024 | 2048 | 2048 | 5120 |
| no_sparse_skip | int4 | none | 7296 | 3575 | 0.994 | 0.500 | 4 | 768 | 1024 | 2048 | 2048 | 5120 |
| no_lane_gating | int4 | bitmap | 7296 | 3672 | 0.968 | 0.500 | 8 | 768 | 1024 | 2048 | 2048 | 5120 |
| no_precision_gating | int8 | bitmap | 7296 | 3670 | 0.968 | 0.000 | 4 | 768 | 1024 | 2048 | 2048 | 5120 |

## Current Compute Shape Table

| Kernel | Vector lanes | VDOT ops | Active products | Skipped products | Active products/cycle |
| --- | ---: | ---: | ---: | ---: | ---: |
| dense | 4 | 512 | 2048 | 0 | 0.576 |
| dense_reuse | 4 | 512 | 2048 | 0 | 0.711 |
| static_lowbit | 8 | 512 | 4096 | 0 | 1.146 |
| static_int2 | 16 | 512 | 8192 | 0 | 2.232 |
| adaptive | 8 | 512 | 2048 | 2048 | 0.558 |
| adaptive_reuse | 8 | 512 | 2048 | 2048 | 0.730 |
| adaptive_unstructured | 8 | 512 | 2048 | 2048 | 0.573 |
| no_sparse_skip | 8 | 512 | 2048 | 2048 | 0.573 |
| no_lane_gating | 8 | 512 | 2048 | 2048 | 0.558 |
| no_precision_gating | 4 | 512 | 2048 | 0 | 0.558 |

## Current Memory Traffic Table

| Kernel | Operand reads | Weight reads | RAM tile reads | Operand bytes | Weight bytes | Partial sum bytes | Total bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dense | 256 | 512 | 768 | 1024 | 2048 | 2048 | 5120 |
| dense_reuse | 256 | 256 | 512 | 1024 | 1024 | 2048 | 4096 |
| static_lowbit | 256 | 512 | 768 | 1024 | 2048 | 2048 | 5120 |
| static_int2 | 256 | 512 | 768 | 1024 | 2048 | 2048 | 5120 |
| adaptive | 256 | 512 | 768 | 1024 | 2048 | 2048 | 5120 |
| adaptive_reuse | 256 | 256 | 512 | 1024 | 1024 | 2048 | 4096 |
| adaptive_unstructured | 256 | 512 | 768 | 1024 | 2048 | 2048 | 5120 |
| no_sparse_skip | 256 | 512 | 768 | 1024 | 2048 | 2048 | 5120 |
| no_lane_gating | 256 | 512 | 768 | 1024 | 2048 | 2048 | 5120 |
| no_precision_gating | 256 | 512 | 768 | 1024 | 2048 | 2048 | 5120 |

## Evidence Covered

The current smoke covers the next paper-roadmap evidence hooks:

- Static INT8 dense baseline.
- Dense INT8 and adaptive INT4 block-local reuse baselines with the same VDOT
  count and lower observed RAM tile traffic.
- Static low-bit INT4 and INT2 policies.
- Adaptive INT4 bitmap sparse and lane policy, including one non-contiguous
  bitmap policy row.
- Three policy-level ablations: no sparse skip, no lane gating, and no
  precision gating.
- Testbench assertion that the smoke performs 7168 operand/weight reads from
  the RAM tile scratch region.
- CSV export for observed per-kernel operand reads, weight reads, and total RAM
  tile reads.
- Counter export for cycles, instruction count, MAC active count, skip count,
  sparse state, lane state, and RAM-loaded packed-word tile traffic.
- Derived compute-shape reporting for vector lanes, issued VDOT ops, active
  products, skipped products, and active products per cycle.

## Interpretation

This table verifies the experiment plumbing and counter visibility. The
eight-block, 2-token x 2-output-channel, 16-round repeat makes cycle counts less
dominated by setup overhead than the first single-tile smoke, but the workload is
still too small for final performance claims.

The `dense_reuse` and `adaptive_reuse` rows are direct memory-reuse sanity
checks: they preserve the corresponding output and VDOT count while reducing
repeated weight loads inside each block.

Use this record to justify that SAP-VPU now has a repeatable TinyViT-oriented
kernel path. The next evidence step should broaden the kernel shape, add more
realistic MLP dimensions, and separate compute effects from memory traffic
before making performance comparisons.
