# 顺序多发 L3M IF redirect 输出路径切分检查点

## L3L 150 MHz 压力结果

- 输入提交：`d42fbb4`；
- 报告目录：`vivado-project/jyd2025-reference/reports/L3L_d42fbb4_150MHz_stress`；
- setup WNS -0.536 ns、TNS -352.865 ns；
- setup 失败端点 1,611 / 40,069；
- 33,326 / 33,326 可路由网络完成，0 路由错误；
- 19,205 LUT、22,216 FF、64 BRAM Tile、8 DSP。

相较 L3K 150 MHz 的 WNS -0.800 ns、TNS -481.135 ns，L3L 的 WNS
改善 0.264 ns，TNS 减少 128.270 ns。DRAM BRAM `WEA` 已退出前 20 条
路径，说明板级 DRAM 高位译码达到了预期目的。

## 新关键路径

前 20 条主要从 EX lane0 分支条件计算出发，经：

```text
br_redirect
  → IF fetch_kill / fs_to_ds_valid*
  → issue incoming_count / packet update
  → queue1~queue3 payload 或 queue_info CE
```

最差路径：

- WNS -0.536 ns；
- 数据路径 6.650 ns；
- 15 级逻辑；
- 逻辑 1.198 ns、路由 5.452 ns（81.985%）。

L3L 已将 redirect 从 issue queue 内部 flush 更新锥移除，但 IF 仍用同一个
即时 `br_redirect` 组合关闭 `fs_to_ds_valid*`。issue stage 同时已经通过
`global_flush` 禁止该拍接收 packet，因此这层 IF 即时门控属于重复控制，
并重新把 EX 分支判断接回了宽队列 CE。

## L3M 修改

IF 输出不再组合依赖即时 `br_taken`：

1. `fetch_kill` 只保留 `br_taken_reg` 和 `exception_flag`；
2. `fs_out_inst` 的 NOP 替换只保留寄存后的 redirect 恢复拍；
3. 两路预测元数据不再用即时 `br_taken` 门控。

即时 redirect 拍仍由 issue stage 的 `global_flush` 同步禁止接收，当前及
队列内的年轻指令仍被清空。下一拍 `br_taken_reg` 继续产生原有恢复气泡，
因此不减少 flush 覆盖，也不改变恢复周期数。

## 仿真验证

- 全 RTL/testbench 编译：Errors 0、Warnings 0；
- `tb_issue_stage`：通过；
- `tb_mem_commit`：通过；
- `tb_multi_issue_l2`：通过；
- `tb_multi_issue_l3`：通过；
- L3 测量保持 27 cycles、34 instret、IPC 1.259、branch miss 2；
- `tb_perf_counters`：通过；
- `tb_dram_driver`：通过。

## 云端实现要求

下一轮先使用与 L3L 相同的 150 MHz stress 综合、placement、route 和
post-route physopt 设置，不增加特殊 directive，以保持单变量比较。

重点检查：

1. 前 20 条中是否仍存在 `br_redirect → fs_to_ds_valid* → issue queue CE`；
2. 新 WNS/TNS 和失败端点数量；
3. issue queue 路径消失后，关键路径是否转移到 BTB/RAS、EX/MEM、DRAM
   `WEA` 或其他独立路径簇；
4. 路由占比、重复端点和前 20 条路径的物理区域集中度。

只有普通 stress flow 仍被同一局部路径簇限制时，再考虑更强 physopt、
placement 或寄存器复制实验。
