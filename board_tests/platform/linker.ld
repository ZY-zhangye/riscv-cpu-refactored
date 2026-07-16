ENTRY(_start)

/*
 * Default memory map for the IC contest "Jingyeda" project template.
 *
 * INSTR is the instruction memory loaded from inst.hex/inst.coe.
 * DATA  is the data memory loaded from data.hex/data.coe.
 *
 * These values follow the supplemental requirement PDF:
 *   IROM: 0x80000000 .. 0x80003fff, 16 KiB, read-only
 *   DRAM: 0x80100000 .. 0x8013ffff, 256 KiB, read/write
 */
MEMORY
{
  INSTR (rx)  : ORIGIN = 0x80000000, LENGTH = 16K
  DATA  (rwx) : ORIGIN = 0x80100000, LENGTH = 256K
}

PROVIDE(__stack_top = ORIGIN(DATA) + LENGTH(DATA));

SECTIONS
{
  .text :
  {
    . = ALIGN(4);
    KEEP(*(.text.startup))
    *(.text)
    *(.text.*)
    . = ALIGN(4);
  } > INSTR

  .trap :
  {
    . = ALIGN(4);
    KEEP(*(.trap))
    . = ALIGN(4);
  } > INSTR

  .rodata :
  {
    . = ALIGN(4);
    *(.srodata)
    *(.srodata.*)
    *(.rodata)
    *(.rodata.*)
    . = ALIGN(4);
  } > DATA

  .data :
  {
    . = ALIGN(4);
    *(.sdata)
    *(.sdata.*)
    *(.data)
    *(.data.*)
    . = ALIGN(4);
  } > DATA

  .bss (NOLOAD) :
  {
    . = ALIGN(4);
    __bss_start = .;
    *(.sbss)
    *(.sbss.*)
    *(.bss)
    *(.bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > DATA

  /DISCARD/ :
  {
    *(.comment)
    *(.riscv.attributes)
    *(.note*)
    *(.eh_frame*)
  }
}
