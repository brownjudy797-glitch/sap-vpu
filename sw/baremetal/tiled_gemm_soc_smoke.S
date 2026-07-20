  .section .text.start, "ax"
  .globl _start

  .equ EXIT_ADDR, 0x10000004

  .macro sap_r funct7, funct3, rd, rs1, rs2
    .word ((\funct7 << 25) | (\rs2 << 20) | (\rs1 << 15) | (\funct3 << 12) | (\rd << 7) | 0x0b)
  .endm

  .macro tile_load data, descriptor
    li t0, \data
    li t1, \descriptor
    sap_r 0x20, 0x0, 0, 5, 6
  .endm

  .macro tile_read expected, fail_label
    sap_r 0x22, 0x0, 28, 0, 0
    li t4, \expected
    bne t3, t4, \fail_label
  .endm

  .macro exit_with code
    li t0, EXIT_ADDR
    li t1, \code
    sw t1, 0(t0)
  1:
    wfi
    j 1b
  .endm

_start:
  la sp, _stack_top

  tile_load 0x04030201, 0       /* lhs[0] */
  tile_load 0x01020304, 2       /* lhs[1] */
  tile_load 0x01010101, 1       /* rhs[0] */
  tile_load 0x00010001, 3       /* rhs[1] */

  li t0, 0x112                  /* M=2, N=2, K=4 */
  sap_r 0x21, 0x0, 0, 5, 0
  tile_read 10, fail_full_00
  tile_read 4, fail_full_01
  tile_read 10, fail_full_10
  tile_read 6, fail_full_11

  tile_load 0x7f030201, 0       /* lane 3 must be ignored */
  tile_load 0x7f060504, 1
  li t0, 0x0c9                  /* M=1, N=1, K=3 */
  sap_r 0x21, 0x0, 0, 5, 0
  tile_read 32, fail_tail

  exit_with 1

fail_full_00:
  exit_with 21
fail_full_01:
  exit_with 22
fail_full_10:
  exit_with 23
fail_full_11:
  exit_with 24
fail_tail:
  exit_with 25
