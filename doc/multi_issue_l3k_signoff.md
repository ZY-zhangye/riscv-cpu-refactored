# 顺序多发 L3K 双频后路由签核

## 冻结对象

- RTL 签核源提交：`6760658`（`timing: pipeline L3K BTB update request`）
- 分支：`codex/multi-issue-inorder`
- CPU：2-wide 顺序多发、128 项直接映射 BTB、2-bit 方向计数、JALR BTB 预测、8-depth 提交态/推测态 RAS
- BTB 更新：IF 本地寄存一拍后写表
- Vivado：2023.2
- 器件：xc7k325t-ffg900-2
- 实现流程：高 QoR placement/route + post-route physical optimization
- 报告目录：`vivado-project/jyd2025-reference/reports/L3K_6760658_highq_physopt`

签核日期：2026-07-11

## 双频结果

| 主频 | CPU setup WNS | TNS | setup 失败端点 | hold WNS | 结论 |
| --- | ---: | ---: | ---: | ---: | --- |
| 125 MHz | +0.060 ns | 0 | 0 / 39,474 | +3.358 ns | 稳健档签核 |
| 130 MHz | +0.044 ns | 0 | 0 / 39,500 | +3.204 ns | 性能档签核 |

两档均完成全部路由，0 路由错误。CPU 与 50 MHz UART 域继续由异步时钟组排除，不作为同步路径计时。

两档 setup/hold 均满足硬时序要求，但裕量仍窄。这里的“稳健档”表示相对 130 MHz 保留 5 MHz 频率余量，并不表示拥有数百 ps 的宽松工程裕量；未来 RTL、约束或实现流程变化后必须重新签核。

## 资源

| 主频 | LUT | FF | BRAM Tile | DSP |
| --- | ---: | ---: | ---: | ---: |
| 125 MHz | 19,094 | 22,215 | 64 | 8 |
| 130 MHz | 19,150 | 22,228 | 64 | 8 |

资源差异来自两次高 QoR 实现的物理优化结果，架构配置一致。

## 关键路径

125 MHz：

```text
exe_stage1/ds_to_es_bus_r_reg[4] → DRAM BRAM WEA[0]
```

- 数据路径 7.234 ns；
- 路由占 83.6%。

130 MHz：

```text
mem_stage0/es_ms_bus_r_reg[95] → DRAM BRAM WEA[0]
```

- 数据路径 6.937 ns；
- 路由占 87.5%。

原 L3H 的 `MEM/flush → bp_counter/D` 路径簇已消失。当前双频最差路径均属于 CPU→DRAM BRAM 写使能的物理路由，而不是 BTB、RAS 或 next-PC 逻辑。

## 性能与功能基线

L3J 默认仿真配置与签核 RTL 一致：

- 九窗口 cycles 1,763,327；
- instret 2,279,453；
- IPC 1.292；
- CAPACITY 误预测 1,150；
- RETURN 误预测 11；
- `sink=0x9D3BF787`；
- exceptions=0。

L3 微基准保持 27 cycles、34 instret、IPC 1.259。完整编译、性能计数单测、issue/L2/L3 和 benchmark 回归均已通过。

## 签核决定

1. L3K 作为当前顺序 2-wide 稳定基线封存。
2. 125 MHz 为稳健运行档；130 MHz 为当前性能档，无需因 128 项 BTB 或 RAS 降频。
3. 后续实验不得覆盖本签核基线；每个新阶段保留独立提交和可回退宏。
4. 当前不改变访存协议，不为提高少量 WNS 直接增加 load/store 延迟。
5. 下一主线转为专门的时序优化与 Fmax 提升；架构性能实验作为其后的独立阶段。

## 下一阶段计划

### T1：建立高频压力实现基线

1. 固定 L3K RTL、XDC、高 QoR directives 和报告脚本。
2. 在 135/140 MHz 运行压力实现，用前 20 条路径簇确定真实 Fmax 限制；压力频点只用于定位，不作为失败回退依据。
3. 每档记录 WNS/TNS、失败端点、hold、逻辑/路由比例、资源和路径重复度。

完成门槛：得到稳定、可重复的路径簇排名，而不是依据单条最差路径修改 RTL。

### T2：CPU→DRAM WEA 专项物理优化

优先保持协议和周期数不变：

1. 追踪 `WEA` 的完整逻辑锥，区分 store 类型译码、地址选择、提交允许和异常屏蔽各自贡献。
2. 评估层次扁平化、局部寄存器复制、控制信号本地化、扇出拆分和 placement/pblock。
3. 把 WEA 控制与宽数据 payload 的无关层次解耦，减少跨 CPU/bridge/BRAM 的远距离布线。
4. 每次只改一个物理或逻辑因素，并在 125/130 MHz 回归；达到 135 MHz 后再尝试更高频点。

完成门槛：`IPC × Fmax` 提高，且 125/130 MHz 不回退。

### T3：最后手段的访存接口分级

只有 T2 多轮仍被同一 WEA 路径限制时才评估：

1. 在 bridge/DRAM 边界增加明确的请求寄存级或局部 store command register。
2. 保持 MMIO、异常、精确 store 提交和读返回时序一致；若延迟变化，必须同步更新仿真模型和 hazard。
3. 重新运行完整 ISA、访存、异常、中断与性能回归。

该阶段风险较高，不在下一对话开始时直接实施。

### P1：时序稳定后的性能主线

1. 拆分 MEXT 的 mul 与 div/rem 窗口，归因 136,000 个 EX stall。
2. 获取真实测评程序动态 trace；静态指令比例不直接作为 IPC 权重。
3. 再决定流水化乘法接受率、分支恢复气泡或 store buffer 的优先级。
4. 同包 ALU RAW 旁路继续保留为默认关闭候选，除非新的动态画像证明收益足以覆盖时序成本。

## 下一对话入口

从提交 `6760658` 的签核 RTL继续，先执行 T1 高频压力实现分析。不要重新修改 BTB/RAS，也不要先增加访存流水级。首个问题应是：135/140 MHz 前 20 条失败路径是否仍集中在 DRAM `WEA`，以及这些路径是否共享同一控制锥和物理区域。
