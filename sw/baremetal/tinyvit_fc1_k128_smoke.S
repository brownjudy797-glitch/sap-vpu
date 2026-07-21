  .section .text.start, "ax"
  .globl _start

  .equ OUT_BASE,      0x00010000
  .equ WINDOW_ID_BASE, 0x000100f0
  .equ INPUT_BASE,    0x00010100
  .equ WEIGHT_BASE,   0x00010200
  .equ FC2_OUT_BASE,  0x00010020
  .equ FC2_SUM_BASE,  0x00010030
  .equ FC2_INPUT_BASE, 0x00010a00
  .equ FC2_WEIGHT_BASE, 0x00010a20
  .equ EXIT_ADDR,     0x10000004

  .macro sap_r funct7, funct3, rd, rs1, rs2
    .word ((\funct7 << 25) | (\rs2 << 20) | (\rs1 << 15) | (\funct3 << 12) | (\rd << 7) | 0x0b)
  .endm

  .macro tile_dma_reg base, descriptor
    mv t0, \base
    li t1, \descriptor
    sap_r 0x23, 0x0, 0, 5, 6
  .endm

  .macro tile_store base
    li t0, \base
    sap_r 0x24, 0x0, 0, 5, 0
  .endm

  .macro exit_with code
    li t0, EXIT_ADDR
    li t1, \code
    sw t1, 0(t0)
  1:
    wfi
    j 1b
  .endm

  .macro check_gelu value, bias_offset, expected_offset, destination
    lw t4, \bias_offset(s10)
    add t4, \value, t4
    li t5, TINYVIT_FC1_K128_GELU_REQUANT_MULTIPLIER
    mul t4, t4, t5
    bgez t4, 5f
    neg t4, t4
    li t5, TINYVIT_FC1_K128_GELU_REQUANT_ROUND
    add t4, t4, t5
    srli t4, t4, TINYVIT_FC1_K128_GELU_REQUANT_SHIFT
    neg t4, t4
    j 6f
5:
    li t5, TINYVIT_FC1_K128_GELU_REQUANT_ROUND
    add t4, t4, t5
    srli t4, t4, TINYVIT_FC1_K128_GELU_REQUANT_SHIFT
6:
    li t5, 127
    ble t4, t5, 7f
    li t4, 127
7:
    li t5, -128
    bge t4, t5, 8f
    li t4, -128
8:
    addi t4, t4, 128
    la t5, tinyvit_fc1_k128_gelu_lut
    add t5, t5, t4
    lb t4, 0(t5)
    lb t5, \expected_offset(s11)
    bne t4, t5, fail_postprocess
    mv \destination, t4
  .endm

  .include "tinyvit_fc1_k128_fixture.inc"

_start:
  la sp, _stack_top
  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT */

  li t0, WINDOW_ID_BASE
  lw t0, 0(t0)
  li t1, TINYVIT_FC1_K128_OUTPUT_WINDOWS
  bgeu t0, t1, fail_window

  li s7, TINYVIT_FC1_K128_OUTPUT_TILES
  li s8, WEIGHT_BASE
  la s9, tinyvit_fc1_k128_expected
  slli t1, t0, 7
  add s9, s9, t1
  la s10, tinyvit_fc1_k128_bias
  slli t1, t0, 6
  add s10, s10, t1
  la s11, tinyvit_fc1_k128_gelu_expected
  slli t1, t0, 5
  add s11, s11, t1

3:
  li s0, INPUT_BASE
  mv s1, s8
  li s2, TINYVIT_FC1_K128_CHUNKS
  li s3, 0
  li s4, 0
  li s5, 0
  li s6, 0

4:
  tile_dma_reg s0, 8             /* input: four packed words */
  tile_dma_reg s1, 9             /* weight: four packed words */
  li t0, 0x212                   /* M=2, N=2, K=8 */
  sap_r 0x21, 0x0, 0, 5, 0
  tile_store OUT_BASE

  li t0, OUT_BASE
  lw a0, 0(t0)
  lw a1, 4(t0)
  lw a2, 8(t0)
  lw a3, 12(t0)
  add s3, s3, a0
  add s4, s4, a1
  add s5, s5, a2
  add s6, s6, a3

  addi s0, s0, 16
  addi s1, s1, TINYVIT_FC1_K128_WEIGHT_CHUNK_STRIDE
  addi s2, s2, -1
  bnez s2, 4b

  lw t4, 0(s9)
  bne s3, t4, fail_output
  lw t4, 4(s9)
  bne s4, t4, fail_output
  lw t4, 8(s9)
  bne s5, t4, fail_output
  lw t4, 12(s9)
  bne s6, t4, fail_output

  check_gelu s3, 0, 0, a0
  check_gelu s4, 4, 1, a1
  check_gelu s5, 0, 2, a2
  check_gelu s6, 4, 3, a3

  li t0, TINYVIT_FC1_K128_OUTPUT_TILES
  sub t0, t0, s7
  srli t1, t0, 2
  slli t1, t1, 4
  andi t0, t0, 3
  slli t0, t0, 1
  add t0, t0, t1
  li t1, FC2_INPUT_BASE
  add t0, t0, t1
  sb a0, 0(t0)
  sb a1, 1(t0)
  sb a2, 8(t0)
  sb a3, 9(t0)

  addi s8, s8, 16
  addi s9, s9, 16
  addi s10, s10, 8
  addi s11, s11, 4
  addi s7, s7, -1
  bnez s7, 3b

  li s0, FC2_INPUT_BASE
  li s1, FC2_WEIGHT_BASE
  li s2, TINYVIT_FC2_K8_CHUNKS
  li s3, 0
  li s4, 0
  li s5, 0
  li s6, 0
.Lfc2_loop:
  tile_dma_reg s0, 8
  tile_dma_reg s1, 9
  li t0, 0x212                   /* M=2, N=2, K=8 */
  sap_r 0x21, 0x0, 0, 5, 0
  tile_store FC2_OUT_BASE

  li t0, FC2_OUT_BASE
  lw a0, 0(t0)
  lw a1, 4(t0)
  lw a2, 8(t0)
  lw a3, 12(t0)
  add s3, s3, a0
  add s4, s4, a1
  add s5, s5, a2
  add s6, s6, a3
  addi s0, s0, 16
  addi s1, s1, 16
  addi s2, s2, -1
  bnez s2, .Lfc2_loop

  li t0, WINDOW_ID_BASE
  lw t1, 0(t0)
  slli t1, t1, 4
  la t0, tinyvit_fc2_k8_expected
  add t0, t0, t1
  lw t1, 0(t0)
  bne s3, t1, fail_fc2
  lw t1, 4(t0)
  bne s4, t1, fail_fc2
  lw t1, 8(t0)
  bne s5, t1, fail_fc2
  lw t1, 12(t0)
  bne s6, t1, fail_fc2

  li t0, FC2_SUM_BASE
  sw s3, 0(t0)
  sw s4, 4(t0)
  sw s5, 8(t0)
  sw s6, 12(t0)

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  li t4, 1040
  bne t3, t4, fail_mac_count

  exit_with 1

fail_output:
  exit_with 41
fail_mac_count:
  exit_with 45
fail_postprocess:
  exit_with 46
fail_fc2:
  exit_with 47
fail_window:
  exit_with 48
