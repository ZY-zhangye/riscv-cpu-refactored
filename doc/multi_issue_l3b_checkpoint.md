# 顺序多发 L3B 时序清理检查点

## 背景

L3A 在 Vivado 2023.2、`xc7k325tffg900-2` 上的后路由结果显示：推导 Fmax 为 126.4 MHz，关键路径从 `exe_stage` 到 `perf_issue_qfull_reg[7]/CE`，数据路径 7.529 ns、18 级逻辑，布线占 77.2%。divider 已使用 35 拍 Radix-2 OOC IP，不再是关键路径。

本检查点的目标是切断性能观测路径，并简化四项 issue queue 的接收容量判断；不改变顺序多发语义、IPC、访存延迟或外设协议。

完成日期：2026-07-10

## 访存返回寄存评估

结论：本阶段不增加 DRAM/MMIO 返回数据寄存器。

原因如下：

- CPU load 接口定义为固定单周期响应：周期 N 发出地址/使能，周期 N+1 的 MEM 阶段消费 `dmem_rdata`。
- 仿真 SoC 的 `rtl/my_cpu/bridge.sv` 已寄存 RAM、IO、PLIC 返回数据及读目标。
- Vivado 板级 `perip_bridge.sv` 已寄存 `read_addr_d/read_valid_d`，明确实现 N 请求、N+1 响应。
- DRAM `blk_mem_gen_0` 配置为 `READ_LATENCY_A=1`。
- L2 的 `mem_stage → BRAM ENARDEN` 路径终点是 BRAM 请求使能，不是返回数据；单独寄存返回数据不能切断该路径。
- 再增加一拍返回寄存会把 load 延迟改为两周期，而当前流水线没有数据存储器 response-valid/wait-state 握手，会导致 MEM 使用旧数据。

若未来需要切断 BRAM 请求使能路径，应引入显式 LSU 请求/响应握手或额外 MEM 等待级，而不是只在返回端增加寄存器。

## RTL 修改

### qfull 性能事件寄存化

- `issue_queue_full_event` 不再直接由组合反压网络驱动 CSR 性能计数器。
- issue stage 在本地寄存 `queue_full_event_now`，对外事件延迟一拍。
- `perf_issue_qfull` 的计数含义仍是 queue 无法接收有效 fetch packet 的周期数，只改变观测时间，不改变 queue、IF 或 EX 的握手行为。
- 寄存器可由布局工具放在 issue queue 周边，切断到 CSR 32-bit 计数器的长布线和控制扇出。

### 四项 queue 接收判断简化

- 原实现使用 `queue_count - consume_count`、剩余空间计算和大小比较生成 `is_allowin`。
- L3B 根据固定深度 4，使用 `queue_count` 与本周期消费 0/1/2 条的显式 case 生成 `can_accept_one/can_accept_two`。
- 该修改避免在 EX 反压到 IF 的容量判断路径上推导通用减法/比较链。
- 同周期出队/入队能力和四项队列行为保持不变。

## 验证结果

- QuestaSim 2024.1 全 RTL 与全部 testbench 编译：Errors 0，Warnings 0。
- `tb_issue_stage`：通过，新增确认 qfull 事件在寄存后一拍出现。
- `tb_perf_counters`：通过。
- `tb_mem_commit`：通过。
- `tb_multi_issue_l2`：通过。
- `tb_multi_issue_l3`：通过，仍保持 `cycles=27`、`instret=34`、IPC=1.259、跨 packet 配对 3 次、bitman 配对 2 次、分支误预测 2 次。
- `run_all.bat all`：5 个单元/专项测试全部通过，77/77 ISA 用例通过。
- 完整回归在隔离 worktree 执行，用户 HEX 和 Vivado 报告目录未被修改。

## 云端后路由验收

本地没有 Vivado，功能验证通过后将提交推送到远端，由云端服务器重新执行综合、布局和布线。验收重点：

1. 原 `exe_stage → perf_issue_qfull_reg/CE` 路径应消失。
2. 125 MHz 约束下应达到 `WNS >= 0`、`TNS = 0`，并检查 hold timing。
3. 尝试 130 MHz，记录新 WNS/TNS、推导 Fmax 和关键路径。
4. 确认 LUT/FF 增量合理，BRAM/DSP 不变。
5. 继续使用 L3A IPC 1.259 计算 `IPC × Fmax`；若周期专项测试仍为 27 拍，则无需调整 IPC。

若新关键路径转移到真正的 queue allowin 或 BRAM 请求使能，再依据报告决定下一轮，不在本检查点加入同周期旁路或额外访存级。
