    .section .text.startup
    .globl _start
    .type _start, @function

_start:
    .option push
    .option norelax
    la sp, __stack_top
    .option pop

    la t0, __bss_start
    la t1, __bss_end

clear_bss:
    bgeu t0, t1, bss_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j clear_bss

bss_done:
    call main

halt:
    wfi
    j halt

    .size _start, . - _start
