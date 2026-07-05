  .section .text.start, "ax"
  .globl _start

  .equ EXIT_ADDR, 0x10000004
  .equ RESULT_BASE, 0x00010000
  .equ RESULT_MAGIC, 0x54564954
  .equ TINYVIT_ITERS, 16

  .macro sap_r funct7, funct3, rd, rs1, rs2
    .word ((\funct7 << 25) | (\rs2 << 20) | (\rs1 << 15) | (\funct3 << 12) | (\rd << 7) | 0x0b)
  .endm

  .macro read_csr rd, csr
    .word ((\csr << 20) | (0 << 15) | (0x2 << 12) | (\rd << 7) | 0x73)
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

  /* TinyViT MLP/GEMM-like INT8 dense 2x2 tile, repeated to expose kernel cost. */
  read_csr 8, 0xb00              /* s0 = mcycle */
  read_csr 9, 0xb02              /* s1 = minstret */
  li t5, 0
  li a0, TINYVIT_ITERS

1:
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

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 2400
  bne t5, t4, fail_dense_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s4, t3
  li t4, 64
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
  li t0, 0x11111111
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* 8 active INT4 products => 8 */
  add t5, t5, t3

  li t0, 0x22222222
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* 8 active INT4 products => 16 */
  add t5, t5, t3

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 384
  bne t5, t4, fail_static_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 32
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
  li t0, 0x55555555
  li t1, 0x55555555
  sap_r 0x10, 0x0, 28, 5, 6     /* 16 active INT2 products => 16 */
  add t5, t5, t3

  li t0, 0x11111111
  li t1, 0x55555555
  sap_r 0x10, 0x0, 28, 5, 6     /* 8 active INT2 products => 8 */
  add t5, t5, t3

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 384
  bne t5, t4, fail_static_int2_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 32
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
  li t0, 0x11111111
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* 4 active INT4 products => 4 */
  add t5, t5, t3

  li t0, 0x22222222
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* 4 active INT4 products => 8 */
  add t5, t5, t3

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 192
  bne t5, t4, fail_policy_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 32
  bne s6, t4, fail_policy_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  li t4, 128
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
  li t0, 0x11111111
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* 4 active INT4 products => 4 */
  add t5, t5, t3

  li t0, 0x22222222
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* 4 active INT4 products => 8 */
  add t5, t5, t3

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 192
  bne t5, t4, fail_no_sparse_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 32
  bne s6, t4, fail_no_sparse_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  li t4, 128
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
  li t0, 0x11111111
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* 4 active INT4 products => 4 */
  add t5, t5, t3

  li t0, 0x22222222
  li t1, 0x11111111
  sap_r 0x10, 0x0, 28, 5, 6     /* 4 active INT4 products => 8 */
  add t5, t5, t3

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 192
  bne t5, t4, fail_no_lane_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 32
  bne s6, t4, fail_no_lane_mac

  li t0, 3
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT SKIPPED */
  mv s7, t3
  li t4, 128
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
  li t0, 0x01010101
  li t1, 0x01010101
  sap_r 0x10, 0x0, 28, 5, 6     /* 4 active INT8 products => 4 */
  add t5, t5, t3

  li t0, 0x02020202
  li t1, 0x01010101
  sap_r 0x10, 0x0, 28, 5, 6     /* 4 active INT8 products => 8 */
  add t5, t5, t3

  addi a0, a0, -1
  bnez a0, 1b

  li t4, 192
  bne t5, t4, fail_no_precision_output

  li t0, 2
  sap_r 0x1a, 0x0, 28, 5, 0     /* VREADCNT MAC_ACTIVE */
  mv s6, t3
  li t4, 32
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

  exit_with 1

fail_dense_output:
  exit_with 11

fail_dense_mac:
  exit_with 12

fail_dense_skip:
  exit_with 13

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
