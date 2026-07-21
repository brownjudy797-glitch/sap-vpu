OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = DEFINED(__rom_length) ? __rom_length : 4K
  RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 4K
}

SECTIONS
{
  .text : {
    KEEP(*(.text.start))
    *(.text*)
    *(.rodata*)
  } > ROM

  .data : {
    *(.data*)
  } > RAM AT > ROM

  .bss (NOLOAD) : {
    *(.bss*)
    *(COMMON)
  } > RAM

  . = ORIGIN(RAM) + LENGTH(RAM);
  _stack_top = .;
}
