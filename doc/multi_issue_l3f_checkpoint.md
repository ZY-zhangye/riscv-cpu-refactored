# 顺序多发 L3F queue 与同包 RAW 旁路仿真 A/B 检查点

> 状态更新：本页记录 L3F 当时的实验决策；`doc/multi_issue_l3p_125mhz_release.md` 已在 125 MHz 提交候选中默认启用完整简单 ALU 同包 RAW 旁路。

## 目标与边界

L3F 建立两类仿真实验，不改变默认综合配置：

- 临时 `L3F_QUEUE_DEPTH8` 配置将 issue queue 从 4 项扩展到 8 项；确认无吞吐收益后已从 RTL 撤销，只保留本检查点数据。
- `L3F_SAME_CYCLE_ALU_BYPASS`：允许两条经典 RV32I 简单 ALU 指令存在同包 RAW，并从 lane0 当前 ALU 结果直接旁路到 lane1。
- 在旁路宏基础上增加 `L3F_BYPASS_LOGIC_ONLY`，则只允许 lane1 为 AND/OR/XOR 类浅逻辑消费者。

所有宏默认关闭，因此 L3D `6c77115` 的 4 项 queue、禁止同包 RAW 的综合结构仍是硬件签核基线。

完成日期：2026-07-11

## 8 项 queue 实验

| 配置 | ALU cycles | BRANCH cycles | MEMORY cycles | 总 cycles | 总 IPC |
| --- | ---: | ---: | ---: | ---: | ---: |
| 默认 4 项 | 144,018 | 213,072 | 463,575 | 820,665 | 1.2956 |
| 实验 8 项 | 144,018 | 213,072 | 463,575 | 820,665 | 1.2956 |

8 项 queue 没有减少任何负载的执行周期，也没有提高 IPC。它只改变排队统计：

- ALU `qfull`：36,004 → 36,000。
- BRANCH `qfull`：36,002 → 15,619。
- MEMORY `qfull`：138,241 → 137,519。

结论：BRANCH 中较深 queue 能吸收更多 fetch packet，但队首依赖、控制流和下游消费率不变，因此吞吐完全不变。不能用 qfull 降低证明性能收益，稳定设计继续保持 4 项 queue。

## 完整简单 ALU 同包 RAW 旁路

旁路年龄规则为：同包 lane0 比上一包 EX/MEM 生产者更年轻，因此匹配时必须覆盖原有跨周期前递选择。第一版原型未给予同包结果最高优先级，导致 benchmark `sink` 改变；修正年龄优先级后 `sink=0xF5B4D4AE` 与基线一致。

| 负载 | 基线 IPC | 完整旁路 IPC | cycles 变化 | IPC 变化 |
| --- | ---: | ---: | ---: | ---: |
| ALU | 1.4999 | 1.7998 | -16.66% | +20.00% |
| BRANCH | 1.1544 | 1.3010 | -11.26% | +12.69% |
| MEMORY | 1.2970 | 1.2970 | 0 | 0 |
| 合计 | 1.2956 | 1.3761 | -5.85% | +6.21% |

完整旁路在 130 MHz 下约为 178.9 MIPS；若只能运行 125 MHz，仍约为 172.0 MIPS，比当前 130 MHz 基线 168.4 MIPS 高约 2.1%。其吞吐盈亏平衡频率约为 122.4 MHz。

该路径会形成 lane0 ALU → 跨 lane 旁路 → lane1 ALU 的同周期组合链。当前 L3D @130 MHz setup 余量只有 2 ps，因此 6.21% IPC 收益不能直接等价为最终吞吐收益，必须以后路由 Fmax 验证。

## 仅浅逻辑消费者旁路

| 指标 | 基线 | 逻辑消费者旁路 |
| --- | ---: | ---: |
| 总 cycles | 820,665 | 796,665 |
| 总 IPC | 1.2956 | 1.3346 |
| IPC 提升 | — | 3.01% |
| 130 MHz 吞吐 | 168.4 MIPS | 173.5 MIPS |
| 125 MHz 吞吐 | — | 166.8 MIPS |
| 盈亏平衡频率 | — | 126.2 MHz |

该限制把组合链的 lane1 端收窄为 AND/OR/XOR，但只保留约一半 IPC 收益。若频率从 130 MHz 降到 125 MHz，其吞吐反而低于当前基线，因此不值得单独进入云端综合。

## 验证

默认宏关闭配置：

- 全部 RTL/testbench 编译：Errors 0，Warnings 0。
- `tb_issue_stage`：通过。
- `tb_multi_issue_l2`：通过。
- `tb_multi_issue_l3`：通过，保持 27 cycles、IPC 1.259。
- L3E benchmark：通过，保持 820,665 cycles、IPC 1.2956、`sink=0xF5B4D4AE`。

完整旁路实验配置：

- 全部 RTL/testbench 编译：Errors 0，Warnings 0。
- `tb_issue_stage`：通过，确认经典 ALU RAW 可双发，load→ALU、ALU→branch 和 ALU→bitman 仍保持阻塞。
- `tb_multi_issue_l2`：通过。
- `tb_multi_issue_l3`：通过，26 cycles、34 instret。
- L3E benchmark：通过，772,665 cycles、IPC 1.3761，`sink=0xF5B4D4AE`。

Questa 在 divider 初始化时仍有两条既有除零警告，不影响结果。

## 决策

1. 8 项 queue 实验终止，不进入稳定综合配置。
2. 仅逻辑消费者旁路实验终止，其 125 MHz 等效吞吐低于当前 130 MHz 基线。
3. 完整简单 ALU 旁路保留为唯一候选，但默认关闭。
4. L3D 125 MHz 稳健档已以 setup WNS +0.178 ns、TNS 0 完成签核。该余量不足以证明新增双 ALU 组合链仍能通过 125 MHz。
5. 旁路候选只有在 post-route Fmax 高于约 122.4 MHz 时才具备理论净收益；由于当前 PLL 采用 5 MHz 步进，工程上必须直接通过 125 MHz，120 MHz 已低于盈亏平衡点。
6. 完整旁路在 125 MHz 下相对当前 130 MHz benchmark 基线只增加约 2.1% 吞吐，L3 微基准则基本持平。暂不占用云端综合轮次，不进入稳定基线。
7. 下一阶段转向不增加 EX 双 ALU 组合深度的分支预测仿真优化；旁路宏保留为可复现实验，只有后续负载继续证明 RAW 是压倒性瓶颈时才重新评估。
