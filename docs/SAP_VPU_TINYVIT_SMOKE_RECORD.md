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
- The skip ratio is product-level. It distinguishes VPU hardware bitmap skips
  from software-scheduled whole-vector skips, rather than treating raw VDOT
  issue count as a hardware skip counter.
- FPGA and ASIC PPA are not covered by this record.

## Reproduction

Run from the repository root after fetching `third_party/cv32e40x`:

```sh
make tinyvit-summary
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

## Data Fixture Interface

The `tinyvit_mlp2` portion of the smoke no longer owns its packed words or its
integer golden result in hand-written assembly. `make tinyvit-fixture` validates
a JSON fixture and generates the assembler include, testbench golden include,
and a metadata record under `TINYVIT_BUILD_DIR/fixture/`. The tracked
`sw/baremetal/fixtures/tinyvit_mlp2_smoke.json` preserves the current smoke
case.

To run a separately exported fixture without overwriting the default work
directory:

```sh
make tinyvit-smoke \
  TINYVIT_FIXTURE_JSON=/absolute/path/to/tinyvit_mlp2.json \
  TINYVIT_BUILD_DIR=/absolute/path/to/work/tinyvit_checkpoint
```

The accepted `sap-vpu-tinyvit-mlp2-int8-v1` schema deliberately has a small
fixed contract: two tokens, four INT8 input channels, four INT8 first-projection
rows, and two INT8 second-projection rows. It requires symmetric INT8 metadata,
zero zero-points, positive scales, and provenance. A fixture marked
`checkpoint` must carry a 64-character checkpoint SHA-256; the tracked
`smoke` fixture is explicitly marked as synthetic.

This interface proves integer data-path correctness for an exported projection
slice. It does not yet support bias, non-zero zero-points, GELU, arbitrary
dimensions, or float-reference error measurement. Consequently, loading a
checkpoint-derived fixture is not by itself a full TinyViT inference claim.
Those features remain required before reporting model-accuracy or end-to-end
energy results.

## Evidence Covered

The current smoke covers the next paper-roadmap evidence hooks:

- Static INT8 dense baseline.
- Larger `dense_x4` INT8 row that repeats the same deterministic macro-tile 64
  times for a less setup-dominated baseline shape.
- Dense INT8 and adaptive INT4 block-local reuse baselines with the same VDOT
  count and lower observed RAM tile traffic.
- Static low-bit INT4 and INT2 policies.
- Adaptive INT4 bitmap sparse and lane policy, including one non-contiguous
  bitmap policy row.
- A structured `adaptive_sparse75` policy row with 25% active INT4 lanes and
  75% product-level skip.
- A structured `adaptive_sparse75_schedule` row that schedules one live INT4
  vector for every four logical vectors. It preserves 1,024 active products,
  records 3,072 software-scheduled skips, and issues 128 VDOTs instead of 512.
- An INT8 `tinyvit_mlp2` projection with two tokens and a real data dependency:
  4 input -> 4 register-packed hidden -> ReLU -> 2 output. It is a
  MLP-shaped smoke, not a full residual block.
- Three policy-level ablations: no sparse skip, no lane gating, and no
  precision gating.
- Testbench assertion that the smoke performs 11392 operand/weight reads from
  the RAM tile scratch region.
- CSV export for observed per-kernel operand reads, weight reads, and total RAM
  tile reads.
- Counter export for cycles, instruction count, MAC active count, hardware skip
  count, software-scheduled skip count, sparse state, lane state, and
  RAM-loaded packed-word tile traffic.
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

`adaptive_sparse75_schedule` is a software mapping experiment, not a new VPU
hardware sparse-skip mechanism. In the current smoke it uses 128 issued VDOTs,
1,024 active products, 3,072 scheduled product skips, 256 RAM tile reads, and
1,700 cycles. The existing bitmap-only `adaptive_sparse75` row has the same
counter-visible active-product count but 512 issued VDOTs, 768 RAM tile reads,
and 4,696 cycles. The 2.762x cycle ratio is therefore useful evidence that a
structured workload schedule can reduce issued work and traffic; it is not a
direct hardware-bitmap speedup or a final TinyViT claim.

`tinyvit_mlp2` provides the first data-dependent projection pair rather than a
repeat of an independent 2x2 macro-tile. Across 16 deterministic repeats it
checks output 1,120, 192 active VDOTs, no hardware skips, and 32 operand plus
96 shared-weight RAM reads. Its negative fourth hidden channel is clamped by
ReLU before the output projection. The current 2,004-cycle result is functional
smoke evidence only: it has no residual path, quantization-scale error, or full
TinyViT dimensions.

Use this record to justify that SAP-VPU now has a repeatable TinyViT-oriented
kernel path and a controlled input-fixture boundary. The next evidence step is
a checkpoint-derived fixture within this contract, followed by larger dimensions,
bias/GELU handling, and float-error accounting before any full-model claim.
