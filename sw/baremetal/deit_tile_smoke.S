  .include "tile_fixture.inc"

  .section .text.start, "ax"
  .globl _start

  .equ UART_ADDR, 0x10000000
  .equ EXIT_ADDR, 0x10000004
  .equ UART_DELAY_LOOPS, 5000

  .macro sap_r funct7, funct3, rd, rs1, rs2
    .word ((\funct7 << 25) | (\rs2 << 20) | (\rs1 << 15) | (\funct3 << 12) | (\rd << 7) | 0x0b)
  .endm

  .macro exit_with code
    li t0, EXIT_ADDR
    li t1, \code
    sw t1, 0(t0)
  1:
    wfi
    j 1b
  .endm

  .macro report_counters tag, mac_expected, dma_expected, mac_fail, dma_fail
    li t0, 0
    sap_r 0x1a, 0x0, 28, 5, 0
    mv s3, t3
    li t0, 2
    sap_r 0x1a, 0x0, 28, 5, 0
    mv s4, t3
    li t4, \mac_expected
    bne s4, t4, \mac_fail
    li t0, 7
    sap_r 0x1a, 0x0, 28, 5, 0
    mv s5, t3
    li t4, \dma_expected
    bne s5, t4, \dma_fail
    li a0, \tag
    mv a1, s3
    mv a2, s4
    mv a3, s5
    jal ra, uart_policy_line
  .endm

  .macro clear_counters
    sap_r 0x1d, 0x0, 0, 0, 0
  .endm

_start:
  la sp, _stack_top

  la s0, tile_lhs_words
  li s1, LHS_BASE
  li s2, TILE_MATRIX_WORDS
1:
  lw t0, 0(s0)
  sw t0, 0(s1)
  addi s0, s0, 4
  addi s1, s1, 4
  addi s2, s2, -1
  bnez s2, 1b

  la s0, tile_global_metadata_words
  li s1, GLOBAL_META_BASE
  li s2, TILE_METADATA_WORDS
1:
  lw t0, 0(s0)
  sw t0, 0(s1)
  addi s0, s0, 4
  addi s1, s1, 4
  addi s2, s2, -1
  bnez s2, 1b

  la s0, tile_budget_metadata_words
  li s1, BUDGET_META_BASE
  li s2, TILE_METADATA_WORDS
1:
  lw t0, 0(s0)
  sw t0, 0(s1)
  addi s0, s0, 4
  addi s1, s1, 4
  addi s2, s2, -1
  bnez s2, 1b

  la s0, tile_rhs_words
  li s1, RHS_BASE
  li s2, TILE_MATRIX_WORDS
1:
  lw t0, 0(s0)
  sw t0, 0(s1)
  addi s0, s0, 4
  addi s1, s1, 4
  addi s2, s2, -1
  bnez s2, 1b

  li s0, DESC_BASE
  li t0, LHS_BASE
  sw t0, 0(s0)
  li t0, RHS_BASE
  sw t0, 4(s0)
  li t0, OUT_BASE
  sw t0, 8(s0)
  li t0, TILE_K_BLOCKS
  sw t0, 12(s0)
  sw zero, 16(s0)

  clear_counters
  li t0, DESC_BASE
  sap_r 0x25, 0x0, 0, 5, 0     /* dense M=2, N=2, K=192 stream */

  li t0, OUT_BASE
  lw t3, 0(t0)
  li t4, TILE_DENSE_EXPECT_00
  bne t3, t4, fail_dense_00
  lw t3, 4(t0)
  li t4, TILE_DENSE_EXPECT_01
  bne t3, t4, fail_dense_01
  lw t3, 8(t0)
  li t4, TILE_DENSE_EXPECT_10
  bne t3, t4, fail_dense_10
  lw t3, 12(t0)
  li t4, TILE_DENSE_EXPECT_11
  bne t3, t4, fail_dense_11
  report_counters 68, TILE_DENSE_MAC_ACTIVE, TILE_DENSE_DMA_SAVED, fail_dense_mac, fail_dense_dma

  li s0, DESC_BASE
  li t0, (TILE_K_BLOCKS | 0x100)
  sw t0, 12(s0)
  li t0, GLOBAL_META_BASE
  sw t0, 16(s0)
  clear_counters
  li t0, DESC_BASE
  sap_r 0x25, 0x0, 0, 5, 0

  li t0, OUT_BASE
  lw t3, 0(t0)
  li t4, TILE_GLOBAL_EXPECT_00
  bne t3, t4, fail_global_00
  lw t3, 4(t0)
  li t4, TILE_GLOBAL_EXPECT_01
  bne t3, t4, fail_global_01
  lw t3, 8(t0)
  li t4, TILE_GLOBAL_EXPECT_10
  bne t3, t4, fail_global_10
  lw t3, 12(t0)
  li t4, TILE_GLOBAL_EXPECT_11
  bne t3, t4, fail_global_11
  report_counters 71, TILE_GLOBAL_MAC_ACTIVE, TILE_GLOBAL_DMA_SAVED, fail_global_mac, fail_global_dma

  li t0, BUDGET_META_BASE
  sw t0, 16(s0)
  clear_counters
  li t0, DESC_BASE
  sap_r 0x25, 0x0, 0, 5, 0

  li t0, OUT_BASE
  lw t3, 0(t0)
  li t4, TILE_BUDGET_EXPECT_00
  bne t3, t4, fail_budget_00
  lw t3, 4(t0)
  li t4, TILE_BUDGET_EXPECT_01
  bne t3, t4, fail_budget_01
  lw t3, 8(t0)
  li t4, TILE_BUDGET_EXPECT_10
  bne t3, t4, fail_budget_10
  lw t3, 12(t0)
  li t4, TILE_BUDGET_EXPECT_11
  bne t3, t4, fail_budget_11
  report_counters 66, TILE_BUDGET_MAC_ACTIVE, TILE_BUDGET_DMA_SAVED, fail_budget_mac, fail_budget_dma

  exit_with 1
fail_dense_00:
  exit_with 51
fail_dense_01:
  exit_with 52
fail_dense_10:
  exit_with 53
fail_dense_11:
  exit_with 54
fail_dense_mac:
  exit_with 55
fail_dense_dma:
  exit_with 56
fail_global_00:
  exit_with 61
fail_global_01:
  exit_with 62
fail_global_10:
  exit_with 63
fail_global_11:
  exit_with 64
fail_global_mac:
  exit_with 65
fail_global_dma:
  exit_with 66
fail_budget_00:
  exit_with 71
fail_budget_01:
  exit_with 72
fail_budget_10:
  exit_with 73
fail_budget_11:
  exit_with 74
fail_budget_mac:
  exit_with 75
fail_budget_dma:
  exit_with 76

uart_policy_line:
  addi sp, sp, -32
  sw ra, 28(sp)
  sw s0, 24(sp)
  sw s1, 20(sp)
  sw s2, 16(sp)
  sw s3, 12(sp)
  mv s0, a0
  mv s1, a1
  mv s2, a2
  mv s3, a3
  mv a0, s0
  jal ra, uart_putc
  li a0, 44
  jal ra, uart_putc
  mv a0, s1
  jal ra, uart_hex32
  li a0, 44
  jal ra, uart_putc
  mv a0, s2
  jal ra, uart_hex32
  li a0, 44
  jal ra, uart_putc
  mv a0, s3
  jal ra, uart_hex32
  li a0, 10
  jal ra, uart_putc
  lw s3, 12(sp)
  lw s2, 16(sp)
  lw s1, 20(sp)
  lw s0, 24(sp)
  lw ra, 28(sp)
  addi sp, sp, 32
  ret

uart_hex32:
  addi sp, sp, -16
  sw ra, 12(sp)
  sw s0, 8(sp)
  sw s1, 4(sp)
  mv s0, a0
  li s1, 28
uart_hex32_loop:
  srl t1, s0, s1
  andi t1, t1, 15
  li t2, 10
  bltu t1, t2, uart_hex32_digit
  addi a0, t1, 55
  j uart_hex32_emit
uart_hex32_digit:
  addi a0, t1, 48
uart_hex32_emit:
  jal ra, uart_putc
  addi s1, s1, -4
  bgez s1, uart_hex32_loop
  lw s1, 4(sp)
  lw s0, 8(sp)
  lw ra, 12(sp)
  addi sp, sp, 16
  ret

uart_putc:
  li t0, UART_ADDR
  sw a0, 0(t0)
  li t0, UART_DELAY_LOOPS
uart_putc_delay:
  addi t0, t0, -1
  bnez t0, uart_putc_delay
  ret
