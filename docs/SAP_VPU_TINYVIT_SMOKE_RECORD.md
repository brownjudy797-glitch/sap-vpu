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

The full-input-channel FC1 slice has a separate system smoke:

```sh
make tinyvit-fc1-k128-smoke
```

It validates two image-derived tokens across all 128 FC1 input channels and eight
of the 512 output channels. SAP-VPU produces the INT32 accumulators; CV32E40X
then executes accumulator-domain bias addition, Q16 requantization, and an INT8
GELU lookup. The test is a correctness checkpoint and does not yet export
paper-facing cycle or energy measurements.

Focused summary-only command:

```sh
python3 scripts/summarize_tinyvit_counters.py work/tinyvit/tinyvit_smoke_counters.csv
```

## Data Fixture Interface

The `tinyvit_mlp2` portion of the smoke no longer owns its packed words or its
integer golden result in hand-written assembly. `make tinyvit-fixture` validates
a JSON fixture and generates the assembler include, testbench golden include,
and a metadata record under `TINYVIT_BUILD_DIR/fixture/`. The tracked
`sw/baremetal/fixtures/tinyvit_mlp2_activation.json` is now the default. It
contains two real-image activation slices and quantized `fc1/fc2` slices from
timm TinyViT-5M checkpoint `6887cbcb...579c82`. The earlier
`tinyvit_mlp2_checkpoint.json` basis-probe fixture and
`tinyvit_mlp2_smoke.json` synthetic fixture remain regressions.

The generated SystemVerilog include also carries packed FC1/FC2 operands, FC1
golden outputs, requantized ReLU hidden words, and FC2 golden outputs. The subsystem
gate testbench uses these arrays to drive the same fixture through three
autonomous tiles instead of duplicating test data.

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
zero zero-points, positive scales, and provenance. An optional FC1 right-shift
requantization prevents hidden INT8 overflow; the real-activation fixture uses
`shift=7`. A fixture marked
`checkpoint` must carry a 64-character checkpoint SHA-256. The default fixture
also records tensor slices, checkpoint/image URLs and hashes, preprocessing,
and selected full-model FC1/GELU/FC2 float values.

This interface proves integer data-path correctness for a real activation and
weight slice. The hardware mapping computes a four-channel partial contribution,
then applies power-of-two requantization and ReLU without bias. The actual model
uses all channels, bias, and exact GELU; these values are recorded as float
references but are not executed by the VPU path. Consequently, this fixture is
not a full TinyViT layer or inference claim.

The same tracked JSON also contains an `fc1_k128` fixture. It preserves both
selected tokens, expands the FC1 reduction from 4 to all 128 input channels,
and covers eight output channels. The preparation script validates the integer
golden result and packs the matrices as four output tiles, each with 16 K=8
chunks. Bare-metal setup copies the 256-byte activation tile and 1024-byte
weight tile from ROM to SoC RAM because the VPU DMA intentionally accesses RAM
only.

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
- An INT8 `tinyvit_mlp2` projection with two image-derived tokens and a real data
  dependency: 4 input -> 4 register-packed hidden -> requantization/ReLU -> 2
  output. It is a partial MLP-shaped smoke, not a full residual block.
- An INT8 FC1 output slice with two image-derived tokens, all 128 input
  channels, and eight output channels. Software iterates four 2-channel output
  tiles through the existing four-word scratchpads and accumulates 16 signed
  32-bit outputs.
- A three-tile subsystem mapping of the same MLP2 fixture: two FC1 tiles,
  testbench-boundary requantization/ReLU/repack, and one FC2 tile, with 12
  checked VDOTs, 12 OBI reads, and 12 OBI writes per inference.
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

`tinyvit_mlp2` provides the first image-activation projection pair rather than a
repeat of an independent 2x2 macro-tile. Across 16 deterministic repeats it
checks output 148,000, 192 active VDOTs, no hardware skips, and 32 operand plus
96 shared-weight RAM reads. The current result is 2,277 cycles and 1,393
instructions. The dequantized integer path differs from the matching
four-channel ReLU/no-bias float partial by at most `9.44e-5`; its mean absolute
error against the selected full-model FC2 output is `2.524`, which exposes the
large and expected gap from omitted channels, bias, and GELU.

The corresponding 140 MHz subsystem gate-SAIF run repeats the three-tile
mapping 128 times, covering 384 tiles and 1536 VDOTs with 99.86% routed-net
annotation. The real-activation run reports 0.013 W dynamic power and 16.990 nJ
per MLP2 fixture. It excludes software-boundary requantization/ReLU/repacking,
RAM array, CPU, full SoC, and board, so it remains subsystem activity evidence
rather than inference energy. The report rounds to 0.001 W and is numerically
unchanged from the basis-probe run at that resolution, so no power improvement
is claimed.

The K=128 FC1 system smoke checks integer outputs
`[[-15845, -5456, 3075, 943, -1370, 715, 11209, -8424],` and
`[6267, -5774, 8916, 191, -3782, 2786, 5524, -16160]]`. Its four output tiles
issue 512 packed VDOTs, representing 2048 INT8 scalar products, and the
`MAC_ACTIVE` counter reports the expected 512 completed VDOT operations. The
maximum dequantized error against the matching no-bias floating-point FC1 slice
is `0.0208`. CV32E40X software then adds the tracked accumulator-domain biases,
uses Q16 multiplier 387 with shift 16 and signed ties-away rounding, and indexes
a 256-entry INT8 GELU table. The checked GELU outputs are
`[[-1, -6, -1, -5, -8, -6, 2, -9],` and
`[2, -6, 24, -6, -7, -8, -8, -5]]`; their maximum dequantized error against the
captured model GELU slice is `0.01185`. This closes the full FC1 input-channel
reduction and CPU bias/GELU boundary for eight output channels, but it still
omits the other 504 FC1 outputs, FC2, and end-to-end model execution. GELU is
software evidence and is not included in the VPU hardware claim.

Use this record to justify that SAP-VPU now has a repeatable TinyViT-oriented
kernel path, captured model activations, a full-K FC1 output slice, and an
explicit and tested software/hardware boundary for bias/GELU. The next evidence
step is wider output-channel coverage and feeding the post-GELU activation into
FC2 before any full-layer or full-model claim.
