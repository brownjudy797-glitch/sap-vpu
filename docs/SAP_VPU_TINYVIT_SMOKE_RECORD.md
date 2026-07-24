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

It validates two image-derived tokens across all 128 FC1 input channels and sixteen
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
and covers 128 output channels. The preparation script validates the integer
golden result and packs eight 16-channel RAM windows, each containing eight
output tiles with 16 K=8 chunks. Each window contains the 256-byte activation tile, 2048-byte
FC1 weight tile, and 32-byte FC2 weight slice. Simulation runs the same program
once per host-loaded window, so model tensors do not consume code ROM or require
scalar copy loops. This is reproducible test-platform loading, not runtime
window swapping, external-memory DMA, or cache coherence.
The program writes each final 2x2 FC2 partial to SoC RAM. The testbench reports
those values and a host checker verifies that their element-wise sum equals the
tracked 128-channel fixture result.

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
  channels, and 128 output channels across eight 16-channel runs. Software iterates
  eight 2-channel output tiles per window through the existing four-word
  scratchpads and accumulates 256 checked signed 32-bit outputs in total.
- Separate generated code-ROM and model-RAM images for the K=128 smoke. The
  executable is 3112 bytes; all eight windows preserve the checked numerical path
  and independently report `MAC_ACTIVE=1040`.
- Checked host aggregation of the eight independently executed FC2 partials into
  the tracked 128-channel result `[[4190, -1917], [1797, -2253]]`.
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

Across eight 16-channel runs, the K=128 FC1 system smoke checks all 256 tracked
integer outputs. Each run issues 1024 packed FC1 VDOTs, representing 4096 INT8
scalar products. The maximum dequantized error against the matching no-bias
floating-point FC1 slice is `0.05887`. CV32E40X software then adds the tracked
accumulator-domain biases, uses Q16 multiplier 313 with shift 16 and signed
ties-away rounding, and indexes a 256-entry INT8 GELU table. The 256 checked GELU
outputs have maximum dequantized error `0.06325` against the captured model
slice. Each runtime GELU window is written to RAM in two K=8 chunks and consumed
by two FC2 tiles. The eight no-bias window partials are
`[[1307, 163], [-411, -45]]`, `[[3000, -974], [1729, -672]]`,
`[[228, -28], [514, 131]]`, `[[79, 196], [188, -443]]`,
`[[-518, -1616], [-1319, -1609]]`, `[[335, -489], [296, -326]]`,
`[[-344, 417], [313, 300]]`, and `[[103, 414], [487, 411]]`; their checked sum
is `[[4190, -1917], [1797, -2253]]`. The maximum dequantized error against the
matching 128-channel floating-point partial is `0.05627`. FC2 adds 16 VDOTs
per window, so `MAC_ACTIVE` reports 1040 completed VDOT operations in each
independent run. The other 384 FC1 outputs and FC2 input channels, runtime
window swapping, FC2 bias, and end-to-end model execution remain omitted. GELU
is software evidence and is not included in the VPU hardware claim.

The same K=128 executable now checks both selected sparse policies through
generated `VTDMA` descriptors. `global_l1_6p25` sums to
`[[4236, -1983], [1702, -2016]]`; `l1_budget_2pct` sums to
`[[4165, -1983], [1771, -2016]]`; the dense sum remains
`[[4190, -1917], [1797, -2253]]`. Across the full 128-channel, two-token FC2
partial, the global policy issues 120 instead of 128 VDOTs and suppresses four
of 128 payload reads; the budget policy issues 122 VDOTs and suppresses three
reads. Since dropped groups are unevenly distributed, each independent window
checks its generated `MAC_ACTIVE` and `DMA_READ_SAVED` values. The testbench
also checks the aggregate physical OBI read count. The executable is 3,908
bytes in the 4 KiB ROM. Against the selected floating-point partial, the
global/budget maximum absolute errors are `0.05415/0.03485`; these local results
do not establish full-model accuracy.

The host-side `tinyvit-sparsity-study` now broadens that numerical check to the
complete 512-input, 128-output FC2 matrix over eight fixed, hash-checked PyTorch
Hub sample images and all 784 stage-1 tokens per image, for 6,272 token samples.
The sweep holds images, activations, scales, and INT8 weights constant. NRMSE is
normalized by the RMS of the matching floating-point no-bias FC2 output:

| Policy | Group sparsity | Mean abs. error | NRMSE | Payload reads saved |
| --- | ---: | ---: | ---: | ---: |
| Dense INT8 | 0% | 0.06328 | 0.05465 | 0 |
| Layer L1 budget 1% | 3.99% | 0.08349 | 0.07455 | 2,101,120 |
| Layer-global L1 6.25% | 6.25% | 0.09960 | 0.09005 | 3,443,328 |
| Layer L1 budget 2% | 6.77% | 0.10420 | 0.09424 | 3,731,840 |
| Layer-global L1 12.5% | 12.5% | 0.15408 | 0.14012 | 7,250,432 |
| Layer-global L1 25% | 25% | 0.26917 | 0.24092 | 15,968,512 |
| Tile-local L1 25% | 25% | 0.33736 | 0.30443 | 12,845,056 |

Dense execution models 102,760,448 VDOTs and the same number of payload reads.
Only 42 of 802,816 quantized activation groups are naturally all zero. Layer-
global 6.25% sparsity therefore reduces VDOTs by 6.25%, while reusable input
groups limit total payload-read reduction to 3.35%. Global ranking is more
accurate than forcing one dropped group in every 2x2x8 tile. The 1% L1-budget
policy is the conservative candidate; 6.25% layer-global is the throughput
candidate; 25% tile-local remains a stress ablation. None is a final model
policy until end-to-end accuracy is measured. Version 4 orders equal-L1 groups
by flat index so the policy is deterministic across PyTorch versions.

The same full-layer masks are now checked in RTL for output pairs `(0,1)`,
`(42,43)`, `(84,85)`, and `(126,127)`. Dense/global/budget runs respectively
issue `2048/1868/1922` VDOTs and `2048/1956/1985` OBI reads, with 1024 writes in
all cases. The selected pairs expose nonuniform sparsity: global active groups
range from 199 to 248 of 256 per pair. Their 8.79% VDOT and 4.49% read reductions
are representative-slice RTL results, not full-layer averages.

Use this record to justify that SAP-VPU now has a repeatable TinyViT-oriented
kernel path, captured model activations, a full-K FC1 output slice, checked host
aggregation, and an explicit software/hardware boundary for bias/GELU. The next
evidence step is matched gate-SAIF for the representative output-pair masks,
while full-model accuracy remains required before a final policy claim.
