# 顺序多发 L3K BTB 更新路径切分检查点

## L3H 后路由结果

L3H `17edf30` 的 128 项 BTB 在 125/130 MHz 均未通过时序：

| 主频 | WNS | TNS | 失败端点 |
| --- | ---: | ---: | ---: |
| 125 MHz | -0.539 ns | -53.809 ns | 235 / 38,699 |
| 130 MHz | -0.628 ns | -82.862 ns | 254 / 38,699 |

资源为约 18,272~18,282 LUT、21,548 FF、64 BRAM Tile、8 DSP。相较 L3G 的 13,273 LUT、15,040 FF，128 项异步双查询表主要以 LUT/FF 实现，面积增量明显。

完成日期：2026-07-11

## 关键路径判断

125 MHz 最差路径为：

```text
u_mem_stage1/es_ms_bus_r_reg[92]
  → exception/flush 与 bp_update_valid 组合网络
  → 128 项 counter 动态写选择
  → u_if_stage/bp_counter_reg[2][1]/D
```

- 数据路径 8.253 ns；
- 17 级逻辑；
- 逻辑 1.541 ns（18.7%）；
- 路由 6.712 ns（81.3%）。

前 20 条路径主要终止于不同 `bp_counter_reg[*]`，属于同一更新路径簇。130 MHz 也具有相同结构。

该路径不是“误预测恢复地址重新进入 BTB 查询后再选 next-PC”。现有 IF 已经具备：

- `fetch_kill = br_taken || br_taken_reg || exception_flag`，redirect 恢复期间不会把错误取指送入 issue；
- `next_pc` 中 `br_taken_reg/br_target_reg` 优先于 BTB/RAS 预测；
- redirect 拍的 `fs_out_inst` 被替换为 NOP。

因此屏蔽恢复目标预测的语义实际上已经存在。完全禁止误预测分支更新 BTB 虽能移除这条路径，却会丢失最需要的训练信息，不应采用。

## L3K 修改

在 IF 内新增一拍本地 BTB 更新寄存器：

```text
EX/flush → bp_update_*_r → 128-entry BTB write
```

寄存字段为 valid、PC、taken 和 target。BTB 表在下一拍消费本地请求；连续分支仍可每拍接收一个更新，不降低更新吞吐，只把单次训练延后一拍。

RAS 的提交态/推测态更新仍使用当前解析控制流，以保持 redirect 恢复语义；只有大容量 BTB 的 valid/counter/tag/target 写口被切断。

该修改预期移除路径前半段约 4.5 ns 的 MEM/exception/flush 组合与跨层布线，使剩余路径从 IF 本地寄存器出发。最终改善幅度仍必须以后路由结果确认。

## 仿真结果

更新延后一拍后，L3J 九窗口全部数据逐项保持不变：

- 总 cycles 1,763,327；
- instret 2,279,453；
- IPC 1.292；
- RETURN 误预测 11；
- CAPACITY 误预测 1,150；
- `sink=0x9D3BF787`；
- exceptions=0。

`tb_perf_counters`、`tb_issue_stage`、`tb_multi_issue_l2`、`tb_multi_issue_l3` 和 L3J benchmark 全部通过；RTL/testbench 编译 Errors 0、Warnings 0。

## 下一步

1. 云端以当前默认 128 项 BTB + RAS 配置重新运行 125/130 MHz。
2. 确认原 `MEM → bp_counter/D` 路径簇消失，并检查新最差路径是否变为 IF 本地 update register → BTB、RAS next-PC 或原 DRAM WEA 路径。
3. 若本地 update → BTB 仍超时，再把数组写法改为逐项 CE/局部译码或评估小型 RAM 化；当前先不同时做第二层结构改造。
4. 若 128 项最终仍不能保持有竞争力的 `IPC × Fmax`，使用 `L3H_BTB_16_ENTRIES` 独立回退，RAS 可继续保留。
