#include "board_runtime.h"
#include <stdio.h>

static volatile uint32_t initialized_word = 0x13579BDFu;
static volatile uint32_t zero_word;
static volatile uint32_t scratch[4];
static const char rodata_marker[] = "HELLOZYNQ";

static void require(int condition, unsigned code) {
    if (!condition) {
        printf("SMOKE_FAIL code=%u\n", code);
        board_halt(0xE0000000u | code);
    }
}

static __attribute__((noinline)) uint32_t stack_call(uint32_t value, unsigned depth) {
    volatile uint32_t saved = value ^ 0xA55A1234u;
    uint32_t result = depth ? stack_call(value + 1u, depth - 1u) : value;
    require(saved == (value ^ 0xA55A1234u), 4);
    return result;
}

int main(void) {
    mmio_write32(LED_VALUE, 1u);
    board_uart_init();
    printf("[SMOKE] BOOT build=%s cpu_hz=%u uart_div=%u\n",
           BOARD_BUILD_ID, BOARD_CPU_HZ, BOARD_UART_DIV);
    require(initialized_word == 0x13579BDFu && zero_word == 0, 2);
    const volatile char *marker = rodata_marker;
    require(marker[0] == 'H' && marker[8] == 'Q', 3);
    require(stack_call(123u, 5u) == 128u, 4);

    scratch[0] = 0x11223344u;
    ((volatile uint8_t *)scratch)[1] = 0xAAu;
    require(scratch[0] == 0x1122AA44u, 5);
    ((volatile uint16_t *)scratch)[1] = 0xBEEFu;
    require(scratch[0] == 0xBEEFAA44u, 6);
    for (unsigned i = 0; i < 4; ++i) scratch[i] = 0xA5A50000u + i;
    for (unsigned i = 0; i < 4; ++i) require(scratch[i] == 0xA5A50000u + i, 7);

    uint32_t product, quotient, remainder;
    __asm__ volatile ("mul %0, %1, %2" : "=r"(product) : "r"(123456u), "r"(37u));
    __asm__ volatile ("div %0, %1, %2" : "=r"(quotient) : "r"(-12345), "r"(37));
    __asm__ volatile ("rem %0, %1, %2" : "=r"(remainder) : "r"(-12345), "r"(37));
    require(product == 4567872u && (int32_t)quotient == -333 && (int32_t)remainder == -24, 8);
    require(mmio_read32(UART_BAUD) == BOARD_UART_DIV &&
            (mmio_read32(UART_CTRL) & 0x1Fu) == 0x14u, 9);
    mmio_write32(TIMER_CTRL, 0u);
    mmio_write32(TIMER_LOAD, 100000u);
    mmio_write32(TIMER_CTRL, TIMER_CTRL_ENABLE);
    uint32_t first = mmio_read32(TIMER_VALUE);
    uint32_t start = board_cycle();
    while ((uint32_t)(board_cycle() - start) < 200u) {}
    uint32_t second = mmio_read32(TIMER_VALUE);
    require(second < first && second > 0, 10);
    mmio_write32(TIMER_CTRL, 0u);
    mmio_write32(LED_VALUE, 3u);
    require(mmio_read32(LED_VALUE) == 3u, 11);
    require(!board_uart_fault, 12);
    printf("SMOKE_PASS cpu_hz=%u data=1 bss=1 rodata=1 stack=1 ram=1 M=1 timer=1 mmio=1 echo=ready\n", BOARD_CPU_HZ);
    for (;;) {
        if (mmio_read32(UART_STATUS) & UART_STATUS_RX_READY) {
            char value = (char)mmio_read32(UART_DATA);
            board_uart_putc(value);
        }
        if (board_uart_fault) board_halt(0xE0000001u);
    }
}
