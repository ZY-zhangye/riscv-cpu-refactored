# 顺序多发 L3C 板级 DRAM 使能路径检查点

## 背景

L3B `57f4074` 的 Vivado 2023.2 后路由报告确认：原 `exe_stage → perf_issue_qfull_reg/CE` 路径已经消失，但 WNS 仍约为 -2.199 ns，推导 Fmax 约 126.4 MHz。新的最差路径为：

```text
mem_stage1/es_ms_bus_r_reg[97]
  → perip_bridge/dram_driver/u_dram/ENARDEN
```

该路径数据延迟 7.257 ns，其中布线占 88.7%。这说明当前瓶颈位于 CPU 到板级 DRAM BRAM 使能的跨层级物理路径，而不是多发 issue 逻辑。

完成日期：2026-07-11

## 设计决策

### 不增加返回数据寄存器

CPU、板级 `perip_bridge` 和 DRAM BRAM 当前共同实现固定单周期读取：周期 N 发地址/读请求，周期 N+1 返回数据。`blk_mem_gen_0` 的 `READ_LATENCY_A=1`。

在 `douta/perip_rdata` 上再增加寄存器会把 load 响应改为两周期，而 CPU 没有 response-valid 或 wait-state 握手，MEM 会消费旧数据。同时，L3B 关键路径终点是 `ENARDEN`，寄存返回数据也无法切断请求使能路径。

### BRAM 常使能

板级 `dram_driver` 修改为：

```systemverilog
assign dram_we = perip_mask & {4{dram_wen}};

blk_mem_gen_0 u_dram (
    .ena (1'b1),
    .wea (dram_we),
    ...
);
```

效果：

- 删除 CPU 访存请求到 BRAM `ENARDEN` 的组合控制路径。
- 保持 BRAM 地址与同步读数据时序不变，load 延迟仍为一周期。
- 写掩码显式受 `dram_wen` 门控，MMIO 写即使携带非零 `perip_mask` 也不会误写 DRAM。
- 字节、半字和整字 store 继续使用原有四位写掩码。
- 代价是 BRAM 端口持续使能，动态功耗可能略有增加。

## 验证

新增 `tb_dram_driver`，使用一周期同步 BRAM 仿真模型覆盖：

- `ena` 固定为高。
- 一周期同步读取保持正确。
- `dram_wen=0` 时非零 `perip_mask` 不会修改 DRAM。
- `dram_wen=1` 时字节写掩码正确生效。
- 写后读取返回更新后的数据。

完整结果：

- QuestaSim 2024.1 编译：Errors 0，Warnings 0。
- `tb_dram_driver`：通过。
- 原有 `tb_perf_counters`、`tb_issue_stage`、`tb_mem_commit`、`tb_multi_issue_l2`、`tb_multi_issue_l3`：全部通过。
- L3 微基准保持 27 周期、IPC 1.259。
- `run_all.bat all`：6 个单元/专项测试通过，77/77 ISA 用例通过。
- 回归在隔离 worktree 执行，用户 HEX 与 Vivado 报告未被覆盖。

## 后路由结果

L3C `0a3a08c` 已完成 Vivado 2023.2 综合、布局和布线：

- LUT 13,528、FF 15,038、BRAM 64、DSP 8。
- 175 MHz 约束下 WNS -1.754 ns、TNS -5,121.279 ns。
- 推导 Fmax 133.9 MHz，按 5 MHz 向下取整的建议频率为 130 MHz。
- 原 `mem_stage → DRAM BRAM ENARDEN` 最差路径已经消失。
- 新最差路径迁移为 `u_exe_stage1/ds_to_es_bus_r_reg[1] → u_issue_stage/queue0_reg[80]/CE`，数据延迟 7.077 ns、15 级逻辑，布线占 82.0%。

完整分析见 `vivado-project/jyd2025-reference/reports/L3C_0a3a08c_final/L3C_full_vivado_analysis.md`。该结果确认 BRAM 常使能修改达成目标；后续由 L3D 清理 EX redirect 对 issue queue payload 的高扇出清零路径。

原定验收项结果如下：

1. `ENARDEN` 路径已经消失。
2. 新关键路径未转移到 BRAM 地址或写使能，而是 issue queue payload CE。
3. hold WNS 为正、hold TNS 为 0；130 MHz 是依据 175 MHz 结果推导的建议运行点，仍应在实际 130 MHz 约束下复跑确认。
4. 按 IPC 1.259 与 130 MHz 估算，吞吐约 163.7 MIPS。
5. BRAM 仍为 64，DSP 仍为 8，资源变化很小。
