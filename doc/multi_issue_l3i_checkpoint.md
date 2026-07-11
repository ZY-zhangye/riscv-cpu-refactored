# 顺序多发 L3I 返回地址栈仿真检查点

## 目标与基准

L3G 的 JALR BTB 预测能处理单一稳定目标，但同一条 `ret` 被多个调用点共享时，直接映射 BTB 每个 PC 只能保存一个目标，会在不同返回地址之间反复覆盖。L3I 增加 `BRANCH_RETURN` 窗口，包含：

- 同一 helper 的四个直接静态调用点；
- 三层嵌套调用链；
- 嵌套链内部再次调用同一 helper。

该结构同时覆盖多调用点共享 `ret` 和连续嵌套返回。性能邮箱升级为 `L3I0`、version 4，共八个测量窗口、656 bytes，仍位于 `0x6000_0800`。

完成日期：2026-07-11

## 基线结果

基线使用 L3H 默认 128 项 BTB、2-bit 方向计数和 JALR BTB 预测，不启用 RAS：

| 指标 | 基线 |
| --- | ---: |
| RETURN branch | 136,002 |
| RETURN mispredict | 40,015 |
| RETURN cycles | 616,079 |
| RETURN instret | 760,025 |
| RETURN IPC | 1.233 |
| 八窗口总 cycles | 1,745,342 |
| 八窗口总 IPC | 1.2751 |

误预测数量与共享 helper 的动态返回次数高度吻合，证明剩余问题是返回目标选择，而不是 BTB 容量或方向计数。

## RAS 设计

8 深度返回地址栈支持标准 RISC-V link register `x1` 和备用 link register `x5`：

- call：JAL/JALR 且 `rd=x1/x5`；
- return：JALR、`rd=x0`、`rs1=x1/x5`、立即数为 0；
- 异常跳转时清空提交态和推测态 RAS；
- 普通 redirect 时从提交态恢复推测态，并纳入当前解析 call/return 的更新。

第一版只在 EX 解析 call/return 时 push/pop。它能改善直接多调用点，但连续嵌套返回会在前一条 `ret` 尚未到 EX 时读取旧栈顶，仍留下 16,011 次误预测。

最终实现分离两份小栈：

- 提交态 RAS 在 EX 确认的 call/return 上更新，作为恢复检查点；
- 推测态 RAS 在 IF bundle 被下游接受时预译码 call/return 并立即 push/pop，为连续返回提供正确栈顶；
- 误预测 redirect 将推测态恢复为“提交态 + 当前解析控制流”的状态，清除错误路径污染。

该方案不改变 BTB、方向计数器、EX 运算路径或程序可见状态。RAS 只提供返回预测目标，预测错误仍由现有精确 redirect 纠正。

## A/B 结果

| 指标 | 无 RAS | 8-depth RAS | 变化 |
| --- | ---: | ---: | ---: |
| RETURN mispredict | 40,015 | 11 | -99.97% |
| RETURN cycles | 616,079 | 456,063 | -25.97% |
| RETURN IPC | 1.233 | 1.666 | +35.1% |
| 八窗口总 cycles | 1,745,342 | 1,585,302 | -9.17% |
| 八窗口总 IPC | 1.2751 | 1.4038 | +10.10% |

剩余 11 次主要为冷启动阶段尚未训练的 call/loop 控制流，不再出现稳定重复的嵌套 `ret` 目标错误。两种配置均满足 `sink=0x7F6E7CB1`、八窗口 exceptions=0。

RAS 候选相对无 RAS 基线的吞吐盈亏平衡频率约 118.1 MHz。若只能通过 125 MHz，按 L3I 八窗口负载换算仍约 175.5 MIPS，高于无 RAS 在 130 MHz 的约 165.8 MIPS；若通过 130 MHz则约 182.5 MIPS。

## 验证

RAS 配置：

- 全部 RTL/testbench 编译 Errors 0、Warnings 0；
- `tb_issue_stage`、`tb_multi_issue_l2`、`tb_multi_issue_l3` 通过；
- L3I benchmark 通过，`sink=0x7F6E7CB1`、exceptions=0；
- L3 微基准保持 27 cycles、34 instret、IPC 1.259。

默认关闭配置也完成相同 RTL/unit 回归，L3I benchmark 基线通过。Questa divider 初始化和 L2/L3 未连接 debug 端口仍有既有警告。

## 决策与下一步

1. 8-depth RAS 的仿真收益明确，现已按后续云端综合版本要求转为默认开启；定义 `L3I_DISABLE_RAS` 可回退到无 RAS 配置。
2. 不采用仅在 EX 更新的简化 RAS；连续嵌套返回必须使用提交态/推测态分离。
3. 后续云端版本将默认同时包含 128 项 BTB 与 RAS；若时序或资源出现问题，可分别使用 `L3H_BTB_16_ENTRIES` 和 `L3I_DISABLE_RAS` 独立回退。
4. RAS 原始新增状态约 512 bits，面积风险小于 128 项 BTB；主要时序风险是 IF 指令预译码、RAS target 选择和 next-PC mux。
5. L3I 仍需 125/130 MHz 双频 post-route setup/hold 签核，只有 `IPC × Fmax` 保持净提升时才转为默认配置。
