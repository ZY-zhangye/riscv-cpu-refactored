# 顺序多发 L3O issue packet 写入路径切分检查点

## L3N 150 MHz recovery 结果

- 输入提交：`4d44da5`；
- 报告目录：`vivado-project/jyd2025-reference/reports/L3N_4d44da5_150MHz_stress`；
- setup WNS -0.732 ns、TNS -424.345 ns；
- setup 失败端点 2,251；
- hold WNS +2.691 ns、TNS 0；
- 36,080 / 36,080 可路由网络完成，0 路由错误；
- 19,698 LUT、22,188 FF、64 BRAM Tile、8 DSP。

## 结果判断

L3N 的 issue 主修改有效：L3M 中 17 条
`ds_to_es_bus_r_reg[4] → queue2/3 CE/D` redirect/物理移位路径已完全退出
前 20。

但 DRAM WEA 实验产生明显回退：

| 指标 | L3M | L3N |
| --- | ---: | ---: |
| WEA WNS | -0.354 ns | -0.732 ns |
| 数据路径 | 6.061 ns | 6.591 ns |
| 逻辑 | 0.908 ns | 0.818 ns |
| 路由 | 5.153 ns | 5.773 ns |

移除冗余 `perip_wen` 虽减少约 90 ps 逻辑，却使物理路由增加约 620 ps，
净回退 378 ps。该修改不满足 `IPC × Fmax` 原则，L3O 直接恢复 L3M 的：

```text
dram_wen = perip_wen & dram_region_sel
```

不再依据逻辑级数推测该路径会改善。

## 新 issue 路径

L3N 前 20 中出现 9 条新的 EX0 数据依赖路径：

```text
exe_stage0/mem_result_reg_reg[1]
  → JALR/branch redirect
  → issue is_allowin / packet 接收控制
  → queue0/2 payload、queue_info CE/D
```

- WNS -0.590~-0.520 ns；
- 18 级逻辑；
- 8 个 CARRY4；
- 路由约占 72%。

这不是 L3M 已移除的物理消费/移位锥，而是 redirect 仍通过
`is_allowin = global_flush || capacity_allow` 和带 flush 掩码的 packet 接收
条件决定宽 payload 是否写入。

## L3O 修改

显式拆分架构 allowin 与物理 packet 写入：

- `capacity_allow` 只由队列容量和正常消费数量产生；
- 对 IF 的 `is_allowin` 仍为 `global_flush || capacity_allow`，保证 redirect
  拍前端能够恢复；
- 内部 `packet_write = fs_to_is_valid0 && capacity_allow`，不依赖
  `global_flush`；
- flush 拍最终仍强制 `queue_count=0`、重置下一包 tag。

非 flush 周期行为与原设计完全一致。flush 周期可能对无效 payload 做一次
物理写入，但 count 同拍清零，因此不会被 issue、提交或性能计数观察到。

配合 L3N 的未掩码物理消费条件，redirect 现在只控制有效计数与对外 valid，
不再控制 queue payload/queue_info 的移位或写入 CE/D。

## 验证

- CPU/SoC RTL 与 testbench 编译：Errors 0、Warnings 0；
- 板级 `perip_bridge` 编译：Errors 0、Warnings 0；
- `tb_issue_stage`：通过；
- `tb_mem_commit`：通过；
- `tb_multi_issue_l2`：通过；
- `tb_multi_issue_l3`：通过，27 cycles、34 instret、IPC 1.259、branch miss 2；
- `tb_perf_counters`：通过；
- `tb_dram_driver`：通过。

## 下一轮云端实现

先沿用 L3N 相同的 150 MHz recovery flow，不增加特殊 directive。

重点确认：

1. `mem_result_reg_reg[1] → queue0/2 CE/D` 九条路径是否消失；
2. WEA 门控恢复后，其路径结构和 WNS 是否回到接近 L3M；
3. 新前 20 是否由 MEM→ID hazard 或其他独立路径主导；
4. 同时记录 setup/hold、失败端点、路由和资源。

若恢复门控后 WEA 仍显著劣于 L3M，再基于新报告进行 placement/physopt
A/B；不继续改变访存协议或增加访存周期。
