# 顺序多发 L3N issue 物理移位路径切分检查点

## L3M 150 MHz 压力结果

- 输入提交：`0b1e80a`；
- 报告目录：`vivado-project/jyd2025-reference/reports/L3M_0b1e80a_150MHz_stress`；
- setup WNS -0.354 ns、TNS -134.475 ns；
- setup 失败端点 1,091 / 39,392；
- hold WNS +2.691 ns、TNS 0；
- 35,932 / 35,932 可路由网络完成，0 路由错误；
- 19,468 LUT、22,172 FF、64 BRAM Tile、8 DSP。

相较 L3L，WNS 改善 0.182 ns，TNS 减少 218.390 ns。L3M 检查点
预期移除的 `br_redirect → fs_to_ds_valid* → issue queue CE` 已不再出现。

## 前 20 条路径归因

1. 一条 EX0 地址计算到 DRAM BRAM `WEA[0]`，WNS -0.354 ns，路由占
   85.018%；
2. 十七条 EX0 分支 redirect 到 issue queue2/3 payload、预译码 CE/D，
   WNS -0.346~-0.301 ns，20 级逻辑，路由约占 72%；
3. 两条 MEM0 load/异常/hazard 到 ID1 payload CE，WNS -0.298 ns，路由占
   88.338%。

## Issue 路径根因

L3L 已移除 `global_flush` 对队列 next-state 外层分支的直接控制，但
`consume_count` 仍来自带 flush 掩码的 `lane*_fire`：

```text
br_redirect
  → is_to_ds_valid*=0
  → lane*_fire=0
  → consume_count
  → queue shift selection
  → queue2/3 payload、queue_info CE/D
```

flush 最终会把 `queue_count` 清零，因此该拍 payload 是否物理移位不影响
任何有效架构状态。

## L3N 修改

新增未受 flush 掩码的内部物理移位条件：

- `lane0_shift = buf_valid0 && ds_bundle_allowin`；
- `lane1_shift = can_pair && ds_bundle_allowin`；
- `consume_count` 由 `lane*_shift` 产生。

对外 valid、真实 issue/commit 事件及所有性能计数仍使用带
`global_flush` 掩码的 `lane*_fire`。非 flush 周期两组条件完全一致；flush
周期只允许无效 payload 做无观察意义的移位，随后 `queue_count` 清零。

这样把 EX redirect 从宽队列 payload/预译码更新锥中移除，同时保留原有
flush、程序序和性能计数语义。

## DRAM WEA 局部清理

板级 wrapper 中 `perip_wen` 等于 `|perip_mask`，而 `dram_driver` 已逐位用
`perip_mask` 门控 BRAM WEA。L3N 的 `dram_wen` 输入只保留
`dram_region_sel`，移除 `perip_wen` 的冗余重汇合逻辑；MMIO 地址仍因
`dram_region_sel=0` 而不会写入 DRAM。

该修改不增加寄存级，不改变地址、写 mask、写数据或访存周期。

## 验证

- CPU/SoC RTL 与全部 testbench 编译：Errors 0、Warnings 0；
- 板级 `perip_bridge` 编译：Errors 0、Warnings 0；
- `tb_issue_stage`：通过；
- `tb_mem_commit`：通过；
- `tb_multi_issue_l2`：通过；
- `tb_multi_issue_l3`：通过，27 cycles、34 instret、IPC 1.259、branch miss 2；
- `tb_perf_counters`：通过；
- `tb_dram_driver`：通过。

## 下一轮云端实现

沿用 L3M 相同的 150 MHz stress/recovery flow，不需要特殊综合 directive。
若 post-route physopt 再次异常，可继续从本提交的 post-synthesis checkpoint
重新执行 opt/place/route/physopt 恢复流程。

重点确认：

1. 十七条 EX redirect → issue queue2/3 CE/D 路径是否消失；
2. DRAM `WEA` 是否因冗余门控移除而改善；
3. 新的前 20 条是否由 MEM→ID hazard、其他 issue 路径或独立物理路径主导；
4. 同时报告 setup/hold、失败端点、路由状态和资源。
