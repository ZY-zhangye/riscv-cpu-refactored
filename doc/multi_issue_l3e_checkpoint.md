# 顺序多发 L3E 仿真性能归因检查点

## 目标

L3D 已在实际 130 MHz PLL 和 post-route physopt 后完成签核，但 setup WNS 仅 +0.002 ns。L3E 不直接修改 CPU 数据通路，而是先用仿真确定真实负载中的 IPC 损失来源，避免为偶发关键路径或猜测瓶颈引入高风险架构改动。

完成日期：2026-07-11

## 测量链路

`riscv_sim_perf_bench` 现在将 CPU 性能换算频率与 UART 时钟拆分：默认 `CPU_FREQ_HZ=130000000`、`UART_FREQ_HZ=50000000`。Questa 仍可使用任意方便的仿真时钟周期，架构 cycle 计数不受仿真时间单位影响。

每个 ALU、BRANCH、MEMORY 负载使用独立性能窗口，采集以下 CSR：

```text
cycle / instret
branch / branch_mispredict / branch_hit / branch_miss
load_use / exe_stall / exception
dual_issue / single_issue
issue_raw / issue_waw / issue_struct
lsu_pair / lane1_control / lsu_conflict
bitman_pair / cross_packet / issue_qfull
```

结果写入 `0x6000_0700~0x6000_07FF` 的固定 256-byte 数据 RAM 邮箱，magic 最后写入。`tb_uart_benchmark` 直接读取邮箱、打印机器可读的 `L3E_REPORT` 并自动判断完成，不把 UART 等待和打印开销计入测量窗口。

testbench 还通过层次观察统计 issue queue 深度，并把 queue full 区分为下游反压和本地接收容量限制；这些观察信号只存在于仿真，不修改综合 RTL。

## 130 MHz 换算基线

| 负载 | cycles | instret | IPC | 130 MHz 吞吐 |
| --- | ---: | ---: | ---: | ---: |
| ALU | 144,018 | 216,013 | 1.4999 | 195.0 MIPS |
| BRANCH | 213,072 | 245,975 | 1.1544 | 150.1 MIPS |
| MEMORY | 463,575 | 601,238 | 1.2970 | 168.6 MIPS |
| 合计 | 820,665 | 1,063,226 | 1.2956 | 168.4 MIPS |

三个负载合计的双发周期占有效单/双发周期约 46.35%。该 benchmark 比 L3 微基准更长且包含编译器生成的循环、分支和访存，但仍属于定向仿真负载，不等同于完整 CoreMark。

## 主要归因

### ALU

- 双发占比约 50.00%，IPC 接近 1.5。
- `issue_raw=72,006`，约等于 50% 测量周期；循环携带依赖是继续接近 2 IPC 的主要限制。
- 分支误预测仅 2 次，结构拒绝仅 2 次。
- `issue_qfull=36,004`，仿真分类显示几乎全部来自队列只能在本拍接收有限 fetch 指令，而非下游冻结。

### BRANCH

- IPC 1.1544，是三类负载最低值。
- 46,464 次控制流中有 11,279 次误预测，误预测率约 24.27%。该负载含伪随机条件，不能假设更大预测表一定能消除这些 miss。
- `issue_struct=17,181`，说明控制流组合限制也有影响。
- queue full 几乎全部是本地接收容量现象，不是持续下游反压。

### MEMORY

- IPC 1.2970，已发生 92,418 次 LSU+ALU 配对。
- `load_use=46,081`，约占 9.94% 测量周期，并与 testbench 观察到的 queue-full downstream 周期一致。
- `lsu_conflict=0`，当前负载没有出现 MEM store 阻塞年轻 EX load，因此不能据此证明 store buffer 有收益。
- `issue_qfull=138,241`；其中约 46,081 次来自 load-use 下游冻结，其余主要是队列接收容量限制。

RAW/WAW/结构事件可能在同一周期重叠，不能把这些计数直接相加当作总损失周期。queue full 也常是下游依赖或 fetch/consume 粒度不匹配的结果，不应仅凭该计数扩大队列。

## 决策

1. 继续维持单周期同步 load 协议，不切整个访存请求路径。
2. 暂不实现 store buffer；当前测量的 `lsu_conflict=0`，没有性能依据。
3. 不直接扩大 issue queue。先用仿真 A/B 证明更深队列能够减少总 cycles，而不只是降低 qfull 计数。
4. lane0→lane1 简单 ALU 同周期旁路具有潜在 IPC 收益，但当前 130 MHz 仅有 2 ps setup 余量；先做仿真上限实验，只有收益足以覆盖可能的 Fmax 下降才进入稳定 RTL。
5. 分支预测优化必须使用可预测分支和更接近真实程序的负载复核，不能针对伪随机 branch benchmark 过拟合。

## 下一阶段 L3F

优先进行不进入稳定 RTL 的仿真 A/B 实验：

1. 将 issue queue 深度参数化为 4/6/8，比较 cycles、IPC、queue 深度分布和 qfull；收益不明显则保留深度 4。
2. 建立“仅简单整数 ALU RAW”的理想 lane0→lane1 旁路实验，测量 ALU、BRANCH、MEMORY 三类负载的 IPC 上限。
3. 根据 130 MHz 当前 168.4 MIPS 基线计算允许的 Fmax 损失；若旁路后的 `IPC × Fmax` 上限不明显增加，则不进入综合。
4. 对分支负载增加规则循环、函数调用和短循环场景，与伪随机分支分开报告。
5. 每个有希望的实验先通过完整仿真回归，再交由云端做 130 MHz 时序门槛检查。

本阶段只增加 benchmark、生成镜像和 testbench 测量逻辑，不修改综合 CPU RTL，因此 L3D `6c77115` 仍是 130 MHz 硬件签核基线。
