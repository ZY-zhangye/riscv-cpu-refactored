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

## 后路由验收

下一次 Vivado 综合、布局和布线应重点确认：

1. `EXE → queue payload CE` 路径从最差路径簇中消失。
2. queue payload 寄存器不再由 redirect/exception 高扇出控制；若仍存在同类路径，应检查综合是否把 count 有效性重新传播成 payload CE。
3. 在 130 MHz 约束下达到 `WNS >= 0`、`TNS = 0`，并检查 hold timing；同时尝试 135 MHz。
4. BRAM 保持 64、DSP 保持 8，LUT/FF 变化应很小。
5. 继续使用 IPC 1.259 计算 `IPC × Fmax`，确认吞吐提升没有以 IPC 回退为代价。

若关键路径迁移到真正的 queue 出入队数据搬移或 allowin 组合网络，再按新报告决定是否改为环形队列/局部写使能；本阶段不加入同周期旁路或 store buffer。
