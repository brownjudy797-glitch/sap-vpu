# SAP-VPU Phase 0 Report

## Completed

- The existing SAP-VPU RTL, CV-X-IF adapter, CV32E40X minimal SoC, and
  bare-metal smoke path have a passing Phase 0 regression set.
- The TinyViT-like MLP smoke fixture is JSON-defined and generates matching
  assembler and testbench golden data, removing duplicated hand-maintained
  constants.
- The VDOT reference is frozen in `docs/baseline/VDOT_REFERENCE_V0.md`.
- FPGA and ASIC scripts now run from configured work directories so tool
  diagnostics are no longer emitted into the repository root.

## Evidence Level

The current evidence proves a functional custom-instruction path and basic
counter observability. It does not yet prove a deployable model flow, a DMA or
scratchpad-fed tiled GEMM engine, full TinyViT inference, FPGA timing, ASIC
PPA, power efficiency, or comparison with RVV.

## Phase 1 Entry Criteria

1. Keep the Phase 0 regression set green.
2. Specify the model artifact, quantization metadata, tensor layout, and
   layer-to-command mapping for the first real MLP/GEMM workload.
3. Specify a bounded scratchpad and tiled-GEMM command/dataflow contract.
4. Add unit tests for tile addressing, accumulation, tails, and quantized
   output before integrating the new engine with the SoC.

## Deferred Claims

No frequency, area, power, model accuracy, end-to-end latency, or generalized
Transformer support claim is frozen by Phase 0.
