#ifndef BOARD_RUNTIME_H
#define BOARD_RUNTIME_H
#include <stdint.h>
#include <stdarg.h>
#include "my_cpu_mmio.h"
#ifndef BOARD_CPU_HZ
#define BOARD_CPU_HZ 50000000u
#endif
#ifndef BOARD_BUILD_ID
#define BOARD_BUILD_ID "local"
#endif
#define BOARD_UART_BAUD 115200u
#define BOARD_UART_DIV (((BOARD_CPU_HZ + BOARD_UART_BAUD / 2u) / BOARD_UART_BAUD) - 1u)
extern volatile uint32_t board_uart_fault;
extern volatile uint32_t board_trap_mcause[3];
static inline uint32_t board_cycle(void) {
    uint32_t value;
    __asm__ volatile ("csrr %0, cycle" : "=r"(value));
    return value;
}
void board_uart_init(void);
int board_uart_putc(char ch);
int board_vprintf(const char *format, va_list arguments);
int board_printf(const char *format, ...);
void board_print_u64(uint64_t value);
void board_print_fixed6(uint64_t value_scaled);
void board_halt(uint32_t code) __attribute__((noreturn));
#endif
