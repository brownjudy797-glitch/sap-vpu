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

  li t0, 0x12345678
  sap_r 0x09, 0x0, 0, 5, 0      /* VSET x0, t0, x0 */

  li t0, 0x11223344
  sap_r 0x09, 0x1, 28, 5, 0     /* VMOV t3, t0, x0 */
  li t4, 0x11223344
  bne t3, t4, fail_vmov

  li t0, 0x04030201
  li t1, 0x08070605
  sap_r 0x10, 0x0, 28, 5, 6     /* VDOT t3, t0, t1 */
  li t4, 70
  bne t3, t4, fail_vdot

  li t0, 1
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT t3, t0, x0 */
  li t4, 4
  bne t3, t4, fail_count

  li t0, 1
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC x0, t0, x0 */

  li t0, 0x0f
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP x0, t0, x0 */

  li t0, 8
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE x0, t0, x0 */

  li t0, 0x11111111
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* VDOT t3, t0, t1 */
  li t4, 4
  bne t3, t4, fail_precision_sparse

  li t0, 2
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE x0, t0, x0 */

  li t0, 0x11111111
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* VDOT t3, t0, t1 */
  li t4, 2
  bne t3, t4, fail_lane

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT t3, t0, x0 */
  li t4, 10
  bne t3, t4, fail_sparse_count

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT t3, t0, x0 */
  li t4, 0x0f
  bne t3, t4, fail_sparse_state

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT t3, t0, x0 */
  li t4, 2
  bne t3, t4, fail_lane_state

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  li t0, 1
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT t3, t0, x0 */
  li t4, 1
  bne t3, t4, fail_clear

  exit_with 1

fail_vmov:
  exit_with 11

fail_vdot:
  exit_with 12

fail_count:
  exit_with 13

fail_precision_sparse:
  exit_with 14

fail_lane:
  exit_with 15

fail_sparse_count:
  exit_with 16

fail_sparse_state:
  exit_with 17

fail_lane_state:
  exit_with 18

fail_clear:
  exit_with 19
