  .section .text.start, "ax"
  .globl _start

  .equ EXIT_ADDR, 0x10000004

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

_start:
  la sp, _stack_top

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* TinyViT MLP/GEMM-like INT8 dense 2x2 tile. */
  li t5, 0

  li t0, 0x04030201             /* token0: [1, 2, 3, 4] */
  li t1, 0x08070605             /* weight0: [5, 6, 7, 8] */
  sap_r 0x10, 0x0, 28, 5, 6     /* VDOT t3, t0, t1 => 70 */
  add t5, t5, t3

  li t1, 0x01010101             /* weight1: [1, 1, 1, 1] */
  sap_r 0x10, 0x0, 28, 5, 6     /* VDOT t3, t0, t1 => 10 */
  add t5, t5, t3

  li t0, 0x01020304             /* token1: [4, 3, 2, 1] */
  li t1, 0x08070605
  sap_r 0x10, 0x0, 28, 5, 6     /* VDOT t3, t0, t1 => 60 */
  add t5, t5, t3

  li t1, 0x01010101
  sap_r 0x10, 0x0, 28, 5, 6     /* VDOT t3, t0, t1 => 10 */
  add t5, t5, t3

  li t4, 150
  bne t5, t4, fail_dense_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  li t4, 4
  bne t3, t4, fail_dense_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  bnez t3, fail_dense_skip

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Low-bit sparse/lane policy tile, standing in for a pruned MLP tile. */
  li t0, 1
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT4 */

  li t0, 0x0f
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP lanes 0..3 */

  li t0, 8
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 8 */

  li t5, 0
  li t0, 0x11111111
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* 4 active INT4 products => 4 */
  add t5, t5, t3

  li t0, 0x22222222
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* 4 active INT4 products => 8 */
  add t5, t5, t3

  li t4, 12
  bne t5, t4, fail_policy_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  li t4, 2
  bne t3, t4, fail_policy_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  li t4, 8
  bne t3, t4, fail_policy_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  li t4, 0x0f
  bne t3, t4, fail_policy_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  li t4, 8
  bne t3, t4, fail_policy_lane

  exit_with 1

fail_dense_output:
  exit_with 11

fail_dense_mac:
  exit_with 12

fail_dense_skip:
  exit_with 13

fail_policy_output:
  exit_with 21

fail_policy_mac:
  exit_with 22

fail_policy_skip:
  exit_with 23

fail_policy_sparse:
  exit_with 24

fail_policy_lane:
  exit_with 25
