# L3Q 125 MHz 性能候选矩阵

## 目标

在不依赖本机 Vivado 的条件下，为 125 MHz 提交版准备多组可独立综合的性能候选。所有结果使用同一份九窗口 benchmark，`sink=0x9D3BF787`、exceptions=0，九个窗口均一次完成。

## 硬件延迟修正

`multiplier.xci` 的 `C_LATENCY` 和 `PipeStages` 均为 6，原 RTL 的 `MUL_CYCLE=4` 会提前两拍解除 EX stall。DEBUG 仿真使用组合乘法，因而未暴露这个硬件风险。L3Q 将两份 defines 中的 `MUL_CYCLE` 对齐为 6。

divider XCI 为 35 拍 Radix-2，RTL 按 AXI `tvalid` 动态等待，因此没有固定周期正确性问题；DEBUG divider 只模拟 10 拍，benchmark 会低估真实硬件除法成本，但不影响各候选之间的相对配对收益。

## A/B 结果

所有配置均使用修正后的 6 拍乘法延迟。

| 配置 | Vivado/Questa defines | cycles | IPC | cycles 变化 | 预期时序风险 |
| --- | --- | ---: | ---: | ---: | --- |
| Q0 安全基线 | `L3P_DISABLE_ALU_BYPASS` | 1,765,323 | 1.291 | — | 最低 |
| Q1 M+简单整数配对 | `L3P_DISABLE_ALU_BYPASS`, `L3Q_MULDIV_SIMPLE_PAIR` | 1,751,323 | 1.301 | -0.79% | 低 |
| Q2 仅逻辑消费者旁路 | `L3F_BYPASS_LOGIC_ONLY` | 1,739,323 | 1.310 | -1.47% | 中低 |
| Q3 逻辑旁路 + M 配对 | `L3F_BYPASS_LOGIC_ONLY`, `L3Q_MULDIV_SIMPLE_PAIR` | 1,725,323 | 1.321 | -2.27% | 中低 |
| Q4 完整 ALU 旁路 | 无附加 define | 1,707,323 | 1.335 | -3.29% | 高 |
| Q5 完整旁路 + M 配对 | `L3Q_MULDIV_SIMPLE_PAIR` | 1,693,323 | 1.346 | -4.08% | 高 |

Q1 利用现有双 EX 中已经实例化的 lane1 乘除单元，让独立的简单整数与 M 指令同包启动。它只扩展 issue 预译码和配对类别，不新增结果旁路或运算组合链。MEXT 窗口单独减少 14,000 cycles，EX stall 数不变，收益来自把相邻独立指令与长操作的启动周期重叠。

Q2/Q3 只允许 lane1 AND/OR/XOR 消费 lane0 当前 ALU 结果。lane0 仍可能是加法或移位，因此不是零时序风险，但不会形成完整的“lane0 ALU + lane1 加法/移位”双深组合链。

## 淘汰实验

- 放开同包 WAW：功能通过，但 cycles 完全不变；WAW 计数与 RAW/结构阻塞重叠。
- `lane0 LSU + lane1 control`：功能通过，只减少 4 cycles，无工程价值。
- producer 和 consumer 都限定为 AND/OR/XOR：只减少 2,000 cycles（约 0.11%），收益不足。
- 更深 issue queue、扩大到 64 项 BTB：已有检查点证明对对应负载无 cycles 收益。

## 综合顺序

明天优先跑 Q0、Q1、Q3、Q4 四组 125 MHz 常规实现。Q0 给出乘法延迟修正后的真实时序基线；Q1 是首选低风险性能版；Q3 是收益/风险折中；Q4 保留作高收益对照。Q2 可由 Q3 去掉 `L3Q_MULDIV_SIMPLE_PAIR` 得到，只有 Q3 的 issue 路径异常时再单独跑。Q5 无需优先跑，因为其主要时序风险与 Q4 相同，先由 Q4 判断完整跨 ALU 旁路能否守住 125 MHz。

每组需要记录 WNS、TNS、失败端点、资源和前 20 条路径。尤其检查：

- Q1/Q3 是否出现 issue queue `can_pair`/预译码到 CE 或 D 的新路径；
- Q3/Q4 是否出现 lane0 `forward_ex_result0` 到 lane1 ALU 的新关键路径；
- multiplier 实例的真实 6 拍输出是否与 `mul_done` 对齐。
