  .section .text.start, "ax"
  .globl _start

  .equ EXIT_ADDR, 0x10000004
  .equ RESULT_BASE, 0x00010000
  .equ TINYVIT_TILE_BASE, 0x00010200
  .equ RESULT_MAGIC, 0x54564954
  .equ TINYVIT_ITERS, 16
  .equ TINYVIT_LARGE_ITERS, 64
  .equ TINYVIT_BLOCKS, 8

  .equ TILE_DENSE_BASE, 0
  .equ TILE_DENSE_STRIDE, 16
  .equ TILE_INT4_BASE, 128
  .equ TILE_INT4_STRIDE, 16
  .equ TILE_INT2_BASE, 256
  .equ TILE_INT2_STRIDE, 16
  .equ TILE_INT8_BASE, 384
  .equ TILE_INT8_STRIDE, 16
  .equ TILE_MLP2_BASE, 512

  .macro sap_r funct7, funct3, rd, rs1, rs2
    .word ((\funct7 << 25) | (\rs2 << 20) | (\rs1 << 15) | (\funct3 << 12) | (\rd << 7) | 0x0b)
  .endm

  .macro read_csr rd, csr
    .word ((\csr << 20) | (0 << 15) | (0x2 << 12) | (\rd << 7) | 0x73)
  .endm

  .macro relu reg
    bgez \reg, .Lrelu_\@
    li \reg, 0
.Lrelu_\@:
  .endm

  .macro requant_relu reg
    bgez \reg, .Lrequant_relu_positive_\@
    li \reg, 0
    j .Lrequant_relu_done_\@
.Lrequant_relu_positive_\@:
    li t2, TINYVIT_MLP2_FC1_REQUANT_ROUNDING
    add \reg, \reg, t2
    srai \reg, \reg, TINYVIT_MLP2_FC1_REQUANT_SHIFT
.Lrequant_relu_done_\@:
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

  /* Materialize the deterministic TinyViT tile in RAM before timing kernels. */
  li a1, TINYVIT_TILE_BASE

  li t0, 0x04030201             /* token0: [1, 2, 3, 4] */
  sw t0, TILE_DENSE_BASE + 0(a1)
  li t0, 0x01020304             /* token1: [4, 3, 2, 1] */
  sw t0, TILE_DENSE_BASE + 4(a1)
  li t0, 0x08070605             /* weight0: [5, 6, 7, 8] */
  sw t0, TILE_DENSE_BASE + 8(a1)
  li t0, 0x01010101             /* weight1: [1, 1, 1, 1] */
  sw t0, TILE_DENSE_BASE + 12(a1)
  li t0, 0x02020202             /* second dense block token0: [2, 2, 2, 2] */
  sw t0, TILE_DENSE_BASE + 16(a1)
  li t0, 0x03010301             /* second dense block token1: [1, 3, 1, 3] */
  sw t0, TILE_DENSE_BASE + 20(a1)
  li t0, 0x08070605
  sw t0, TILE_DENSE_BASE + 24(a1)
  li t0, 0x02020202
  sw t0, TILE_DENSE_BASE + 28(a1)
  li t0, 0x01010101
  sw t0, TILE_DENSE_BASE + 32(a1)
  li t0, 0x02020202
  sw t0, TILE_DENSE_BASE + 36(a1)
  li t0, 0x04030201
  sw t0, TILE_DENSE_BASE + 40(a1)
  li t0, 0x01010101
  sw t0, TILE_DENSE_BASE + 44(a1)
  li t0, 0x03030303
  sw t0, TILE_DENSE_BASE + 48(a1)
  li t0, 0x01010101
  sw t0, TILE_DENSE_BASE + 52(a1)
  li t0, 0x02020202
  sw t0, TILE_DENSE_BASE + 56(a1)
  li t0, 0x01010101
  sw t0, TILE_DENSE_BASE + 60(a1)
  li t0, 0x04030201
  sw t0, TILE_DENSE_BASE + 64(a1)
  li t0, 0x01020304
  sw t0, TILE_DENSE_BASE + 68(a1)
  li t0, 0x08070605
  sw t0, TILE_DENSE_BASE + 72(a1)
  li t0, 0x01010101
  sw t0, TILE_DENSE_BASE + 76(a1)
  li t0, 0x02020202
  sw t0, TILE_DENSE_BASE + 80(a1)
  li t0, 0x03010301
  sw t0, TILE_DENSE_BASE + 84(a1)
  li t0, 0x08070605
  sw t0, TILE_DENSE_BASE + 88(a1)
  li t0, 0x02020202
  sw t0, TILE_DENSE_BASE + 92(a1)
  li t0, 0x01010101
  sw t0, TILE_DENSE_BASE + 96(a1)
  li t0, 0x02020202
  sw t0, TILE_DENSE_BASE + 100(a1)
  li t0, 0x04030201
  sw t0, TILE_DENSE_BASE + 104(a1)
  li t0, 0x01010101
  sw t0, TILE_DENSE_BASE + 108(a1)
  li t0, 0x03030303
  sw t0, TILE_DENSE_BASE + 112(a1)
  li t0, 0x01010101
  sw t0, TILE_DENSE_BASE + 116(a1)
  li t0, 0x02020202
  sw t0, TILE_DENSE_BASE + 120(a1)
  li t0, 0x01010101
  sw t0, TILE_DENSE_BASE + 124(a1)

  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 0(a1)
  li t0, 0x22222222
  sw t0, TILE_INT4_BASE + 4(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 8(a1)
  li t0, 0x22222222
  sw t0, TILE_INT4_BASE + 12(a1)
  li t0, 0x33333333
  sw t0, TILE_INT4_BASE + 16(a1)
  li t0, 0x44444444
  sw t0, TILE_INT4_BASE + 20(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 24(a1)
  li t0, 0x22222222
  sw t0, TILE_INT4_BASE + 28(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 32(a1)
  li t0, 0x33333333
  sw t0, TILE_INT4_BASE + 36(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 40(a1)
  li t0, 0x22222222
  sw t0, TILE_INT4_BASE + 44(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 48(a1)
  li t0, 0x22222222
  sw t0, TILE_INT4_BASE + 52(a1)
  li t0, 0x44444444
  sw t0, TILE_INT4_BASE + 56(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 60(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 64(a1)
  li t0, 0x22222222
  sw t0, TILE_INT4_BASE + 68(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 72(a1)
  li t0, 0x22222222
  sw t0, TILE_INT4_BASE + 76(a1)
  li t0, 0x33333333
  sw t0, TILE_INT4_BASE + 80(a1)
  li t0, 0x44444444
  sw t0, TILE_INT4_BASE + 84(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 88(a1)
  li t0, 0x22222222
  sw t0, TILE_INT4_BASE + 92(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 96(a1)
  li t0, 0x33333333
  sw t0, TILE_INT4_BASE + 100(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 104(a1)
  li t0, 0x22222222
  sw t0, TILE_INT4_BASE + 108(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 112(a1)
  li t0, 0x22222222
  sw t0, TILE_INT4_BASE + 116(a1)
  li t0, 0x44444444
  sw t0, TILE_INT4_BASE + 120(a1)
  li t0, 0x11111111
  sw t0, TILE_INT4_BASE + 124(a1)

  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 0(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 4(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 8(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 12(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 16(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 20(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 24(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 28(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 32(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 36(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 40(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 44(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 48(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 52(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 56(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 60(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 64(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 68(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 72(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 76(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 80(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 84(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 88(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 92(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 96(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 100(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 104(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 108(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 112(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 116(a1)
  li t0, 0x55555555
  sw t0, TILE_INT2_BASE + 120(a1)
  li t0, 0x11111111
  sw t0, TILE_INT2_BASE + 124(a1)

  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 0(a1)
  li t0, 0x02020202
  sw t0, TILE_INT8_BASE + 4(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 8(a1)
  li t0, 0x02020202
  sw t0, TILE_INT8_BASE + 12(a1)
  li t0, 0x03030303
  sw t0, TILE_INT8_BASE + 16(a1)
  li t0, 0x04040404
  sw t0, TILE_INT8_BASE + 20(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 24(a1)
  li t0, 0x02020202
  sw t0, TILE_INT8_BASE + 28(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 32(a1)
  li t0, 0x03030303
  sw t0, TILE_INT8_BASE + 36(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 40(a1)
  li t0, 0x02020202
  sw t0, TILE_INT8_BASE + 44(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 48(a1)
  li t0, 0x02020202
  sw t0, TILE_INT8_BASE + 52(a1)
  li t0, 0x04040404
  sw t0, TILE_INT8_BASE + 56(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 60(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 64(a1)
  li t0, 0x02020202
  sw t0, TILE_INT8_BASE + 68(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 72(a1)
  li t0, 0x02020202
  sw t0, TILE_INT8_BASE + 76(a1)
  li t0, 0x03030303
  sw t0, TILE_INT8_BASE + 80(a1)
  li t0, 0x04040404
  sw t0, TILE_INT8_BASE + 84(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 88(a1)
  li t0, 0x02020202
  sw t0, TILE_INT8_BASE + 92(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 96(a1)
  li t0, 0x03030303
  sw t0, TILE_INT8_BASE + 100(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 104(a1)
  li t0, 0x02020202
  sw t0, TILE_INT8_BASE + 108(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 112(a1)
  li t0, 0x02020202
  sw t0, TILE_INT8_BASE + 116(a1)
  li t0, 0x04040404
  sw t0, TILE_INT8_BASE + 120(a1)
  li t0, 0x01010101
  sw t0, TILE_INT8_BASE + 124(a1)

  /* Two-token INT8 MLP projection: 4 input -> 4 hidden -> 2 output. */
  .include "tinyvit_mlp2_fixture.inc"

  /* TinyViT MLP/GEMM-like INT8 dense 4-block tile, repeated to expose kernel cost. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */
  li t5, 0
  li a0, TINYVIT_ITERS

1:
  addi a2, a1, TILE_DENSE_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6     /* token0 dot weight0 */
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6     /* token0 dot weight1 */
  add t5, t5, t3

  lw t0, 4(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6     /* token1 dot weight0 */
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6     /* token1 dot weight1 */
  add t5, t5, t3

  addi a2, a2, TILE_DENSE_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 12096
  bne t5, t4, fail_dense_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s4, t3
  li t4, 512
  bne s4, t4, fail_dense_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s5, t3
  bnez s5, fail_dense_skip

  read_csr 31, 0xb00             /* t6 = dense cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = dense instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  li s3, RESULT_MAGIC
  sw s3, 0(s2)
  sw t5, 4(s2)
  sw s4, 8(s2)
  sw s5, 12(s2)
  sw t6, 16(s2)
  sw t2, 20(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Larger INT8 dense kernel shape for the paper-table path. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */
  li t5, 0
  li a0, TINYVIT_LARGE_ITERS

1:
  addi a2, a1, TILE_DENSE_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t0, 4(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a2, a2, TILE_DENSE_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 48384
  bne t5, t4, fail_dense_x4_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s4, t3
  li t4, 2048
  bne s4, t4, fail_dense_x4_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s5, t3
  bnez s5, fail_dense_x4_skip

  read_csr 31, 0xb00             /* t6 = dense x4 cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = dense x4 instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 296(s2)
  sw s4, 300(s2)
  sw s5, 304(s2)
  sw t6, 308(s2)
  sw t2, 312(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Static low-bit INT4 dense tile. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 1
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT4 */

  li t0, 0xff
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP dense INT4 lanes */

  li t0, 8
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 8 */

  li t5, 0
  li a0, TINYVIT_ITERS
1:
  addi a2, a1, TILE_INT4_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t0, 4(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a2, a2, TILE_INT4_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 14592
  bne t5, t4, fail_static_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 512
  bne s6, t4, fail_static_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  bnez s7, fail_static_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0xff
  bne s8, t4, fail_static_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 8
  bne s9, t4, fail_static_lane

  read_csr 31, 0xb00             /* t6 = static low-bit cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = static low-bit instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 24(s2)
  sw s6, 28(s2)
  sw s7, 32(s2)
  sw s8, 36(s2)
  sw s9, 40(s2)
  sw t6, 44(s2)
  sw t2, 48(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Static INT2 dense tile. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 2
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT2 */

  li t0, 0xffff
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP dense INT2 lanes */

  li t0, 16
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 16 */

  li t5, 0
  li a0, TINYVIT_ITERS
1:
  addi a2, a1, TILE_INT2_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t0, 4(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a2, a2, TILE_INT2_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 5120
  bne t5, t4, fail_static_int2_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 512
  bne s6, t4, fail_static_int2_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  bnez s7, fail_static_int2_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0xffff
  bne s8, t4, fail_static_int2_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 16
  bne s9, t4, fail_static_int2_lane

  read_csr 31, 0xb00             /* t6 = static INT2 cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = static INT2 instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 164(s2)
  sw s6, 168(s2)
  sw s7, 172(s2)
  sw s8, 176(s2)
  sw s9, 180(s2)
  sw t6, 184(s2)
  sw t2, 188(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Adaptive low-bit sparse/lane policy tile, standing in for a pruned MLP tile. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 1
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT4 */

  li t0, 0x0f
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP lanes 0..3 */

  li t0, 4
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 4 */

  li t5, 0
  li a0, TINYVIT_ITERS
1:
  addi a2, a1, TILE_INT4_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t0, 4(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a2, a2, TILE_INT4_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 7296
  bne t5, t4, fail_policy_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 512
  bne s6, t4, fail_policy_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  li t4, 2048
  bne s7, t4, fail_policy_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0x0f
  bne s8, t4, fail_policy_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 4
  bne s9, t4, fail_policy_lane

  read_csr 31, 0xb00             /* t6 = policy cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = policy instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 52(s2)
  sw s6, 56(s2)
  sw s7, 60(s2)
  sw s8, 64(s2)
  sw s9, 68(s2)
  sw t6, 72(s2)
  sw t2, 76(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Adaptive INT4 structured sparse point with 25% active lanes. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 1
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT4 */

  li t0, 0x03
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP lanes 0..1 */

  li t0, 2
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 2 */

  li t5, 0
  li a0, TINYVIT_ITERS
1:
  addi a2, a1, TILE_INT4_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t0, 4(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a2, a2, TILE_INT4_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 3648
  bne t5, t4, fail_policy_sparse75_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 512
  bne s6, t4, fail_policy_sparse75_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  li t4, 3072
  bne s7, t4, fail_policy_sparse75_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0x03
  bne s8, t4, fail_policy_sparse75_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 2
  bne s9, t4, fail_policy_sparse75_lane

  read_csr 31, 0xb00             /* t6 = sparse75 cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = sparse75 instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 268(s2)
  sw s6, 272(s2)
  sw s7, 276(s2)
  sw s8, 280(s2)
  sw s9, 284(s2)
  sw t6, 288(s2)
  sw t2, 292(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Adaptive sparse policy with a non-contiguous bitmap. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 1
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT4 */

  li t0, 0x55
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP lanes 0,2,4,6 */

  li t0, 8
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 8 */

  li t5, 0
  li a0, TINYVIT_ITERS
1:
  addi a2, a1, TILE_INT4_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t0, 4(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a2, a2, TILE_INT4_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 7296
  bne t5, t4, fail_policy_unstructured_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 512
  bne s6, t4, fail_policy_unstructured_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  li t4, 2048
  bne s7, t4, fail_policy_unstructured_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0x55
  bne s8, t4, fail_policy_unstructured_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 8
  bne s9, t4, fail_policy_unstructured_lane

  read_csr 31, 0xb00             /* t6 = unstructured policy cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = unstructured policy instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 192(s2)
  sw s6, 196(s2)
  sw s7, 200(s2)
  sw s8, 204(s2)
  sw s9, 208(s2)
  sw t6, 212(s2)
  sw t2, 216(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Ablation: no sparse skip, with lane gating still enabled. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 1
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT4 */

  li t0, 0xff
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP dense INT4 lanes */

  li t0, 4
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 4 */

  li t5, 0
  li a0, TINYVIT_ITERS
1:
  addi a2, a1, TILE_INT4_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t0, 4(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a2, a2, TILE_INT4_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 7296
  bne t5, t4, fail_no_sparse_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 512
  bne s6, t4, fail_no_sparse_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  li t4, 2048
  bne s7, t4, fail_no_sparse_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0xff
  bne s8, t4, fail_no_sparse_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 4
  bne s9, t4, fail_no_sparse_lane

  read_csr 31, 0xb00             /* t6 = no-sparse cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = no-sparse instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 80(s2)
  sw s6, 84(s2)
  sw s7, 88(s2)
  sw s8, 92(s2)
  sw s9, 96(s2)
  sw t6, 100(s2)
  sw t2, 104(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Ablation: no lane gating, with sparse bitmap still enabled. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 1
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT4 */

  li t0, 0x0f
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP lanes 0..3 */

  li t0, 8
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 8 */

  li t5, 0
  li a0, TINYVIT_ITERS
1:
  addi a2, a1, TILE_INT4_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t0, 4(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a2, a2, TILE_INT4_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 7296
  bne t5, t4, fail_no_lane_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 512
  bne s6, t4, fail_no_lane_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  li t4, 2048
  bne s7, t4, fail_no_lane_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0x0f
  bne s8, t4, fail_no_lane_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 8
  bne s9, t4, fail_no_lane_lane

  read_csr 31, 0xb00             /* t6 = no-lane cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = no-lane instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 108(s2)
  sw s6, 112(s2)
  sw s7, 116(s2)
  sw s8, 120(s2)
  sw s9, 124(s2)
  sw t6, 128(s2)
  sw t2, 132(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Ablation: no precision gating, using an INT8-packed equivalent tile. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 0
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT8 */

  li t0, 0x0f
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP INT8 lanes 0..3 */

  li t0, 4
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 4 */

  li t5, 0
  li a0, TINYVIT_ITERS
1:
  addi a2, a1, TILE_INT8_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t0, 4(a2)
  lw t1, 8(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t1, 12(a2)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a2, a2, TILE_INT8_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 7296
  bne t5, t4, fail_no_precision_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 512
  bne s6, t4, fail_no_precision_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  bnez s7, fail_no_precision_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0x0f
  bne s8, t4, fail_no_precision_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 4
  bne s9, t4, fail_no_precision_lane

  read_csr 31, 0xb00             /* t6 = no-precision cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = no-precision instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 136(s2)
  sw s6, 140(s2)
  sw s7, 144(s2)
  sw s8, 148(s2)
  sw s9, 152(s2)
  sw t6, 156(s2)
  sw t2, 160(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Dense INT8 macro-tile with block-local operand and weight reuse. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */
  li t5, 0
  li a0, TINYVIT_ITERS

1:
  addi a2, a1, TILE_DENSE_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)                   /* token0 */
  lw t2, 4(a2)                   /* token1 */
  lw t1, 8(a2)                   /* weight0 */
  lw t4, 12(a2)                  /* weight1 */

  sap_r 0x10, 0x0, 28, 5, 6     /* token0 dot weight0 */
  add t5, t5, t3

  sap_r 0x10, 0x0, 28, 5, 29    /* token0 dot weight1 */
  add t5, t5, t3

  sap_r 0x10, 0x0, 28, 7, 6     /* token1 dot weight0 */
  add t5, t5, t3

  sap_r 0x10, 0x0, 28, 7, 29    /* token1 dot weight1 */
  add t5, t5, t3

  addi a2, a2, TILE_DENSE_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 12096
  bne t5, t4, fail_dense_reuse_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s4, t3
  li t4, 512
  bne s4, t4, fail_dense_reuse_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s5, t3
  bnez s5, fail_dense_reuse_skip

  read_csr 31, 0xb00             /* t6 = dense reuse cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = dense reuse instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 220(s2)
  sw s4, 224(s2)
  sw s5, 228(s2)
  sw t6, 232(s2)
  sw t2, 236(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Adaptive INT4 sparse/lane policy with block-local operand and weight reuse. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 1
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT4 */

  li t0, 0x0f
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP lanes 0..3 */

  li t0, 4
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 4 */

  li t5, 0
  li a0, TINYVIT_ITERS
1:
  addi a2, a1, TILE_INT4_BASE
  li a3, TINYVIT_BLOCKS
2:
  lw t0, 0(a2)                   /* token0 */
  lw t2, 4(a2)                   /* token1 */
  lw t1, 8(a2)                   /* weight0 */
  lw t4, 12(a2)                  /* weight1 */

  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  sap_r 0x10, 0x0, 28, 5, 29
  add t5, t5, t3

  sap_r 0x10, 0x0, 28, 7, 6
  add t5, t5, t3

  sap_r 0x10, 0x0, 28, 7, 29
  add t5, t5, t3

  addi a2, a2, TILE_INT4_STRIDE
  addi a3, a3, -1
  bnez a3, 2b

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 7296
  bne t5, t4, fail_policy_reuse_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 512
  bne s6, t4, fail_policy_reuse_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  li t4, 2048
  bne s7, t4, fail_policy_reuse_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0x0f
  bne s8, t4, fail_policy_reuse_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 4
  bne s9, t4, fail_policy_reuse_lane

  read_csr 31, 0xb00             /* t6 = adaptive reuse cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = adaptive reuse instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 240(s2)
  sw s6, 244(s2)
  sw s7, 248(s2)
  sw s8, 252(s2)
  sw s9, 256(s2)
  sw t6, 260(s2)
  sw t2, 264(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Structured 75% sparse schedule: issue only the live INT4 vector chunks. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 1
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT4 */

  li t0, 0xff
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP dense live chunks */

  li t0, 8
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 8 */

  li t5, 0
  li a0, 128                     /* One live vector per four logical vectors. */
1:
  lw t0, TILE_INT4_BASE + 0(a1)
  lw t1, TILE_INT4_BASE + 8(a1)
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 1024
  bne t5, t4, fail_policy_sparse75_schedule_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 128
  bne s6, t4, fail_policy_sparse75_schedule_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  bnez s7, fail_policy_sparse75_schedule_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0xff
  bne s8, t4, fail_policy_sparse75_schedule_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 8
  bne s9, t4, fail_policy_sparse75_schedule_lane

  read_csr 31, 0xb00             /* t6 = scheduled sparse cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = scheduled sparse instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 320(s2)
  sw s6, 324(s2)
  sw s7, 328(s2)
  sw s8, 332(s2)
  sw s9, 336(s2)
  sw t6, 340(s2)
  sw t2, 344(s2)

  sap_r 0x1d, 0x0, 0, 0, 0      /* VCLEARCNT x0, x0, x0 */

  /* Two-stage MLP projection with ReLU and register-packed hidden activations. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */

  li t0, 0
  sap_r 0x18, 0x0, 0, 5, 0      /* VSETPREC INT8 */

  li t0, 0x0f
  sap_r 0x1c, 0x0, 0, 5, 0      /* VSETSPARSE_BMP dense INT8 lanes */

  li t0, 4
  sap_r 0x1b, 0x0, 0, 5, 0      /* VSETLANE 4 */

  li t5, 0
  li a0, TINYVIT_ITERS
1:
  addi a2, a1, TILE_MLP2_BASE

  lw s3, 8(a2)                   /* hidden weight0 */
  lw s4, 12(a2)                  /* hidden weight1 */
  lw s5, 16(a2)                  /* hidden weight2 */
  lw s10, 20(a2)                 /* hidden weight3 */
  lw s11, 24(a2)                 /* output weight0 */
  lw a7, 28(a2)                  /* output weight1 */

  lw t0, 0(a2)                   /* token0 */
  mv t1, s3
  sap_r 0x10, 0x0, 28, 5, 6
  mv a3, t3
  mv t1, s4
  sap_r 0x10, 0x0, 28, 5, 6
  mv a4, t3
  mv t1, s5
  sap_r 0x10, 0x0, 28, 5, 6
  mv a5, t3
  mv t1, s10
  sap_r 0x10, 0x0, 28, 5, 6
  mv a6, t3
  requant_relu a3
  requant_relu a4
  requant_relu a5
  requant_relu a6
  slli a4, a4, 8
  slli a5, a5, 16
  slli a6, a6, 24
  or t0, a3, a4
  or t0, t0, a5
  or t0, t0, a6
  mv t1, s11
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3
  mv t1, a7
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  lw t0, 4(a2)                   /* token1 */
  mv t1, s3
  sap_r 0x10, 0x0, 28, 5, 6
  mv a3, t3
  mv t1, s4
  sap_r 0x10, 0x0, 28, 5, 6
  mv a4, t3
  mv t1, s5
  sap_r 0x10, 0x0, 28, 5, 6
  mv a5, t3
  mv t1, s10
  sap_r 0x10, 0x0, 28, 5, 6
  mv a6, t3
  requant_relu a3
  requant_relu a4
  requant_relu a5
  requant_relu a6
  slli a4, a4, 8
  slli a5, a5, 16
  slli a6, a6, 24
  or t0, a3, a4
  or t0, t0, a5
  or t0, t0, a6
  mv t1, s11
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3
  mv t1, a7
  sap_r 0x10, 0x0, 28, 5, 6
  add t5, t5, t3

  addi a0, a0, -1
  bnez a0, 1b

  li t4, TINYVIT_MLP2_EXPECTED_OUTPUT
  bne t5, t4, fail_mlp2_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 192
  bne s6, t4, fail_mlp2_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  bnez s7, fail_mlp2_skip

  li t0, 4
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SPARSE */
  mv s8, t3
  li t4, 0x0f
  bne s8, t4, fail_mlp2_sparse

  li t0, 5
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT LANE */
  mv s9, t3
  li t4, 4
  bne s9, t4, fail_mlp2_lane

  read_csr 31, 0xb00             /* t6 = MLP2 cycle delta */
  sub t6, t6, s0
  read_csr 7, 0xb02              /* t2 = MLP2 instret delta */
  sub t2, t2, s1
  li s2, RESULT_BASE
  sw t5, 348(s2)
  sw s6, 352(s2)
  sw s7, 356(s2)
  sw t6, 360(s2)
  sw t2, 364(s2)

  exit_with 1

fail_dense_output:
  exit_with 11

fail_dense_mac:
  exit_with 12

fail_dense_skip:
  exit_with 13

fail_dense_x4_output:
  exit_with 17

fail_dense_x4_mac:
  exit_with 18

fail_dense_x4_skip:
  exit_with 19

fail_dense_reuse_output:
  exit_with 14

fail_dense_reuse_mac:
  exit_with 15

fail_dense_reuse_skip:
  exit_with 16

fail_static_output:
  exit_with 21

fail_static_mac:
  exit_with 22

fail_static_skip:
  exit_with 23

fail_static_sparse:
  exit_with 24

fail_static_lane:
  exit_with 25

fail_static_int2_output:
  exit_with 71

fail_static_int2_mac:
  exit_with 72

fail_static_int2_skip:
  exit_with 73

fail_static_int2_sparse:
  exit_with 74

fail_static_int2_lane:
  exit_with 75

fail_policy_output:
  exit_with 31

fail_policy_mac:
  exit_with 32

fail_policy_skip:
  exit_with 33

fail_policy_sparse:
  exit_with 34

fail_policy_lane:
  exit_with 35

fail_policy_sparse75_output:
  exit_with 86

fail_policy_sparse75_mac:
  exit_with 87

fail_policy_sparse75_skip:
  exit_with 88

fail_policy_sparse75_sparse:
  exit_with 89

fail_policy_sparse75_lane:
  exit_with 90

fail_policy_sparse75_schedule_output:
  exit_with 91

fail_policy_sparse75_schedule_mac:
  exit_with 92

fail_policy_sparse75_schedule_skip:
  exit_with 93

fail_policy_sparse75_schedule_sparse:
  exit_with 94

fail_policy_sparse75_schedule_lane:
  exit_with 95

fail_mlp2_output:
  exit_with 96

fail_mlp2_mac:
  exit_with 97

fail_mlp2_skip:
  exit_with 98

fail_mlp2_sparse:
  exit_with 99

fail_mlp2_lane:
  exit_with 100

fail_policy_reuse_output:
  exit_with 36

fail_policy_reuse_mac:
  exit_with 37

fail_policy_reuse_skip:
  exit_with 38

fail_policy_reuse_sparse:
  exit_with 39

fail_policy_reuse_lane:
  exit_with 40

fail_policy_unstructured_output:
  exit_with 81

fail_policy_unstructured_mac:
  exit_with 82

fail_policy_unstructured_skip:
  exit_with 83

fail_policy_unstructured_sparse:
  exit_with 84

fail_policy_unstructured_lane:
  exit_with 85

fail_no_sparse_output:
  exit_with 41

fail_no_sparse_mac:
  exit_with 42

fail_no_sparse_skip:
  exit_with 43

fail_no_sparse_sparse:
  exit_with 44

fail_no_sparse_lane:
  exit_with 45

fail_no_lane_output:
  exit_with 51

fail_no_lane_mac:
  exit_with 52

fail_no_lane_skip:
  exit_with 53

fail_no_lane_sparse:
  exit_with 54

fail_no_lane_lane:
  exit_with 55

fail_no_precision_output:
  exit_with 61

fail_no_precision_mac:
  exit_with 62

fail_no_precision_skip:
  exit_with 63

fail_no_precision_sparse:
  exit_with 64

fail_no_precision_lane:
  exit_with 65
