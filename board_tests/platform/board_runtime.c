#include "board_runtime.h"
#include <stdio.h>

volatile uint32_t board_uart_fault;
volatile uint32_t board_trap_mcause[3];

void board_uart_init(void) {
    mmio_write32(UART_CTRL, UART_CTRL_UART_RST);
    mmio_write32(UART_BAUD, BOARD_UART_DIV);
    mmio_write32(UART_CTRL, UART_CTRL_UART_EN | UART_CTRL_BOUNDARY_ON);
}

int board_uart_putc(char ch) {
    if (board_uart_fault) return -1;
    /* CR can consume the last FIFO slot. Poll again for LF independently. */
    if (ch == '\n' && board_uart_putc('\r') < 0) return -1;
    uint32_t start = board_cycle();
    while (mmio_read32(UART_STATUS) & UART_STATUS_TX_FULL) {
        if ((uint32_t)(board_cycle() - start) > BOARD_CPU_HZ / 10u) {
            board_uart_fault = 1;
            mmio_write32(LED_VALUE, 0xE0000001u);
            return -1;
        }
    }
    mmio_write32(UART_DATA, (uint32_t)(uint8_t)ch);
    return 0;
}

static void print_unsigned(uint64_t value, unsigned base, unsigned width) {
    char buffer[21];
    unsigned count = 0;
    do {
        unsigned digit = (unsigned)(value % base);
        buffer[count++] = (char)(digit < 10 ? '0' + digit : 'a' + digit - 10);
        value /= base;
    } while (value);
    while (width > count) { board_uart_putc('0'); --width; }
    while (count) board_uart_putc(buffer[--count]);
}

void board_print_u64(uint64_t value) { print_unsigned(value, 10, 0); }
void board_print_fixed6(uint64_t value_scaled) {
    print_unsigned(value_scaled / 1000000u, 10, 0);
    board_uart_putc('.');
    print_unsigned(value_scaled % 1000000u, 10, 6);
}

/* Small freestanding printf: strings, characters, signed/unsigned integers,
 * hex, optional l/ll and zero padding. No libc, allocation, or float support. */
int board_vprintf(const char *format, va_list arguments) {
    while (*format) {
        if (*format++ != '%') { board_uart_putc(format[-1]); continue; }
        if (*format == '%') { board_uart_putc(*format++); continue; }
        unsigned width = 0, longs = 0;
        while (*format >= '0' && *format <= '9') width = width * 10u + (unsigned)(*format++ - '0');
        while (*format == 'l') { ++longs; ++format; }
        char spec = *format++;
        if (spec == 's') {
            const char *text = va_arg(arguments, const char *);
            while (*text) board_uart_putc(*text++);
        } else if (spec == 'c') {
            board_uart_putc((char)va_arg(arguments, int));
        } else if (spec == 'u' || spec == 'x' || spec == 'd') {
            uint64_t value;
            if (spec == 'd') {
                int64_t signed_value = longs > 1 ? va_arg(arguments, long long) :
                    longs ? va_arg(arguments, long) : va_arg(arguments, int);
                if (signed_value < 0) {
                    board_uart_putc('-');
                    value = 0u - (uint64_t)signed_value;
                } else value = (uint64_t)signed_value;
            } else value = longs > 1 ? va_arg(arguments, unsigned long long) :
                longs ? va_arg(arguments, unsigned long) : va_arg(arguments, unsigned int);
            print_unsigned(value, spec == 'x' ? 16u : 10u, width);
        } else {
            board_uart_putc('?');
        }
    }
    return board_uart_fault ? -1 : 0;
}

int board_printf(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int result = board_vprintf(format, arguments);
    va_end(arguments);
    return result;
}

int printf(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int result = board_vprintf(format, arguments);
    va_end(arguments);
    return result;
}

void board_halt(uint32_t code) {
    mmio_write32(LED_VALUE, code);
    for (;;) __asm__ volatile ("nop");
}
