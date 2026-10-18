ENTRY(_start)
MEMORY
{
  INSTR (rx) : ORIGIN = 0x80000000, LENGTH = 16K
  DATA (rw)  : ORIGIN = 0x80100000, LENGTH = 256K
}
__stack_top = ORIGIN(DATA) + LENGTH(DATA);
__stack_bottom = __stack_top - 8K;
SECTIONS
{
  .text : {
    KEEP(*(.text.startup))
    *(.text .text.*)
    KEEP(*(.trap))
    . = ALIGN(4);
  } > INSTR
  .rodata : {
    . = ALIGN(4);
    *(.srodata .srodata.* .rodata .rodata.*)
    . = ALIGN(4);
  } > DATA
  .data : {
    . = ALIGN(8);
    *(.sdata .sdata.* .data .data.*)
    . = ALIGN(4);
  } > DATA
  .bss (NOLOAD) : {
    . = ALIGN(4);
    __bss_start = .;
    *(.sbss .sbss.* .bss .bss.* COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > DATA
  ASSERT(__bss_end <= __stack_bottom, "DATA overlaps reserved 8 KiB stack")
  /DISCARD/ : { *(.comment .note* .eh_frame* .init_array* .fini_array*) }
}
