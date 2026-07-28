# SAP-VPU FPGA Evidence Manifest

## Status

This manifest freezes the current FPGA evidence artifacts at the file level.
The repository baseline is commit
`bd59377df21281f4c217c96bc6ac927d0d9bbe26` on
`codex/ieee-paper-v0`, but the evidence was produced from a modified worktree.
The commit alone is therefore not an exact source snapshot. Before manuscript
submission, commit the intended source tree and rerun both summary targets.

All `work/` paths below are ignored build artifacts and are not committed.

## Board Kernel Evidence

Reproduce the two images and board runs, then regenerate the table:

```sh
make fpga-davinci-deit-tile DAVINCI_CLOCK_MHZ=70
make fpga-davinci-deit-tile-board-smoke DAVINCI_CLOCK_MHZ=70
make fpga-davinci-tinyvit-tile DAVINCI_CLOCK_MHZ=70
make fpga-davinci-tinyvit-tile-board-smoke DAVINCI_CLOCK_MHZ=70
make fpga-davinci-model-tile-summary
```

| Model | Model checkpoint SHA-256 | Generated fixture and SHA-256 | Bitstream SHA-256 | Board result |
| --- | --- | --- | --- | --- |
| DeiT-Tiny | `a1311bcf4f24e3c95adaa75535db67bc4412d95535b98f7c1dfd1164dda41c97` | `work/deit_tile/tile_fixture.inc`: `1880292368cc322c886bf3abb20ce96ff07589090d4e35921e4f375008234e84` | `7c3b0c7911f4a89b18ed6eac405ae40ebafccf9bb8723fac351c161dbe0e73fe` | `work/fpga/davinci_deit_fc1_k192_sparse_uart_70/board_smoke_summary.csv` |
| TinyViT-5M | `6887cbcb87b340515b477b1582bdada6a7cafff15720dd1a9c102b3aaa579c82` | `work/tinyvit_tile/tile_fixture.inc`: `f2505c0342a418f51a3efcac07b44e98bb44aee3345229c85fcad078bf52d221` | `830d52637988318727bc16ec7306a0090dce2604239d09791d59d3a515a7b487` | `work/fpga/davinci_tinyvit_fc2_k512_sparse_uart_70/board_smoke_summary.csv` |

The generated board CSV is
`work/fpga/davinci_model_tile_summary/model_tile_board_table.csv`, SHA-256
`bfa91d5c310fcab62fed137e96a73744b7b12eab30d7c646dbeb418662bf6117`.
It contains the six paper-facing latency rows and validates UART and board pass
status before writing output.

## Gate-SAIF Energy Evidence

Rebuild the common subsystem checkpoint, run both policy matrices, and combine
their validated rows:

```sh
make fpga-vpu-synth FPGA_TOP=sap_vpu_subsystem FPGA_OUT_OF_CONTEXT=1 FPGA_CLOCK_MHZ=140 FPGA_BUILD_DIR=work/fpga/vpu_subsystem_140_current
make fpga-vpu-subsystem-k512-stream-policy-power-matrix
make fpga-vpu-subsystem-deit-full-output-power-matrix
make fpga-vpu-subsystem-cross-model-energy-summary
```

| Artifact | SHA-256 |
| --- | --- |
| TinyViT gate fixture `work/tinyvit/fc2_k512/tinyvit_fc2_k512_policy_tb.svh` | `8e668fbf4857082766bf4f0b6ae4bf20f2eddf3047fcf176d5b3ad2c07fe4733` |
| DeiT gate fixture `work/transformer_fixture/deit_full_output/deit_tiny_stream_fixture_tb.svh` | `4322eb9c7caace26b03b5a709566c3820705d0931a2037a8d37ab4dfa118b5f8` |
| Current post-synth DCP | `cddad89e10fca65602c8b36bb9e14d6361afee71df10844fadd7c7f07170b1f1` |
| Current post-route DCP | `e95e3a8c9feae3bfd90069c0f309ee39533ed1424f06586ec0b643d0168c5027` |
| Generated gate-energy CSV | `4a49d24a1120754ca7c062837bdf553cd977fadbd7483dae202baca8bccd3404` |

The generated CSV is
`work/fpga/vpu_subsystem_140_current_cross_model_energy/gate_saif_energy_table.csv`.
The summary target rejects a DCP mismatch, gate-simulation failure, annotation
below 99%, non-High confidence, or power-log mapping/error warning.

## Claim Boundary

- Board rows are bounded `VTSTREAM` kernel intervals, not image-to-class
  latency.
- Gate energy excludes CPU, RAM arrays, interconnect, and board power.
- Policy reductions are compared within one model; absolute TinyViT and DeiT
  energy is not compared because output coverage differs.
- Vivado default-activity board power is not paper-facing evidence.
