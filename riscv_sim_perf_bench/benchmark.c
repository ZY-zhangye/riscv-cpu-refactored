#include <stdint.h>

/*
 * ========================= 可修改参数区（最常改） =========================
 * 1) 时钟/串口映射：按你的 SoC 地址映射修改。
 * 2) 规模参数：按仿真时长预算修改 BENCH_SCALE / *_BASE。
 * 3) 负载结构：bench_alu / bench_branch / bench_memory 可独立扩展。
 */
#ifndef CPU_FREQ_HZ
#define CPU_FREQ_HZ      130000000u
#endif

#ifndef UART_FREQ_HZ
#define UART_FREQ_HZ     50000000u
#endif

#ifndef BENCH_UART_OUTPUT
#define BENCH_UART_OUTPUT 0
#endif

/*
 * ===================== UART 地址映射与寄存器定义 =====================
 * UART 模块在 AXI 总线上的基地址为 0x80010000。下面定义的是相对于基地址的寄存器偏移。
 * 
 * 寄存器地址表：
 * +--+----------+--------+---------+----------------------------------------------------+
 * |#1| 偏移     | 地址   | 名称    | 功能说明                                           |
 * +--+----------+--------+---------+----------------------------------------------------+
 * |  | 0x0      | 0x8001 | DATA    | 收发缓冲区（写=发送，读=接收）                     |
 * |  | 0x4      | 0x8001 | STATUS  | 状态标志（bit0:TX_EMPTY, bit1:RX_READY...）       |
 * |  | 0x8      | 0x8001 | CTRL    | 使能/中断配置                                      |
 * |  | 0xC      | 0x8001 | BAUD    | 波特率分频寄存器                                   |
 * +--+----------+--------+---------+----------------------------------------------------+
 */
#define UART_BASE_ADDR   0x80010000u

/* ========= 寄存器偏移定义 ========= */
/* DATA 寄存器 (0x0) - 收发缓冲区
 *   写入：将数据 [7:0] 推入发送 FIFO
 *   读出：从接收 FIFO 读取 [7:0]
 */
#define UART_DATA_ADDR   (UART_BASE_ADDR + 0x0u)

/* STATUS 寄存器 (0x4) - 状态标志与中断状态
 *   bit[0]     TX_EMPTY    : 1 = 发送缓冲区空且移位寄存器空，可以写新数据
 *   bit[1]     RX_READY    : 1 = 接收缓冲区非空，至少有一字节数据可读
 *   bit[2]     TX_FULL     : 1 = 发送 FIFO 已满，不能再写
 *   bit[3]     RX_FULL     : 1 = 接收 FIFO 已满，新数据将被丢弃（溢出风险）
 *   bit[4]     TX_INT      : 1 = 发送中断待处理（写 CTRL 的 bit[3] 清除）
 *   bit[5]     RX_INT      : 1 = 接收中断待处理（写 CTRL 的 bit[4] 清除）
 *   bit[31:6]  保留
 */
#define UART_STATUS_ADDR (UART_BASE_ADDR + 0x4u)

/* CTRL 寄存器 (0x8) - 控制与中断配置
 *   bit[0]     EN          : 1 = UART 使能
 *   bit[1]     TX_INT_EN   : 1 = 发送中断使能（当 TX_EMPTY 时触发）
 *   bit[2]     RX_INT_EN   : 1 = 接收中断使能（当 RX_READY 时触发）
 *   bit[3]     TX_INT_CLR  : 写 1 清除发送中断标志（硬件自动清除）
 *   bit[4]     RX_INT_CLR  : 写 1 清除接收中断标志（硬件自动清除）
 *   bit[31:5]  保留
 *   
 *   典型初值：0x15 = 0b10101
 *            = RX_INT_EN(bit2=1) | TX_INT_EN(bit1=1) | EN(bit0=1)
 */
#define UART_CTRL_ADDR   (UART_BASE_ADDR + 0x8u)

/* BAUD 寄存器 (0xC) - 波特率分频配置
 *   写入 16 位分频值 DIV：
 *   实际波特率 = CLK_FREQ_HZ / DIV
 *   例：CLK=50MHz, 期望115200 bps
 *      DIV = 50000000 / 115200 ≈ 434 (0x1B2)
 *   
 *   硬件内部用此值生成接收采样时钟与发送波特率时钟
 */
#define UART_BAUD_ADDR   (UART_BASE_ADDR + 0xCu)

/* ===== UART 状态掩码 ===== */
#define UART_TX_EMPTY_MASK   0x01u   /* 发送缓冲区空 */
#define UART_RX_READY_MASK   0x02u   /* 接收缓冲区非空 */
#define UART_TX_FULL_MASK    0x04u   /* 发送缓冲区满 */
#define UART_RX_FULL_MASK    0x08u   /* 接收缓冲区满 */
#define UART_TX_INT_FLAG     0x10u   /* 发送中断待处理 */
#define UART_RX_INT_FLAG     0x20u   /* 接收中断待处理 */

/* ===== UART 控制掩码 ===== */
#define UART_EN              0x01u   /* UART 使能 */
#define UART_TX_INT_EN       0x02u   /* 发送中断使能 */
#define UART_RX_INT_EN       0x04u   /* 接收中断使能 */
#define UART_TX_INT_CLR      0x08u   /* 发送中断清除 */
#define UART_RX_INT_CLR      0x10u   /* 接收中断清除 */
#define UART_CTRL_ENABLE     0x15u   /* 典型使能值 = EN + TX_INT_EN + RX_INT_EN */

/*
 * 仿真规模控制：
 * - BENCH_SCALE: 总体倍率（建议先 1 验证，再逐步 2~4 增强说服力）
 * - *_BASE: 三类子测试的基础迭代规模
 */
#define BENCH_SCALE        1u
#define ALU_ITERS_BASE     12000u
#define BRANCH_ITERS_BASE  12000u
#define MEM_WORDS          256u
#define MEM_PASSES_BASE    180u

/*
 * g_sink 用于防止编译器把测试循环优化掉。
 * g_mem  为内存访存测试缓冲区。
 */
static volatile uint32_t g_sink;
static uint32_t g_mem[MEM_WORDS];

#define PERF_RESULT_MAGIC   0x4C334530u /* "L3E0" */
#define PERF_RESULT_VERSION 1u

typedef struct {
    uint32_t cycles;
    uint32_t instret;
    uint32_t branch;
    uint32_t branch_mispredict;
    uint32_t branch_hit;
    uint32_t branch_miss;
    uint32_t load_use;
    uint32_t exe_stall;
    uint32_t exception;
    uint32_t dual_issue;
    uint32_t single_issue;
    uint32_t issue_raw;
    uint32_t issue_waw;
    uint32_t issue_struct;
    uint32_t lsu_pair;
    uint32_t lane1_control;
    uint32_t lsu_conflict;
    uint32_t bitman_pair;
    uint32_t cross_packet;
    uint32_t issue_qfull;
} perf_report_t;

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t cpu_freq_hz;
    uint32_t sink;
    perf_report_t alu;
    perf_report_t branch;
    perf_report_t memory;
} perf_results_t;

/* 固定在数据RAM末尾的256-byte仿真邮箱；magic最后写入。 */
volatile perf_results_t g_perf_results
    __attribute__((section(".perf_results"), aligned(4)));

static inline void mmio_write(uint32_t addr, uint32_t value) {
    *((volatile uint32_t *)addr) = value;
}

static inline uint32_t mmio_read(uint32_t addr) {
    return *((volatile uint32_t *)addr);
}

#define READ_CSR_IMM(csr_num) ({                         \
    uint32_t csr_value;                                  \
    __asm__ volatile ("csrr %0, " #csr_num              \
                      : "=r"(csr_value) :: "memory");   \
    csr_value;                                           \
})

#define WRITE_CSR_IMM(csr_num, value)                    \
    __asm__ volatile ("csrw " #csr_num ", %0"            \
                      :: "r"((uint32_t)(value)) : "memory")

static inline void perf_begin(void) {
    WRITE_CSR_IMM(0x7C0, 2u);
    WRITE_CSR_IMM(0x7C0, 1u);
}

static inline void perf_end(void) {
    WRITE_CSR_IMM(0x7C0, 0u);
}

static void capture_perf(volatile perf_report_t *report) {
    report->cycles            = READ_CSR_IMM(0x7C1);
    report->instret           = READ_CSR_IMM(0x7C2);
    report->branch            = READ_CSR_IMM(0x7C3);
    report->branch_mispredict = READ_CSR_IMM(0x7C4);
    report->branch_hit        = READ_CSR_IMM(0x7C5);
    report->branch_miss       = READ_CSR_IMM(0x7C6);
    report->load_use          = READ_CSR_IMM(0x7C7);
    report->exe_stall         = READ_CSR_IMM(0x7C8);
    report->exception         = READ_CSR_IMM(0x7C9);
    report->dual_issue        = READ_CSR_IMM(0x7CA);
    report->single_issue      = READ_CSR_IMM(0x7CB);
    report->issue_raw         = READ_CSR_IMM(0x7CC);
    report->issue_waw         = READ_CSR_IMM(0x7CD);
    report->issue_struct      = READ_CSR_IMM(0x7CE);
    report->lsu_pair          = READ_CSR_IMM(0x7CF);
    report->lane1_control     = READ_CSR_IMM(0x7D0);
    report->lsu_conflict      = READ_CSR_IMM(0x7D1);
    report->bitman_pair       = READ_CSR_IMM(0x7D2);
    report->cross_packet      = READ_CSR_IMM(0x7D3);
    report->issue_qfull       = READ_CSR_IMM(0x7D4);
}

static void uart_init(uint32_t baudrate) {
    /* 可改：串口波特率；若仿真模型忽略 BAUD，也可保留默认 */
    if (baudrate == 0u) {
        baudrate = 115200u;
    }
    mmio_write(UART_BAUD_ADDR, UART_FREQ_HZ / baudrate);
    mmio_write(UART_CTRL_ADDR, UART_CTRL_ENABLE);
}

static void uart_putc(char c) {
    while ((mmio_read(UART_STATUS_ADDR) & UART_TX_EMPTY_MASK) == 0u) {
        /* busy wait */
    }
    mmio_write(UART_DATA_ADDR, (uint32_t)(uint8_t)c);
}

static void uart_puts(const char *s) {
    while (*s != '\0') {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s++);
    }
}

static void uart_put_u32(uint32_t x) {
    char buf[10];
    uint32_t i = 0;

    if (x == 0u) {
        uart_putc('0');
        return;
    }

    while (x > 0u) {
        buf[i++] = (char)('0' + (x % 10u));
        x /= 10u;
    }

    while (i > 0u) {
        uart_putc(buf[--i]);
    }
}

static void uart_put_hex32(uint32_t x) {
    static const char hex[] = "0123456789ABCDEF";
    int i;
    uart_puts("0x");
    for (i = 7; i >= 0; --i) {
        uart_putc(hex[(x >> (i * 4)) & 0xFu]);
    }
}

static void bench_alu(uint32_t iters) {
    /* ALU 密集型负载：移位/异或/加法，主要观察算术路径效率 */
    uint32_t x = 0x12345678u;
    uint32_t y = 0x9E3779B9u;
    uint32_t i;

    for (i = 0; i < iters; ++i) {
        x ^= (x << 5) + (x >> 2) + y;
        y += (x << 7) ^ (x >> 3) ^ 0xA5A5A5A5u;
        x = (x << 1) | (x >> 31);
        y = (y >> 1) | (y << 31);
    }

    g_sink ^= x ^ y;
}

static void bench_branch(uint32_t iters) {
    /* 分支负载：含多分支路径，观察分支处理和流水线行为 */
    uint32_t s = 0x31415926u;
    uint32_t acc = 0;
    uint32_t i;

    for (i = 0; i < iters; ++i) {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        if (s & 1u) {
            acc += (s >> 3) ^ 0x55AA55AAu;
        } else {
            acc ^= (s << 1) + 0x13579BDFu;
        }

        if ((s & 0x1Cu) == 0x14u) {
            acc += i;
        } else if ((s & 0x1Cu) == 0x08u) {
            acc ^= (i << 2);
        } else {
            acc += 3u;
        }
    }

    g_sink ^= acc;
}

static void bench_memory(uint32_t passes) {
    /* 访存负载：数组随机扰动读写，观察 load/store 与存储系统表现 */
    uint32_t p, i;
    uint32_t mix = 0xCAFEBABEu;

    for (i = 0; i < MEM_WORDS; ++i) {
        g_mem[i] = i ^ 0xA5A5A5A5u;
    }

    for (p = 0; p < passes; ++p) {
        for (i = 0; i < MEM_WORDS; ++i) {
            uint32_t j = ((i << 4) + i + (p << 3) + (p << 2) + p) & (MEM_WORDS - 1u);
            uint32_t v = g_mem[j];
            v = (v << 3) ^ (v >> 1) ^ (p + i);
            g_mem[j] = v;
            mix ^= v;
        }
    }

    g_sink ^= mix;
}

static void print_metric(const char *name, uint32_t cycles, uint32_t instret) {
    /* CPI(x1000) = cycles * 1000 / instret，放大后避免浮点 */
    uint32_t cpi_x1000 = 0;
    /* IPS(x1M) = instret * CLK_FREQ / cycles，单位：10^6 instructions/sec */
    /* 为避免溢出，采用两步计算：先算 (instret*1000/cycles)，再乘以CLK_FREQ/1000 */
    uint32_t ips_x1m = 0;  /* Instructions Per Second × 1M */
    uint32_t per_frame_us = 0; /* microseconds per 1000 instructions */

    if (instret != 0u) {
        cpi_x1000 = ((cycles << 10) - (cycles << 4) - (cycles << 3)) / instret;
        
        /* IPS = instret * CLK_FREQ / cycles = instret * 50M / cycles */
        /* 计算 instret / cycles（放大1000倍避免精度丢失）*/
        uint32_t rate_x1000 = (instret * 1000u) / cycles;  /* instret/cycles * 1000 */
        /* IPS = rate_x1000 * CLK_FREQ / 1000000 */
        ips_x1m = (rate_x1000 * (CPU_FREQ_HZ / 1000u)) / 1000u;
        
        /* Per-frame time: 微秒/1000条指令 */
        per_frame_us = (cycles * 1000000u) / (CPU_FREQ_HZ / 1000u) / instret;
    }

    uart_puts(name);
    uart_puts(": cycles=");
    uart_put_u32(cycles);
    uart_puts(", instret=");
    uart_put_u32(instret);
    uart_puts(", CPI(x1000)=");
    uart_put_u32(cpi_x1000);
    uart_puts(", IPS(x1M)=");
    uart_put_u32(ips_x1m);
    uart_puts(", us/1K=");
    uart_put_u32(per_frame_us);
    uart_puts("\n");
}

int main(void) {
    /*
     * 可改：这三个变量决定仿真总耗时。
     * 若仿真过慢：先减 BENCH_SCALE；若需更稳统计：增 BENCH_SCALE。
     */
    uint32_t alu_iters = ALU_ITERS_BASE * BENCH_SCALE;
    uint32_t branch_iters = BRANCH_ITERS_BASE * BENCH_SCALE;
    uint32_t mem_passes = MEM_PASSES_BASE * BENCH_SCALE;
    
    /* 性能评分相关 */
    uint32_t total_cycles = 0;
    uint32_t total_instret = 0;
    uint32_t alu_cycles = 0, alu_instret = 0;
    uint32_t branch_cycles = 0, branch_instret = 0;
    uint32_t memory_cycles = 0, memory_instret = 0;

    g_perf_results.magic = 0u;
    g_perf_results.version = PERF_RESULT_VERSION;
    g_perf_results.cpu_freq_hz = CPU_FREQ_HZ;

    if (BENCH_UART_OUTPUT) {
        uart_init(115200u);
        uart_puts("\n=== RISC-V Simulation Performance Benchmark (Independent) ===\n");
        uart_puts("CPU Clock(Hz): ");
        uart_put_u32(CPU_FREQ_HZ);
        uart_puts("\nScale: ");
        uart_put_u32(BENCH_SCALE);
        uart_puts("\n\n");
    }

    perf_begin();
    bench_alu(alu_iters);
    perf_end();
    capture_perf(&g_perf_results.alu);
    alu_cycles = g_perf_results.alu.cycles;
    alu_instret = g_perf_results.alu.instret;
    if (BENCH_UART_OUTPUT) {
        print_metric("ALU", alu_cycles, alu_instret);
    }

    perf_begin();
    bench_branch(branch_iters);
    perf_end();
    capture_perf(&g_perf_results.branch);
    branch_cycles = g_perf_results.branch.cycles;
    branch_instret = g_perf_results.branch.instret;
    if (BENCH_UART_OUTPUT) {
        print_metric("BRANCH", branch_cycles, branch_instret);
    }

    perf_begin();
    bench_memory(mem_passes);
    perf_end();
    capture_perf(&g_perf_results.memory);
    memory_cycles = g_perf_results.memory.cycles;
    memory_instret = g_perf_results.memory.instret;
    if (BENCH_UART_OUTPUT) {
        print_metric("MEMORY", memory_cycles, memory_instret);
    }
    
    /* 累加总体指标 */
    total_cycles = alu_cycles + branch_cycles + memory_cycles;
    total_instret = alu_instret + branch_instret + memory_instret;

    if (BENCH_UART_OUTPUT) {
        uart_puts("\n==== Overall Performance Summary ====\n");
        uart_puts("Total cycles: ");
        uart_put_u32(total_cycles);
        uart_puts(", Total instret: ");
        uart_put_u32(total_instret);
        uart_puts("\n");
        print_metric("OVERALL", total_cycles, total_instret);
    }
    
    /* CoreMark-style 评分计算 */
    /* Score = (instret / cycles) * clock_freq * 100 */
    /* 分子：instret/cycles，用定点表示（×1000）*/
    uint32_t overall_cpi_x1000 = 0;
    if (total_instret != 0u) {
        overall_cpi_x1000 = ((total_cycles << 10) - (total_cycles << 4) - (total_cycles << 3)) / total_instret;
    }
    /* Score ≈ (1/CPI) * 100 */
    uint32_t coremark_like_score = 0;
    if (overall_cpi_x1000 != 0u) {
        /* Score = 100000 / overall_cpi_x1000 */
        coremark_like_score = 100000u / overall_cpi_x1000;
    }
    g_perf_results.sink = g_sink;
    __asm__ volatile ("fence rw, rw" ::: "memory");
    g_perf_results.magic = PERF_RESULT_MAGIC;

    if (BENCH_UART_OUTPUT) {
        uart_puts("\nPerformance Score (CoreMark-like): ");
        uart_put_u32(coremark_like_score);
        uart_puts("\n");
        uart_puts("sink=");
        uart_put_hex32(g_sink);
        uart_puts("\nDone.\n");
    }

    /* 测试结束后停机等待，避免程序跑飞影响仿真观察 */
    while (1) {
        __asm__ volatile ("wfi");
    }

    return 0;
}
