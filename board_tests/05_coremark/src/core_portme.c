#include "coremark.h"
#include <stdarg.h>

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

static CORETIMETYPE start_time_val, stop_time_val;
static uint32_t start_cycle, elapsed_cycle_mod32;
static uint32_t reported_iterations;
static uint32_t validation_passed;
static uint32_t timing_runs;
static uint32_t known_configuration, crc_error, crc_seen;
static uint32_t list_crc, matrix_crc, state_crc;

void start_time(void) {
    GETMYTIME(&start_time_val);
    start_cycle = board_cycle();
    ++timing_runs;
}
void stop_time(void) {
    GETMYTIME(&stop_time_val);
    elapsed_cycle_mod32 = board_cycle() - start_cycle;
}
CORE_TICKS get_time(void) { return (CORE_TICKS)MYTIMEDIFF(stop_time_val, start_time_val); }
secs_ret time_in_secs(CORE_TICKS ticks) {
    return (secs_ret)(((uint64_t)ticks * COREMARK_TIMER_DIVIDER) / BOARD_CPU_HZ);
}

static int same(const char *left, const char *right) {
    while (*left && *left == *right) { ++left; ++right; }
    return *left == *right;
}
static int begins(const char *text, const char *prefix) {
    while (*prefix) if (*text++ != *prefix++) return 0;
    return 1;
}

/* Observe the official reporting path without changing core_main/algorithms.
 * The official success message is required before reporting a valid score. */
int ee_printf(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    if (same(format, "Iterations       : %lu\n")) {
        va_list copy;
        va_copy(copy, arguments);
        reported_iterations = (uint32_t)va_arg(copy, unsigned long);
        va_end(copy);
    }
    if (begins(format, "Correct operation validated.")) validation_passed = 1;
    if (begins(format, "Errors detected") || begins(format, "Cannot validate operation")) validation_passed = 0;
    if (same(format, "2K performance run parameters for coremark.\n")) known_configuration = 1;
    if (begins(format, "[%u]ERROR!") || begins(format, "ERROR:")) crc_error = 1;
    if (same(format, "[%d]crclist       : 0x%04x\n") ||
        same(format, "[%d]crcmatrix     : 0x%04x\n") ||
        same(format, "[%d]crcstate      : 0x%04x\n")) {
        va_list copy;
        va_copy(copy, arguments);
        (void)va_arg(copy, int);
        uint32_t value = va_arg(copy, unsigned int);
        va_end(copy);
        if (same(format, "[%d]crclist       : 0x%04x\n")) { list_crc = value; crc_seen |= 1; }
        else if (same(format, "[%d]crcmatrix     : 0x%04x\n")) { matrix_crc = value; crc_seen |= 2; }
        else { state_crc = value; crc_seen |= 4; }
    }
    int result = board_vprintf(format, arguments);
    va_end(arguments);
    return result;
}

void portable_init(core_portable *port, int *argc, char *argv[]) {
    (void)argc;
    (void)argv;
    mmio_write32(LED_VALUE, 1u);
    board_uart_init();
    board_printf("[COREMARK] BOOT build=%s cpu_hz=%u uart_div=%u iterations=%u timer_div=%u\n",
                 BOARD_BUILD_ID, BOARD_CPU_HZ, BOARD_UART_DIV,
                 (unsigned)ITERATIONS, (unsigned)COREMARK_TIMER_DIVIDER);
    board_printf("[COREMARK] baseline: RV32IM+Zicsr ILP32, static 2000 bytes, official CRC checks; calibrating/running\n");
    mmio_write32(TIMER_CTRL, 0u);
    mmio_write32(TIMER_PRESCALER, COREMARK_TIMER_DIVIDER - 1u);
    mmio_write32(TIMER_LOAD, 0xFFFFFFFFu);
    mmio_write32(TIMER_CTRL, TIMER_CTRL_ENABLE | TIMER_CTRL_MODE_PERIODIC |
                 TIMER_CTRL_RELOAD | TIMER_CTRL_PRESCALER_EN);
    port->portable_id = 1;
}

void portable_fini(core_portable *port) {
    uint64_t cycles = (uint64_t)get_time() * COREMARK_TIMER_DIVIDER;
    uint64_t duration_us = cycles * 1000000u / BOARD_CPU_HZ;
    int crc_valid = known_configuration && !crc_error && crc_seen == 7u &&
                    list_crc == 0xE714u && matrix_crc == 0x1FD7u && state_crc == 0x8E3Au;
    int valid = validation_passed && crc_valid && cycles >= (uint64_t)BOARD_CPU_HZ * 10u &&
                reported_iterations != 0 && !board_uart_fault;
    /* Quotient/remainder splitting preserves six decimals without overflow. */
    uint64_t rate_x1m = 0, per_mhz_x1m = 0;
    if (valid) {
        uint64_t numerator = (uint64_t)reported_iterations * BOARD_CPU_HZ;
        rate_x1m = (numerator / cycles) * 1000000u +
                   ((numerator % cycles) * 1000000u) / cycles;
        numerator = (uint64_t)reported_iterations * 1000000u;
        per_mhz_x1m = (numerator / cycles) * 1000000u +
                     ((numerator % cycles) * 1000000u) / cycles;
    }
    board_printf("[COREMARK_RESULT] cpu_hz=%u iterations=%u timer_ticks=%u timer_div=%u cpu_cycles=",
                 BOARD_CPU_HZ, reported_iterations, get_time(), (unsigned)COREMARK_TIMER_DIVIDER);
    board_print_u64(cycles);
    board_printf(" duration_us="); board_print_u64(duration_us);
    board_printf(" cycle_csr_mod32=%u cycle_csr_full_width=%u timing_runs=%u validation=%u valid=%u\n",
                 elapsed_cycle_mod32, cycles <= UINT32_MAX ? 1u : 0u,
                 timing_runs, validation_passed, valid ? 1u : 0u);
    if (valid) {
        board_printf("[COREMARK_SCORE] iterations_per_second="); board_print_fixed6(rate_x1m);
        board_printf(" per_mhz="); board_print_fixed6(per_mhz_x1m);
        board_printf(" valid=1 (CRC validated; duration >= 10 seconds)\n");
    } else {
        board_printf("[COREMARK_SCORE] valid=0 reason=CRC_or_duration_or_UART; no performance score\n");
    }
    board_printf("COREMARK_CRC status=%s list=%04x matrix=%04x state=%04x\n",
                 crc_valid ? "PASS" : "FAIL", list_crc, matrix_crc, state_crc);
    board_printf("COREMARK_RESULT status=%s valid=%u score_x1000=",
                 valid ? "PASS" : (crc_valid && !board_uart_fault ? "SHORT" : "FAIL"), valid ? 1u : 0u);
    board_print_u64(rate_x1m / 1000u);
    board_printf(" score_per_mhz_x1000000="); board_print_u64(per_mhz_x1m);
    board_printf(" cycles="); board_print_u64(cycles);
    board_printf(" iterations=%u elapsed_ms=", reported_iterations); board_print_u64(duration_us / 1000u);
    board_printf(" cpu_hz=%u validation=%u\n", BOARD_CPU_HZ, crc_valid ? 1u : 0u);
    mmio_write32(LED_VALUE, valid ? 3u : 2u);
    port->portable_id = 0;
}
