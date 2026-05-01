# RISC-V 仿真性能测试（独立工程）

这是一个与仓库其它目录**完全独立**的性能测试工程，目标是在仿真环境下快速得到有说服力的性能指标，同时控制总仿真时长。

## 设计目标

- **独立性**：不依赖原有 `start.s`、`uart.c`、`Makefile` 或其它模块。
- **可解释性**：输出 `cycles`、`instret`、`CPI`（放大1000倍）三个核心指标。
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

- `benchmark.c`
  - `CLK_FREQ_HZ`、`UART_BASE_ADDR`：按平台地址映射修改。
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
