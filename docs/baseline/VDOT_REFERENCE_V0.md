# SAP-VPU VDOT Reference v0

## Purpose

This document freezes the functional VDOT reference used to detect regressions
while SAP-VPU evolves from a CPU-issued custom-instruction path into a tiled
matrix engine. It is a verification baseline, not a paper result table.

## Frozen Configuration

- Scalar host: CV32E40X minimal SoC.
- Attachment: existing flattened SAP-VPU adapter contract, exercised through
  the CV-X-IF-connected SoC path.
- Workload: `tinyvit_mlp2` from
  `sw/baremetal/fixtures/tinyvit_mlp2_smoke.json`.
- Shape: two tokens, four INT8 inputs, four hidden ReLU outputs, and two INT8
  outputs.
- Fixture status: deterministic smoke input with checked provenance metadata;
  it is not a TinyViT checkpoint.

## Reproduction

Run:

```sh
make tinyvit-fixture-check
make tinyvit-smoke \
  TINYVIT_FIXTURE_JSON=sw/baremetal/fixtures/tinyvit_mlp2_smoke.json \
  TINYVIT_BUILD_DIR=work/tinyvit_vdot_v0
make tinyvit-summary \
  TINYVIT_FIXTURE_JSON=sw/baremetal/fixtures/tinyvit_mlp2_smoke.json \
  TINYVIT_BUILD_DIR=work/tinyvit_vdot_v0
```

The generated assembly include, testbench golden include, ROM image, counter
CSV, and rendered tables are intentionally placed under `work/tinyvit_vdot_v0/`.

## Reference Observations

The current `tinyvit_mlp2` row from `make tinyvit-summary` is:

| Output accumulation | Active MAC counter | Skip ratio | Lane state | Cycles | Instructions | Estimated total traffic |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1120 | 192 | 0.000 | 4 | 2004 | 1136 | 1280 bytes |

The output accumulation and counter values are checked by the bare-metal SoC
smoke test. Cycle, instruction, and traffic fields are diagnostic counter
values for this compact fixture; they must not be reported as full-model
throughput, energy, or accuracy results.

## Guardrails

- Preserve this test as an instruction-path regression when changing VDOT,
  adapter handshaking, counters, or the memory system.
- Keep synthetic policy rows separate from this reference. For example,
  `adaptive_sparse75_schedule` is useful for control-path testing, but it is
  not an input-derived sparsity measurement.
- Legacy `nutvpu` values are historical context only. They are not SAP-VPU v0
  results unless reproduced through this platform and documented separately.
