# RISC-V 仿真性能测试（独立工程）

这是一个与仓库其它目录**完全独立**的性能测试工程，目标是在仿真环境下快速得到有说服力的性能指标，同时控制总仿真时长。

## 设计目标

- **独立性**：不依赖原有 `start.s`、`uart.c`、`Makefile` 或其它模块。
- **可解释性**：分段采集 `cycles`、`instret`、双发、RAW/WAW、分支、load-use、LSU 和 queue full 等完整性能计数。
- **仿真友好**：默认循环规模适中，避免仿真时间过长。
- **代表性**：分离测试三类负载：
  - `ALU`：移位/异或/加法密集
  - `BRANCH`：条件分支与不可预测路径
  - `MEMORY`：数组读写与访存扰动

## 目录结构

- `benchmark.c`：基准主程序（含 UART 输出和 CSR 统计）
- `startup.S`：启动入口与 `.bss` 清零
- `linker.ld`：链接脚本（指令/数据地址布局）
- `Makefile`：独立构建脚本
- `build/`：ELF 产物
- `out/`：反汇编与 HEX 文件

## 构建

在本目录下执行 `make` 后会生成：

- `build/sim_perf_bench.elf`
- `out/sim_perf_bench.dump`
- `out/inst.hex`（纯 HEX，**每行一个32位指令字**）
- `out/data.hex`（纯 HEX，**每行一个32位数据字**）
- `out/inst.coe`（指令 COE）
- `out/data.coe`（数据 COE）

> 说明：默认输出深度为 1024 行，不足部分补 `00000000`。可在 `Makefile` 里修改 `DEPTH`。

默认构建参数为：

```text
CPU_FREQ_HZ=130000000
UART_FREQ_HZ=50000000
BENCH_UART_OUTPUT=0
```

`CPU_FREQ_HZ` 只用于把仿真得到的 IPC 换算成签核频率下的吞吐；Questa 的仿真时钟周期不会改变架构 cycle 计数。`UART_FREQ_HZ` 单独用于波特率分频，避免把 CPU 频率和 UART 时钟混为一谈。需要串口文本输出时可使用 `make BENCH_UART_OUTPUT=1`。

## L3E 仿真结果邮箱

默认仿真不等待 UART 串行输出，而是在 `0x6000_0700~0x6000_07FF` 写入固定 256-byte 结果邮箱。`test/tb_top.sv` 监视最后写入的 magic `0x4C334530`，随后打印三行机器可读的 `L3E_REPORT` 并自动结束仿真。

每个 ALU/BRANCH/MEMORY 报告包含 20 个 32-bit 计数：

```text
cycle, instret, branch, branch_mispredict, branch_hit, branch_miss,
load_use, exe_stall, exception, dual_issue, single_issue,
issue_raw, issue_waw, issue_struct, lsu_pair, lane1_control,
lsu_conflict, bitman_pair, cross_packet, issue_qfull
```

testbench 还会输出 `L3E_QUEUE`，统计性能窗口内 issue queue 深度分布，并把 queue full 分为下游反压与本地接收容量限制。邮箱位于链接脚本保留区，不进入普通 `.bss`，magic 始终最后写入。

## 仿真时间与说服力平衡建议

当前默认规模由以下宏控制（`benchmark.c`）：

- `BENCH_SCALE`（默认 `1`）
- `ALU_ITERS_BASE`（默认 `12000`）
- `BRANCH_ITERS_BASE`（默认 `12000`）
- `MEM_PASSES_BASE`（默认 `180`）

建议：

1. 先用默认值验证功能与输出格式。
2. 若仿真太慢，先将 `BENCH_SCALE` 调到 `0` 或减半各基数（快速回归）。
3. 若要更强说服力，逐步将 `BENCH_SCALE` 提升到 `2~4`，观察指标稳定性。
4. 报告时同时给出三类负载，避免单一程序导致结论片面。

## 你最常改的位置

- `benchmark.c` / `Makefile`
  - `CPU_FREQ_HZ`、`UART_FREQ_HZ`、`BENCH_UART_OUTPUT`：分别控制吞吐换算、UART 分频和文本输出。
  - `UART_BASE_ADDR`：按平台地址映射修改。
  - `BENCH_SCALE`、`*_BASE`：控制仿真时长与统计稳定性。
- `linker.ld`
  - `MEMORY` 里的 `ORIGIN/LENGTH`：按 irom/dram 实际大小和地址修改。
  - `.stack` 大小：当前 `0x100`，可按函数深度加大。
- `Makefile`
  - `DEPTH`：HEX/COE 导出行数。

---

## UART 硬件设计

如果你需要在硬件中实现 UART 模块，详见 [UART_DESIGN.md](UART_DESIGN.md)，包含：

- 完整的寄存器定义与位字段说明
- RTL 伪代码实现参考
- 时序流程和工作示例
- 与 benchmark.c 的对应关系
