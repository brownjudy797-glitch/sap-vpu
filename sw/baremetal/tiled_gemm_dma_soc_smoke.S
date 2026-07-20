  .section .text.start, "ax"
  .globl _start

  .equ RAM_BASE,  0x00010000
  .equ RHS_BASE,  0x00010020
  .equ EXIT_ADDR, 0x10000004

  .macro sap_r funct7, funct3, rd, rs1, rs2
    .word ((\funct7 << 25) | (\rs2 << 20) | (\rs1 << 15) | (\funct3 << 12) | (\rd << 7) | 0x0b)
  .endm

  .macro tile_dma base, descriptor
    li t0, \base
    li t1, \descriptor
    sap_r 0x23, 0x0, 0, 5, 6
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

  li s0, RAM_BASE
  li t0, 0x04030201
  sw t0, 0(s0)
  li t0, 0x01020304
  sw t0, 4(s0)

  li s1, RHS_BASE
  li t0, 0x01010101
  sw t0, 0(s1)
  li t0, 0x00010001
  sw t0, 4(s1)

  tile_dma RAM_BASE, 4             /* input, two words */
  tile_dma RHS_BASE, 5             /* weight, two words */
  li t0, 0x112                     /* M=2, N=2, K=4 */
  sap_r 0x21, 0x0, 0, 5, 0
  tile_read 10, fail_full_00
  tile_read 4, fail_full_01
  tile_read 10, fail_full_10
  tile_read 6, fail_full_11

  li t0, 0x7f030201
  sw t0, 0(s0)
  li t0, 0x7f060504
  sw t0, 0(s1)
  tile_dma RAM_BASE, 2             /* input, one word */
  tile_dma RHS_BASE, 3             /* weight, one word */
  li t0, 0x0c9                     /* M=1, N=1, K=3 */
  sap_r 0x21, 0x0, 0, 5, 0
  tile_read 32, fail_tail

  li t0, 0x04030201
  sw t0, 0(s0)
  li t0, 0x08070605
  sw t0, 4(s0)
  li t0, 0x05060708
  sw t0, 8(s0)
  li t0, 0x01020304
  sw t0, 12(s0)
  li t0, 0x01010101
  sw t0, 0(s1)
  sw t0, 4(s1)
  li t0, 0x00010001
  sw t0, 8(s1)
  sw t0, 12(s1)
  tile_dma RAM_BASE, 8             /* input, four words */
  tile_dma RHS_BASE, 9             /* weight, four words */
  li t0, 0x212                     /* M=2, N=2, K=8 */
  sap_r 0x21, 0x0, 0, 5, 0
  tile_read 36, fail_k8_00
  tile_read 16, fail_k8_01
  tile_read 36, fail_k8_10
  tile_read 20, fail_k8_11

  li t0, 0x04030201
  sw t0, 0(s0)
  li t0, 0x7f7f7f05
  sw t0, 4(s0)
  li t0, 0x02030405
  sw t0, 0(s1)
  li t0, 0x7f7f7f01
  sw t0, 4(s1)
  tile_dma RAM_BASE, 4             /* input, two words */
  tile_dma RHS_BASE, 5             /* weight, two words */
  li t0, 0x149                     /* M=1, N=1, K=5 */
  sap_r 0x21, 0x0, 0, 5, 0
  tile_read 35, fail_k5

  exit_with 1

fail_full_00:
  exit_with 31
fail_full_01:
  exit_with 32
fail_full_10:
  exit_with 33
fail_full_11:
  exit_with 34
fail_tail:
  exit_with 35
fail_k8_00:
  exit_with 36
fail_k8_01:
  exit_with 37
fail_k8_10:
  exit_with 38
fail_k8_11:
  exit_with 39
fail_k5:
  exit_with 40
