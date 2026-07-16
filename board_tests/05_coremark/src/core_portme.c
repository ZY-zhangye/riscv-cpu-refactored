#include "coremark.h"

/* ---- Volatile seeds ---- */
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#elif VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#elif PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1;

/* ---- Timing globals ---- */
static CORETIMETYPE start_time_val, stop_time_val;

void start_time(void)   { GETMYTIME(&start_time_val); }
void stop_time(void)    { GETMYTIME(&stop_time_val); }
CORE_TICKS get_time(void) { return (CORE_TICKS)MYTIMEDIFF(stop_time_val, start_time_val); }
secs_ret time_in_secs(CORE_TICKS ticks) { return (secs_ret)ticks / (secs_ret)EE_TICKS_PER_SEC; }

/* ---- UART helpers (polling) ---- */
static void uart_putc(char c)
{
    if (c == '\n') {
        while (mmio_read32(UART_STATUS) & UART_STATUS_TX_FULL) {}
        mmio_write32(UART_DATA, '\r');
    }
    while (mmio_read32(UART_STATUS) & UART_STATUS_TX_FULL) {}
    mmio_write32(UART_DATA, (uint32_t)(uint8_t)c);
}

static void uart_puts(const char *s)
{
    while (*s) uart_putc(*s++);
}

static const ee_u32 dec_pow10[] = {
    1000000000u, 100000000u, 10000000u, 1000000u,
    100000u, 10000u, 1000u, 100u, 10u, 1u
};

static void uart_putnum(ee_u32 val)
{
    int i = 0;
    if (val == 0) { uart_putc('0'); return; }
    while (i < 9 && val < dec_pow10[i]) i++;
    while (i < 10) {
        ee_u32 d = dec_pow10[i];
        char c = '0';
        while (val >= d) { val -= d; c++; }
        uart_putc(c);
        i++;
    }
}

static void uart_puthex4(ee_u16 val)
{
    int i;
    for (i = 12; i >= 0; i -= 4) {
        int d = (val >> i) & 0xF;
        uart_putc(d < 10 ? '0' + d : 'a' + d - 10);
    }
}

/* ---- ee_printf: minimal formatted output over UART ---- */
#include <stdarg.h>

int ee_printf(const char *fmt, ...)
{
    va_list va;
    va_start(va, fmt);
    while (*fmt) {
        if (*fmt == '%') {
            fmt++;
            if (*fmt == 's') {
                uart_puts(va_arg(va, const char *));
            } else if (*fmt == 'd') {
                ee_s32 d = va_arg(va, ee_s32);
                if (d < 0) { uart_putc('-'); d = -d; }
                uart_putnum((ee_u32)d);
            } else if (*fmt == 'u') {
                uart_putnum(va_arg(va, ee_u32));
            } else if (*fmt == 'l' && *(fmt+1) == 'u') {
                fmt++;
                uart_putnum(va_arg(va, ee_u32));
            } else if (*fmt == 'f') {
                (void)va_arg(va, double);
                uart_puts("(float)");
            } else if (*fmt == '%') {
                uart_putc('%');
            } else if (*fmt == '0' && *(fmt+1) == '4' && *(fmt+2) == 'x') {
                fmt += 2;
                uart_puthex4(va_arg(va, ee_u32));
            } else {
                uart_putc('%');
                uart_putc(*fmt);
            }
        } else {
            uart_putc(*fmt);
        }
        fmt++;
    }
    va_end(va);
    return 0;
}

/* ---- Target init/fini ---- */
void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;

    mmio_write32(UART_BAUD, 1519u);
    mmio_write32(UART_CTRL, UART_CTRL_UART_EN | UART_CTRL_BOUNDARY_ON);

    mmio_write32(TIMER_LOAD, 0xFFFFFFFFu);
    mmio_write32(TIMER_CTRL, TIMER_CTRL_ENABLE | TIMER_CTRL_MODE_PERIODIC | TIMER_CTRL_RELOAD);

    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    p->portable_id = 0;
}
