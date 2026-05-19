# C 程序移植参考

本文按当前 RTL 整理 C 程序可能用到的地址、寄存器位和中断使用约定。信息来源以 `rtl/cpu_top/*.sv*` 和 `rtl/my_cpu/*.sv*` 为准。

## CPU 与内存

### 取指 PC 基地址

| 场景 | `PC_START` | 说明 |
| --- | ---: | --- |
| 普通工程/SoC 模式 | `0x8000_0000` | 默认值，见 `rtl/cpu_top/defines.svh` |
| 定义 `PERF_BENCH` | `0x0000_0000` | 兼容旧 `riscv_sim_perf_bench` 流程 |

当前取指侧直接使用 `imem_addr` 访问指令 RAM，仿真 RAM 用地址低位索引，所以正常 C 工程建议把 `.text` 链接到 `0x8000_0000`。

### 数据 RAM 地址

| 地址范围 | 用途 | 备注 |
| --- | --- | --- |
| `0x8010_0000` - `0x8013_FFFF` | 推荐 DRAM 区 | 赛事文档风格，256 KiB |
| `0x6000_0000` 开头 | benchmark 兼容数据区 | bridge 按 `addr[31:28] == 4'h6` 选择 RAM |

这两个区域在当前 `soc_data_ram` 里都会按低地址位进入同一类 RAM 存储体，软件侧最好只选一个作为主数据区，避免地址别名带来的困惑。

## MMIO 总览

| 模块 | 基地址/范围 | 说明 |
| --- | ---: | --- |
| UART | `0x8001_0000` | 串口收发、状态、中断 |
| Timer | `0x8002_0000` | 32 位倒计时定时器 |
| LED | `0x8003_0000` | 32 位 LED 输出寄存器 |
| PLIC | `0x8030_0000` - `0x8030_5004` | 外部中断控制器 |

`IO.sv` 对 UART/Timer/LED 使用地址高 16 位译码，因此软件应使用下表列出的低 16 位偏移。

`rtl/cpu_top/defines.svh` 里还保留了旧 MIMO 宏，例如 `SW_LOW_ADDR=0x8020_0000`、`LED_ADDR=0x8020_0040`、`CNT_ADDR=0x8020_0050`。这些不是当前 `rtl/my_cpu/my_cpu.sv` SoC 封装实际接出的外设地址；现在写 C 程序时优先使用本文件的 `0x8001_0000`、`0x8002_0000`、`0x8003_0000` 和 `0x8030_xxxx` 地址。

## UART

### 地址

| 名称 | 地址 | 访问 | 说明 |
| --- | ---: | --- | --- |
| `UART_DATA` | `0x8001_0000` | R/W | 写入 `bit[7:0]` 推入 TX FIFO；读取弹出 RX FIFO |
| `UART_STATUS` | `0x8001_0004` | R/W | 读状态；写 `bit5=1` 清除 overflow |
| `UART_CTRL` | `0x8001_0008` | R/W | UART 使能、中断使能、软复位、波特率模式 |
| `UART_BAUD` | `0x8001_000C` | R/W | 内部分频模式下的波特率计数阈值 |

### `UART_STATUS` 位定义

| 位 | 名称 | 说明 |
| ---: | --- | --- |
| 0 | `TX_EMPTY` | TX FIFO 为空且发送状态机空闲 |
| 1 | `RX_READY` | RX FIFO 非空 |
| 2 | `TX_FULL` | TX FIFO 已满 |
| 3 | `RX_FULL` | RX FIFO 已满 |
| 4 | `PARITY_ERROR` | 当前 RTL 固定为 0 |
| 5 | `OVERFLOW_ERROR` | TX/RX FIFO 溢出；向 `UART_STATUS` 写 `bit5=1` 清除 |
| 6 | `TX_INT` | TX 中断输出状态 |
| 7 | `RX_INT` | RX 中断输出状态 |

### `UART_CTRL` 位定义

| 位 | 名称 | 说明 |
| ---: | --- | --- |
| 0 | `RX_INT_EN` | RX 中断使能，`RX_READY` 时触发 |
| 1 | `TX_INT_EN` | TX 中断使能，`TX_EMPTY` 时触发 |
| 2 | `UART_EN` | UART 总使能 |
| 3 | `UART_RST` | 写 1 产生软复位脉冲，寄存器自身不保持为 1 |
| 4 | `BOUNDARY_ON` | 1：使用 `UART_BAUD` 内部分频；0：使用外部 `clk_uart` tick |

常用初始化：

```c
mmio_write(UART_BAUD, div);
mmio_write(UART_CTRL, UART_CTRL_UART_EN | UART_CTRL_BOUNDARY_ON);
```

如果要启用 RX 中断：

```c
mmio_write(UART_CTRL, UART_CTRL_UART_EN | UART_CTRL_BOUNDARY_ON | UART_CTRL_RX_INT_EN);
```

## Timer

### 地址

| 名称 | 地址 | 访问 | 说明 |
| --- | ---: | --- | --- |
| `TIMER_LOAD` | `0x8002_0000` | R/W | 写入装载值，同时 `VALUE <= LOAD` |
| `TIMER_VALUE` | `0x8002_0004` | R | 当前倒计时值 |
| `TIMER_CTRL` | `0x8002_0008` | R/W | 使能、模式、中断、预分频 |
| `TIMER_INTCLR` | `0x8002_000C` | R/W | 写 `bit0=1` 清除定时器中断 |
| `TIMER_PRESCALER` | `0x8002_0010` | R/W | 预分频计数阈值 |

### `TIMER_CTRL` 位定义

| 位 | 名称 | 说明 |
| ---: | --- | --- |
| 0 | `ENABLE` | 定时器使能 |
| 1 | `INT_ENABLE` | 倒计时到 0 时置 `timer_int` |
| 2 | `MODE` | 0：one-shot；1：periodic |
| 3 | `RELOAD` | periodic 模式下清中断后重装 `LOAD` |
| 4 | `PRESCALER_ENABLE` | 0：每个 CPU clk 递减；1：按 `TIMER_PRESCALER` 分频 |

典型周期中断初始化：

```c
mmio_write(TIMER_LOAD, ticks);
mmio_write(TIMER_PRESCALER, prescaler);
mmio_write(TIMER_CTRL,
           TIMER_CTRL_ENABLE |
           TIMER_CTRL_INT_ENABLE |
           TIMER_CTRL_MODE_PERIODIC |
           TIMER_CTRL_RELOAD |
           TIMER_CTRL_PRESCALER_ENABLE);
```

定时器 ISR 中需要先写：

```c
mmio_write(TIMER_INTCLR, 1);
```

## LED

| 名称 | 地址 | 访问 | 说明 |
| --- | ---: | --- | --- |
| `LED_VALUE` | `0x8003_0000` | R/W | 32 位 LED 输出寄存器，支持字节写使能 |

## PLIC

### 地址

| 名称 | 地址 | 访问 | 说明 |
| --- | ---: | --- | --- |
| `PLIC_PRIORITY_BASE + id * 4` | `0x8030_0000 + id * 4` | R/W | 中断源优先级，`id=0` 保留不可用 |
| `PLIC_PENDING` | `0x8030_1000` | R | pending 位图 |
| `PLIC_ENABLE` | `0x8030_2000` | R/W | enable 位图，`bit0` 强制为 0 |
| `PLIC_THRESHOLD` | `0x8030_4000` | R/W | 阈值，只有 `priority > threshold` 才会请求 CPU |
| `PLIC_CLAIM_COMPLETE` | `0x8030_4004` | R/W | 读 claim ID；写同一 ID complete |
| `PLIC_IN_SERVICE` | `0x8030_5000` | R | 正在服务的中断位图 |

当前参数：

| 参数 | 值 |
| --- | ---: |
| 中断源数量 | 32 |
| 中断 ID 宽度 | 5 |
| 优先级宽度 | 3，范围 `0..7` |

### 已连接中断号

| ID | 来源 |
| ---: | --- |
| 0 | 保留，不使用 |
| 1 | Timer |
| 2 | UART RX |
| 3 | UART TX |
| 其它 | `my_cpu.external_interrupts[id]` 外部输入 |

### PLIC 使用顺序

1. 给对应中断源写优先级，优先级必须大于阈值。
2. 在 `PLIC_ENABLE` 中置对应 ID 的 bit。
3. 写 `PLIC_THRESHOLD`，常用值为 0。
4. 在 CPU CSR 中设置 `mtvec`、`mie.MEIE` 和 `mstatus.MIE`。
5. 进入 ISR 后读取 `PLIC_CLAIM_COMPLETE` 得到 ID。
6. 清除具体外设的中断源，例如 Timer 写 `TIMER_INTCLR=1`。
7. 向 `PLIC_CLAIM_COMPLETE` 写回同一个 ID 完成中断。

PLIC 是电平式 pending：如果外设中断源在 complete 后仍保持为 1，它会再次进入 pending。

## CSR 与异常/中断

### CSR 地址

| CSR | 地址 | 软件用途 |
| --- | ---: | --- |
| `mstatus` | `0x300` | `MIE=bit3`，`MPIE=bit7` |
| `mie` | `0x304` | `MEIE=bit11` 控制 PLIC 外部中断 |
| `mtvec` | `0x305` | trap 入口地址，当前 RTL 按 direct 方式使用 |
| `mscratch` | `0x340` | 可由软件自由使用 |
| `mepc` | `0x341` | trap 返回 PC |
| `mcause` | `0x342` | trap 原因 |
| `mtval` | `0x343` | 同步异常附加信息；外部中断为 0 |
| `mip` | `0x344` | 可读写，但当前外部中断响应不依赖此寄存器 |
| `cycle` | `0xC00` | 32 位周期计数 |
| `instret` | `0xC02` | 32 位指令计数 |

### 当前 trap 语义

- 同步异常优先于 PLIC 外部中断。
- PLIC 外部中断只有在 `mstatus.MIE=1` 且 `mie.MEIE=1` 时进入 trap。
- 外部中断进入时：
  - `mcause = 0x8000_000B`
  - `mtval = 0`
  - `mstatus.MPIE <= mstatus.MIE`
  - `mstatus.MIE <= 0`
- `mret` 时：
  - `mstatus.MIE <= mstatus.MPIE`
  - `mstatus.MPIE <= 1`
  - PC 跳回 `mepc`

## 建议的 C 侧最小初始化顺序

```c
extern void trap_entry(void);

static inline void write_csr_mtvec(uint32_t v) {
    __asm__ volatile ("csrw mtvec, %0" :: "r"(v));
}

static inline void enable_machine_external_irq(void) {
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 11));     // MEIE
    __asm__ volatile ("csrs mstatus, %0" :: "r"(1u << 3));  // MIE
}

void platform_init(void) {
    write_csr_mtvec((uint32_t)trap_entry);

    mmio_write(PLIC_THRESHOLD, 0);
    mmio_write(PLIC_PRIORITY_BASE + TIMER_INT_ID * 4u, 1);
    mmio_write(PLIC_PRIORITY_BASE + UART_RX_INT_ID * 4u, 1);
    mmio_write(PLIC_ENABLE, (1u << TIMER_INT_ID) | (1u << UART_RX_INT_ID));

    enable_machine_external_irq();
}
```

## 注意事项

- 普通 MMIO 访问使用 `volatile uint32_t *`。
- 当前 bridge 对读返回做了一级目标寄存，软件用普通 load/store 即可，不需要额外空读。
- `mtvec` 建议 4 字节对齐。
- 当前没有实现 cache，也没有复杂总线握手；C 侧无需 fence 来保证 MMIO 顺序，但保留 `volatile` 是必要的。
- 如果链接脚本从旧 benchmark 搬来，需要把 `.text` 从 `0x0000_0000` 改到 `0x8000_0000`，除非 RTL 编译时定义了 `PERF_BENCH`。
