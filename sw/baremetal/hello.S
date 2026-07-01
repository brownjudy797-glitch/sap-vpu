  .section .text.start, "ax"
  .globl _start

  .equ UART_ADDR, 0x10000000
  .equ EXIT_ADDR, 0x10000004

_start:
  la sp, _stack_top
  la t0, message
  li t1, UART_ADDR

1:
  lbu t2, 0(t0)
  beqz t2, 2f
  sw t2, 0(t1)
  addi t0, t0, 1
  j 1b

2:
  li t1, EXIT_ADDR
  li t2, 1
  sw t2, 0(t1)

3:
  wfi
  j 3b

  .section .rodata
message:
  .asciz "SAP-VPU hello\n"
