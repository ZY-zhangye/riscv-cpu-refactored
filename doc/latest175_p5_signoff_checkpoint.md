# latest175 P5 实现签核检查点

## 版本范围

本检查点对应顺序双发 CPU 的 P5 RTL，目标器件与约束为：

```text
Device       xc7k325tffg900-2
CPU clock    175 MHz
Period       5.714 ns
```

P5 保留 P1–P4 已完成的控制路径流水化、异常控制隔离、BTB LUTRAM 化和 RAS 同周期地址闭环切断，并进一步缩短 IF lane1 地址计算、允许 Vivado 对高扇出的 `fs_pc` 进行物理复制。

曾评估的 load response 流水线 P6 已回退，不属于本检查点。P5 仍采用原有数据存储器响应协议，没有每次 load 额外等待周期。

## Vivado 实现结果

完整报告和检查点保存在本地忽略目录：

```text
vivado-project/jyd2025-reference/artifacts/latest175_p5
```

未生成 bitstream。

| 指标 | 普通实现 | `phys_opt_design -directive Explore` |
| --- | ---: | ---: |
| WNS | -0.951 ns | -0.817 ns |
| TNS | -232.238 ns | -213.840 ns |
| Setup failing endpoints | 913 / 29149 | 842 / 29149 |
| WPWS | +1.100 ns | +1.100 ns |
| TPWS | 0 | 0 |

物理优化相对普通实现改善 WNS 134 ps，TNS 减少 18.398 ns。最终路由状态为：

```text
Routable nets          25006
Fully routed nets      25006
Routing errors             0
```

## P5 物理效果

`fs_pc` 复制已在实现网表中实际发生：

- `fs_pc_reg[2]`：原寄存器外另有 6 个复制寄存器；
- `fs_pc_reg[3]`：原寄存器外另有 5 个复制寄存器；
- 单个复制后 Q 网的负载约为 23–31。

因此 P4 的 `fs_pc -> BTB lookup -> IROM1 address` 高扇出热点已明显下降。高扇出热点迁移到 `bp_update_pc_r` 和 BTB RAM 控制，最差 setup 路径迁移到 DRAM load response。

post-physopt 最差路径为：

```text
DRAM RAMB36E1 read clock
  -> perip_bridge / load-data select
  -> mem_stage load select
  -> exe_stage0 skid_mem_result_reg[25]/D
```

```text
Slack             -0.817 ns
Data path          6.053 ns
Logic              2.258 ns
Route              3.795 ns
Logic levels              7
```

前 20 条路径中主要是 DRAM BRAM read 到 MEM/EX/WB 的 load 数据路径，另有少量 EX/load-address 到 DRAM `WEA` 的控制路径。IF 剩余最差 slack 约为 -0.387 ns，不再是全局最差路径。

## RTL 与性能验证

P5 回退后使用 QuestaSim 重新验证：

```text
Full compile: 0 errors, 0 warnings
```

通过：

```text
tb_if_ras_recovery
tb_issue_stage
tb_mem_commit
tb_multi_issue_l2
tb_multi_issue_l3
tb_mul_special
tb_perf_counters
tb_my_cpu
```

P5 九窗口 benchmark 结果保持为：

```text
cycles       1,790,178
instret      2,279,455
IPC              1.273
sink        0x9D3BF787
exceptions           0
```

## 签核结论

P5 是当前最后一个经过完整 Vivado 综合、布局布线、post-route 物理优化和 Questa 回归验证的 RTL 检查点。它尚未满足 175 MHz setup 时序，但相较 P4 已将 IF 高扇出关键路径成功迁出最差路径。

后续若继续提高频率，应从 P5 分支重新开始，优先处理 DRAM read response 和 DRAM `WEA` 两组路径；任何增加 load 延迟的流水线方案都必须单独进行 IPC A/B，不应直接覆盖本签核点。
