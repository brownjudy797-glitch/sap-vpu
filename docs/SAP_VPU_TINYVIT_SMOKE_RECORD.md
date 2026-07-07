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

To save the same Markdown summary as a reproducible table artifact:

```sh
make tinyvit-paper-table
```

This writes `work/tinyvit/tinyvit_paper_table.md`. That generated file is the
current source of truth for smoke numbers; do not hand-copy it into this
document as a fixed claim.

Focused summary-only command:

```sh
python3 scripts/summarize_tinyvit_counters.py work/tinyvit/tinyvit_smoke_counters.csv
```

## Evidence Covered

The current smoke covers the next paper-roadmap evidence hooks:

- Static INT8 dense baseline.
- Dense INT8 and adaptive INT4 block-local reuse baselines with the same VDOT
  count and lower observed RAM tile traffic.
- Static low-bit INT4 and INT2 policies.
- Adaptive INT4 bitmap sparse and lane policy, including one non-contiguous
  bitmap policy row.
- A structured `adaptive_sparse75` policy row with 25% active INT4 lanes and
  75% product-level skip.
- Three policy-level ablations: no sparse skip, no lane gating, and no
  precision gating.
- Testbench assertion that the smoke performs 7936 operand/weight reads from
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
