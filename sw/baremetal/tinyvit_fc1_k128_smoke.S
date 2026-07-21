  .section .text.start, "ax"
  .globl _start

  .equ OUT_BASE,      0x00010000
  .equ INPUT_BASE,    0x00010100
  .equ WEIGHT_BASE,   0x00010200
  .equ FIXTURE_WORDS, 64
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

  .include "tinyvit_fc1_k128_fixture.inc"

_start:
  la sp, _stack_top
  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT */

  la t0, tinyvit_fc1_k128_inputs
  li t1, INPUT_BASE
  li t2, FIXTURE_WORDS
1:
  lw t3, 0(t0)
  sw t3, 0(t1)
  addi t0, t0, 4
  addi t1, t1, 4
  addi t2, t2, -1
  bnez t2, 1b

  la t0, tinyvit_fc1_k128_weights
  li t1, WEIGHT_BASE
  li t2, FIXTURE_WORDS
2:
  lw t3, 0(t0)
  sw t3, 0(t1)
  addi t0, t0, 4
  addi t1, t1, 4
  addi t2, t2, -1
  bnez t2, 2b

  li s0, INPUT_BASE
  li s1, WEIGHT_BASE
  li s2, TINYVIT_FC1_K128_CHUNKS
  li s3, 0
  li s4, 0
  li s5, 0
  li s6, 0

3:
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
  addi s1, s1, 16
  addi s2, s2, -1
  bnez s2, 3b

  li t4, TINYVIT_FC1_K128_EXPECTED_00
  bne s3, t4, fail_output_00
  li t4, TINYVIT_FC1_K128_EXPECTED_01
  bne s4, t4, fail_output_01
  li t4, TINYVIT_FC1_K128_EXPECTED_10
  bne s5, t4, fail_output_10
  li t4, TINYVIT_FC1_K128_EXPECTED_11
  bne s6, t4, fail_output_11

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  li t4, 128
  bne t3, t4, fail_mac_count

  exit_with 1

fail_output_00:
  exit_with 41
fail_output_01:
  exit_with 42
fail_output_10:
  exit_with 43
fail_output_11:
  exit_with 44
fail_mac_count:
  exit_with 45
