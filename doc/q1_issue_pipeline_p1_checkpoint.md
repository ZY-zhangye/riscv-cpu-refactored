# Q1 Issue 流水化 P1 检查点

## 目标

切断 issue queue 与 ID/EX 双 lane 反压之间的组合路径，并缩小 EX redirect 对 issue queue 宽 payload、预译码和 tag 寄存器的控制锥。Q1 直连结构保留为可选回退配置。

## RTL 修改

1. `issue_stage` 的 flush 不再作为 queue payload 和预译码寄存器更新的外层条件。flush 周期的 `lane*_fire` 与 `packet_accept` 已为零，因此只清空 `queue_count` 和下一 packet tag。
2. `cpu_top` 在 issue queue 与双 ID lane 之间增加一项原子 bundle 寄存器，valid、两路 bus 和 flush 在该边界锁存。
3. issue queue 的下游 ready 终止在 bundle 寄存器输入；ID/EX 的反压位于新寄存边界之后。
4. redirect/exception 同拍屏蔽 bundle 输出并在时钟沿清空 valid，错误路径不会进入 ID。

默认定义 `L3_PIPELINED_ISSUE_OUTPUT`。定义 `L3_DISABLE_ISSUE_OUTPUT_PIPE` 可恢复 Q1 的 issue→ID 直连路径。

## 仿真结果

默认流水化配置：

- 全 RTL/testbench 编译：Errors 0、Warnings 0；
- `tb_issue_stage`、`tb_mem_commit`、`tb_multi_issue_l2`、`tb_multi_issue_l3`、`tb_dram_driver`：通过；
- L3 微基准：29 cycles、34 instret；
- 九窗口 benchmark：1,770,715 cycles、2,279,454 instret、IPC 1.287。

Q1 回退配置 `L3_DISABLE_ISSUE_OUTPUT_PIPE`：

- 全 RTL/testbench 编译：Errors 0、Warnings 0；
- `tb_multi_issue_l3`：27 cycles、34 instret，与原 Q1 一致。

流水化配置相对 Q1 的 benchmark IPC 从 1.301 降至 1.287，下降约 1.08%。吞吐盈亏平衡频率约为 126.4 MHz；若实现频率达到 150 MHz，估算吞吐为 193.1 MIPS，高于 Q1 @125 MHz 的 162.6 MIPS。

## 外部综合 A/B

综合和布局布线由外部流程执行。本工作区不运行 Vivado。建议以完全相同的器件、约束和 directive 比较：

- P1 默认：不增加宏；
- Q1 回退：定义 `L3_DISABLE_ISSUE_OUTPUT_PIPE`。

重点检查 EX redirect/ID allowin 到 `queue*` payload、`queue_info*` 和 CE/D 的路径是否退出前 20，以及新 bundle 寄存器是否成为局部短路径。若 150 MHz 仍受 issue 控制限制，再依据新前 20 继续切分配对选择或 queue 写入口；若关键路径迁移到 DRAM WEA，则 issue 流水化已达到本阶段目标。
