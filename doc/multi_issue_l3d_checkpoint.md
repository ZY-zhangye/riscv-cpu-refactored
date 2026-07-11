# 顺序多发 L3D issue payload flush 扇出清理检查点

## 背景

L3C `0a3a08c` 的 Vivado 2023.2 后路由结果确认，原 `mem_stage → DRAM BRAM ENARDEN` 路径已经消失。175 MHz 约束下 WNS 为 -1.754 ns、TNS 为 -5,121.279 ns，推导 Fmax 约 133.9 MHz，建议运行点为 130 MHz；LUT 13,528、FF 15,038、BRAM 64、DSP 8。

新的最差路径为：

```text
u_exe_stage1/ds_to_es_bus_r_reg[1]
  → u_issue_stage/queue0_reg[80]/CE
```

该路径数据延迟 7.077 ns、15 级逻辑，布线占 82.0%。分析 RTL 后确认，EX redirect/exception 形成的 `global_flush` 会同步清零 issue queue 的全部 payload、packet tag 和预译码信息，使 EX 控制信号扇出到四个队列槽的大量寄存器 CE/D 输入选择逻辑。

完成日期：2026-07-11

## RTL 修改

redirect 或 exception 发生时，issue stage 现在只执行：

```systemverilog
next_queue_count = 3'd0;
next_next_packet_tag = 1'b0;
```

不再清零 `queue0..queue3`、各槽 packet tag 和预译码 payload。理由如下：

- `queue_count=0` 后所有槽位都无效，残留 payload 不具备架构可见性。
- 后续入队会根据有效槽位覆盖对应 payload、tag 和预译码信息。
- reset 路径仍完整清零全部状态，仿真和上电初态不变。
- 顺序发射、flush 语义、同周期出入队和 packet tag 生成规则均未改变。

该修改的目标是从 queue payload 寄存器上移除 EX redirect 的高扇出清零控制；它不增加流水级，也不改变 IPC 或取指恢复延迟。

## 验证

`tb_issue_stage` 新增 flush 后重新入队两条新指令的检查，确认旧 payload 即使物理留存，也不会重新成为有效指令。

完整结果：

- QuestaSim 2024.1 编译：Errors 0，Warnings 0。
- `tb_perf_counters`、`tb_issue_stage`、`tb_mem_commit`、`tb_multi_issue_l2`、`tb_multi_issue_l3`、`tb_dram_driver`：全部通过。
- L3 微基准保持 27 周期、34 条提交、IPC 1.259；跨 packet 配对 3 次、bitman 配对 2 次、分支误预测 2 次。
- `run_all.bat all`：6 个单元/专项测试通过，77/77 ISA 用例通过。
- 完整回归在 `F:\Tools` 下的隔离 worktree 执行，用户 HEX 未被覆盖。

## 175 MHz 后路由结果

L3D `6c77115` 在 175 MHz 约束下完成后路由：WNS -1.747 ns、TNS -4,794.079 ns。原 L3C 的 flush payload 路径退出关键路径簇，最差路径迁移到 `mem_stage0/es_ms_bus_r_reg[92] → DRAM BRAM WEA[0]`。这说明本阶段修改达到目标，但 175 MHz 仍明显超出当前设计的可实现频率。

## 130 MHz 阶段签核

服务器随后使用实际 130 MHz PLL、50/130 MHz 异步时钟组约束和后路由 `phys_opt_design -directive Explore` 完成签核：

- CPU setup WNS +0.002 ns、TNS 0、失败端点 0。
- CPU hold WNS +3.204 ns、TNS 0。
- 24,444 条网络全部完成路由，0 路由错误。
- 最差路径为 `u_exe_stage1/ds_to_es_bus_r_reg[3] → u_issue_stage/queue3_reg[71]/CE`，数据路径 7.251 ns，布线占 75.6%。
- 前 20 条路径均为正裕量，范围 +0.002 ns 至 +0.032 ns。
- IPC 保持 1.259，按 130 MHz 估算吞吐约 163.7 MIPS。

完整报告见 `vivado-project/jyd2025-reference/reports/L3D_130MHz_physopt/L3D_130MHz_signoff_analysis.md`。

由此将 L3D @130 MHz 定义为本阶段最高性能签核版本。2 ps setup 余量满足本次工具流的签核条件，但不具备充足的实现扰动余量；需要更高鲁棒性时使用 125 MHz。当前不再寄存化整个 LSU/DRAM 请求边界，因为 DRAM `WEA` 已不再是 130 MHz 最差路径，修改访存协议的风险大于收益。

## 125 MHz 稳健档签核

服务器使用实际 125 MHz PLL（8.000 ns）、50/125 MHz 异步时钟组约束和后路由物理优化完成复核：

- CPU setup WNS +0.178 ns、TNS 0、失败端点 0。
- CPU hold WNS +3.358 ns、TNS 0。
- 24,427 / 24,427 条可路由网络完成，0 路由错误。
- 最差路径为 `mem_stage0/es_ms_bus_r_reg[90] → DRAM BRAM WEA[0]`。
- 数据路径 7.134 ns，其中逻辑 0.739 ns（10.4%）、布线 6.395 ns（89.6%）。
- 未生成 bitstream。
- 按 L3 微基准 IPC 1.259 估算，吞吐约 157.4 MIPS。

由此正式定义双频档：125 MHz 是具有明确正余量的稳健签核档；130 MHz 是 WNS 仅 +0.002 ns 的最高性能签核档。125 MHz 下 WEA 再次成为最差路径属于布局布线和约束点变化后的路径迁移，但该频点已经通过，不构成修改访存协议的理由。

后续若继续提高频率或扩大签核余量，应以 `IPC × Fmax` 为准。正常 issue queue CE 与 DRAM WEA 都具有较高布线占比，不恢复 payload flush 清零，也不为单条随实现迁移的路径盲目增加流水级。
