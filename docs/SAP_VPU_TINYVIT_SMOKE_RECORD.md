# SAP-VPU TinyViT Smoke Record

## Scope

This record captures the current TinyViT MLP/GEMM smoke evidence in the
SAP-VPU platform. It is a reproducibility checkpoint, not a paper-facing final
result table.

Current boundary:

- The workload is a small deterministic bare-metal smoke kernel, not full
  TinyViT end-to-end inference.
- Each row repeats a four-block micro-tile 16 times to reduce one-time setup
  overhead and expose more RAM traffic, but the kernel is still a smoke workload.
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
| dense | int8 | none | 6048 | 1825 | 1.000 | 0.000 | 4 | 384 | 512 | 1024 | 1024 | 2560 |
| static_lowbit | int4 | none | 2560 | 1205 | 1.515 | 0.000 | 8 | 256 | 512 | 512 | 512 | 1536 |
| static_int2 | int2 | none | 1536 | 1238 | 1.474 | 0.000 | 16 | 256 | 512 | 512 | 512 | 1536 |
| adaptive | int4 | bitmap | 1280 | 1205 | 1.515 | 0.500 | 4 | 256 | 512 | 512 | 512 | 1536 |
| no_sparse_skip | int4 | none | 1280 | 1238 | 1.474 | 0.500 | 4 | 256 | 512 | 512 | 512 | 1536 |
| no_lane_gating | int4 | bitmap | 1280 | 1205 | 1.515 | 0.500 | 8 | 256 | 512 | 512 | 512 | 1536 |
| no_precision_gating | int8 | bitmap | 1280 | 1204 | 1.516 | 0.000 | 4 | 256 | 512 | 512 | 512 | 1536 |

## Current Compute Shape Table

| Kernel | Vector lanes | VDOT ops | Active products | Skipped products | Active products/cycle |
| --- | ---: | ---: | ---: | ---: | ---: |
| dense | 4 | 256 | 1024 | 0 | 0.561 |
| static_lowbit | 8 | 128 | 1024 | 0 | 0.850 |
| static_int2 | 16 | 128 | 2048 | 0 | 1.654 |
| adaptive | 8 | 128 | 512 | 512 | 0.425 |
| no_sparse_skip | 8 | 128 | 512 | 512 | 0.414 |
| no_lane_gating | 8 | 128 | 512 | 512 | 0.425 |
| no_precision_gating | 4 | 128 | 512 | 0 | 0.425 |

## Current Memory Traffic Table

| Kernel | Operand reads | Weight reads | RAM tile reads | Operand bytes | Weight bytes | Partial sum bytes | Total bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dense | 128 | 256 | 384 | 512 | 1024 | 1024 | 2560 |
| static_lowbit | 128 | 128 | 256 | 512 | 512 | 512 | 1536 |
| static_int2 | 128 | 128 | 256 | 512 | 512 | 512 | 1536 |
| adaptive | 128 | 128 | 256 | 512 | 512 | 512 | 1536 |
| no_sparse_skip | 128 | 128 | 256 | 512 | 512 | 512 | 1536 |
| no_lane_gating | 128 | 128 | 256 | 512 | 512 | 512 | 1536 |
| no_precision_gating | 128 | 128 | 256 | 512 | 512 | 512 | 1536 |

## Evidence Covered

The current smoke covers the next paper-roadmap evidence hooks:

- Static INT8 dense baseline.
- Static low-bit INT4 and INT2 policies.
- Adaptive INT4 bitmap sparse and lane policy.
- Three policy-level ablations: no sparse skip, no lane gating, and no
  precision gating.
- Testbench assertion that the smoke performs 1920 operand/weight reads from
  the RAM tile scratch region.
- CSV export for observed per-kernel operand reads, weight reads, and total RAM
  tile reads.
- Counter export for cycles, instruction count, MAC active count, skip count,
  sparse state, lane state, and RAM-loaded packed-word tile traffic.
- Derived compute-shape reporting for vector lanes, issued VDOT ops, active
  products, skipped products, and active products per cycle.

## Interpretation

This table verifies the experiment plumbing and counter visibility. The
four-block, 16-round repeat makes cycle counts less dominated by setup overhead
than the first single-tile smoke, but the workload is still too small for final
performance claims.

Use this record to justify that SAP-VPU now has a repeatable TinyViT-oriented
kernel path. The next evidence step should broaden the kernel shape, add more
realistic MLP dimensions, and separate compute effects from memory traffic
before making performance comparisons.
