ENTRY(_start)

/*
 * ========================= 可修改参数区（链接脚本） =========================
 * 按你的仿真平台内存映射修改 ORIGIN/LENGTH：
 * - INSTR: 指令存储器（通常接 irom/inst mem）
 * - DATA : 数据存储器（通常接 dram/data mem）
 */
MEMORY
{
  INSTR (rx) : ORIGIN = 0x00000000, LENGTH = 0x800
  DATA  (rw) : ORIGIN = 0x60000000, LENGTH = 0x800
}

SECTIONS
{
  /* .text 放到指令区，启动入口和主程序都在这里 */
  .text :
  {
    KEEP(*(.text.startup))
    *(.text)
    *(.text.*)
  } > INSTR

  /* 常量字符串/查表放 DATA，便于与你现有仿真加载流程一致 */
  .rodata :
  {
    *(.rodata)
    *(.rodata.*)
  } > DATA

  /* 已初始化全局/静态变量 */
  .data :
  {
    *(.data)
    *(.data.*)
  } > DATA

  /* 未初始化全局/静态变量；NOLOAD 表示镜像文件不需要初值填充 */
  .bss (NOLOAD) :
  {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss)
    *(.bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > DATA

  /*
   * 软件栈区：
   * - 当前预留 0x100 字节
   * - 若后续函数更深/局部变量更多，可适当增大
   */
  .stack (NOLOAD) :
  {
    . = ALIGN(16);
    . = . + 0x100;
    __stack_top = .;
  } > DATA
}
