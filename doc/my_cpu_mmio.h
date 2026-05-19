#ifndef MY_CPU_MMIO_H
#define MY_CPU_MMIO_H

#include <stdint.h>

static inline void mmio_write32(uint32_t addr, uint32_t value) {
    *(volatile uint32_t *)addr = value;
}

static inline uint32_t mmio_read32(uint32_t addr) {
    return *(volatile uint32_t *)addr;
}

#define CPU_PC_START_NORMAL        0x80000000u
#define CPU_PC_START_PERF_BENCH    0x00000000u

#define DRAM_BASE_ADDR             0x80100000u
#define DRAM_END_ADDR              0x8013FFFFu
#define BENCH_DATA_BASE_ADDR       0x60000000u

#define UART_BASE_ADDR             0x80010000u
#define UART_DATA                  (UART_BASE_ADDR + 0x00u)
#define UART_STATUS                (UART_BASE_ADDR + 0x04u)
#define UART_CTRL                  (UART_BASE_ADDR + 0x08u)
#define UART_BAUD                  (UART_BASE_ADDR + 0x0Cu)

#define UART_STATUS_TX_EMPTY       (1u << 0)
#define UART_STATUS_RX_READY       (1u << 1)
#define UART_STATUS_TX_FULL        (1u << 2)
#define UART_STATUS_RX_FULL        (1u << 3)
#define UART_STATUS_PARITY_ERROR   (1u << 4)
#define UART_STATUS_OVERFLOW_ERROR (1u << 5)
#define UART_STATUS_TX_INT         (1u << 6)
#define UART_STATUS_RX_INT         (1u << 7)

#define UART_CTRL_RX_INT_EN        (1u << 0)
#define UART_CTRL_TX_INT_EN        (1u << 1)
#define UART_CTRL_UART_EN          (1u << 2)
#define UART_CTRL_UART_RST         (1u << 3)
#define UART_CTRL_BOUNDARY_ON      (1u << 4)

#define TIMER_BASE_ADDR            0x80020000u
#define TIMER_LOAD                 (TIMER_BASE_ADDR + 0x00u)
#define TIMER_VALUE                (TIMER_BASE_ADDR + 0x04u)
#define TIMER_CTRL                 (TIMER_BASE_ADDR + 0x08u)
#define TIMER_INTCLR               (TIMER_BASE_ADDR + 0x0Cu)
#define TIMER_PRESCALER            (TIMER_BASE_ADDR + 0x10u)

#define TIMER_CTRL_ENABLE          (1u << 0)
#define TIMER_CTRL_INT_ENABLE      (1u << 1)
#define TIMER_CTRL_MODE_PERIODIC   (1u << 2)
#define TIMER_CTRL_RELOAD          (1u << 3)
#define TIMER_CTRL_PRESCALER_EN    (1u << 4)

#define LED_BASE_ADDR              0x80030000u
#define LED_VALUE                  (LED_BASE_ADDR + 0x00u)

#define PLIC_NUM_INTERRUPTS        32u
#define PLIC_PRIORITY_BASE         0x80300000u
#define PLIC_PENDING               0x80301000u
#define PLIC_ENABLE                0x80302000u
#define PLIC_THRESHOLD             0x80304000u
#define PLIC_CLAIM_COMPLETE        0x80304004u
#define PLIC_IN_SERVICE            0x80305000u

#define TIMER_INT_ID               1u
#define UART_RX_INT_ID             2u
#define UART_TX_INT_ID             3u

#define CSR_MSTATUS                0x300u
#define CSR_MIE                    0x304u
#define CSR_MTVEC                  0x305u
#define CSR_MSCRATCH               0x340u
#define CSR_MEPC                   0x341u
#define CSR_MCAUSE                 0x342u
#define CSR_MTVAL                  0x343u
#define CSR_MIP                    0x344u
#define CSR_CYCLE                  0xC00u
#define CSR_INSTRET                0xC02u

#define MSTATUS_MIE                (1u << 3)
#define MSTATUS_MPIE               (1u << 7)
#define MIE_MEIE                   (1u << 11)
#define MCAUSE_MACHINE_EXTERNAL    0x8000000Bu

static inline void plic_set_priority(uint32_t id, uint32_t priority) {
    mmio_write32(PLIC_PRIORITY_BASE + id * 4u, priority);
}

static inline void plic_enable(uint32_t mask) {
    mmio_write32(PLIC_ENABLE, mask);
}

static inline uint32_t plic_claim(void) {
    return mmio_read32(PLIC_CLAIM_COMPLETE);
}

static inline void plic_complete(uint32_t id) {
    mmio_write32(PLIC_CLAIM_COMPLETE, id);
}

static inline void uart_enable_polling(uint32_t baud_div) {
    mmio_write32(UART_BAUD, baud_div);
    mmio_write32(UART_CTRL, UART_CTRL_UART_EN | UART_CTRL_BOUNDARY_ON);
}

static inline void uart_putc_poll(char ch) {
    while ((mmio_read32(UART_STATUS) & UART_STATUS_TX_FULL) != 0u) {
    }
    mmio_write32(UART_DATA, (uint32_t)(uint8_t)ch);
}

#endif
