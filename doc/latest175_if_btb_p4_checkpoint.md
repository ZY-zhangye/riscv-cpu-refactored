# latest175 Post-Route IF/BTB P4 Checkpoint

## latest175 实现基线

报告目录：

```text
vivado-project/jyd2025-reference/artifacts/latest175
```

器件 `xc7k325tffg900-2`，CPU 约束 `175 MHz`。报告为完整 routed design，不是 quick synth。

| 阶段 | WNS | TNS | failing endpoints |
| --- | ---: | ---: | ---: |
| Synth | -0.773 ns | -81.016 ns | 514 |
| Post-route | -1.162 ns | -642.603 ns | 2625 |

Post-route hold `WHS +0.072 ns`、`THS 0`；全部 34,250 条可布线 net 已完成，无 routing error、unrouted net 或 node overlap。

资源：

```text
Slice LUTs       19,062 (9.35%)
Slice Registers  22,581 (5.54%)
BRAM tiles           72 (16.18%)
DSPs                  8 (0.95%)
```

## 当前最差路径

Post-route 最差路径：

```text
u_if_stage/fs_pc_reg[2]_rep
  -> u_irom1 RAMB36E1/ADDRARDADDR[13]
```

```text
Data path      6.056 ns
Logic          1.981 ns
Route          4.075 ns
Logic levels          12
Clock skew    -0.251 ns
Slack         -1.162 ns
```

该路径包括：

```text
fs_pc + 4
  -> lane1 128-entry BTB lookup/tag compare
  -> next_pc target selection
  -> lane1 fetch address + 4
  -> IROM1 BRAM address
```

综合级最差路径则从 IROM1 BRAM 输出开始：

```text
IROM1 instruction data
  -> lane1 return instruction decode
  -> RAS target selection
  -> next_pc / lane1 +4
  -> IROM1 BRAM address
```

这说明 P3 已经消除 MEM exception feedback；当前主问题是同步 IROM 的 Q->prediction->A 单周期闭环，以及旧 BTB FF 阵列产生的 128:1 mux/高扇出布线。

前 20 中另有两条后续候选：

```text
DRAM BRAM read -> EX1 mem_result1_reg/D   -1.020 ns
DRAM BRAM read -> WB1 ms_ws_bus_r/D       -0.977 ns
```

IF 修复后如果它们升到最前，需要再单独处理 load response/forwarding 边界。

## P4 RTL 修改

### 128-entry BTB 分布式 RAM

保持 128 项、2-bit counter、tag、target 和双组合查询不变。旧数组全部带逐项 reset，Vivado 只能实现为数千 FF 与宽 mux。P4 改为三份 1R1W 分布式 RAM：

```text
bp_mem_lookup0  lane0 read + update write
bp_mem_lookup1  lane1 read + update write
bp_mem_update   update-state read + update write
```

三份 payload 同步写入；每份 valid bitmap 独立复位。payload 无复位，invalid 时为 don't-care，从而允许 `ram_style="distributed"` 推断。

BTB 表项增加 `is_return`，宽度为：

```text
counter[1:0] + is_return + tag + target[31:0]
```

### RAS 返回类型元数据

RAS 预测现在使用：

```text
ras_nonempty && btb_hit && btb_entry.is_return
```

不再直接从当拍 IROM 指令数据译码 return 后反馈到 IROM address。指令译码仍保留用于 packet 被接受时的推测 RAS push/pop，不改变栈状态语义。

首次遇到尚未训练或刚被冲突替换的 return 时，BTB 没有类型元数据，会多一次冷 miss；稳定返回仍由 RAS 提供目标。

### lane1 PC 计算隔离

BTB lane1 word-PC increment 与 issue packet 中的 `PC+4` 分开计算，避免综合共享一个扇出接近千级的加法结果。

## RTL 与性能验证

全 RTL/testbench 编译：`Errors 0, Warnings 0`。

通过：

```text
tb_if_ras_recovery
tb_multi_issue_l2
tb_multi_issue_l3
tb_issue_stage
tb_perf_counters
tb_mem_commit
tb_my_cpu
```

L3 微基准保持 `30 cycles / 34 instret`。

九窗口 A/B：

| 指标 | P3 | P4 | 变化 |
| --- | ---: | ---: | ---: |
| cycles | 1,790,106 | 1,790,178 | +72 |
| instret | 2,279,454 | 2,279,455 | +1 |
| IPC | 1.273 | 1.273 | 无可见变化 |
| total mispredict | 19,389 | 19,401 | +12 |
| RETURN mispredict | 11 | 16 | +5 |

新增 12 次 miss 对应 72 cycles，即每次约 6 cycles。总周期变化约 `0.004%`，远小于缩小 BTB 或关闭 RAS 的既有损失。

sink 仍为 P1 起已存在的 `0x4A27AD51`，P4 未改变该结果。

## 下一轮实现检查

本阶段未运行 Vivado。下一轮请继续使用相同器件、175 MHz XDC 和实现策略，重点确认：

1. `bp_mem_lookup0/1/update` 是否推断为 LUTRAM/RAM primitive，而不是 FF 阵列；
2. BTB payload FF 与 128:1 mux 数量是否明显下降；
3. `IROM dout -> ras_return -> IROM address` 路径是否完全消失；
4. `fs_pc -> IROM address` 路径是否缩短并退出最差路径；
5. post-route WNS/TNS、clock skew 和 failing endpoints；
6. 若最差路径迁移到 DRAM read->EX/WB，保留完整路径报告作为下一阶段输入。
