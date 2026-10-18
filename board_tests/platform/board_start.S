    .section .text.startup
    .globl _start
    .type _start, @function
_start:
    csrw mstatus, zero
    csrw mie, zero
    .option push
    .option norelax
    la sp, __stack_top
    la t0, board_trap
    .option pop
    csrw mtvec, t0
    la t0, __bss_start
    la t1, __bss_end
1:
    bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:
    call main
3:
    j 3b
    .size _start, . - _start

    .section .text.trap
    .balign 4
    .globl board_trap
board_trap:
    csrr t1, mcause
    la t0, board_trap_mcause
    sw t1, 0(t0)
    csrr t1, mepc
    sw t1, 4(t0)
    csrr t1, mtval
    sw t1, 8(t0)
    li t0, 0x80030000
    li t1, 0xE0000003
    sw t1, 0(t0)
4:
    j 4b
