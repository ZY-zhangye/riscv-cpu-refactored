# Q1 M 阻塞绕过实验记录

## 实验范围

实验宏为 `L3Q_MULDIV_BLOCKING_BYPASS`。当 lane0 是正在停顿的 M 指令、lane1 是同包独立简单整数指令时，允许 lane1 提前进入 MEM；通过 `m_bypass_pending` 栅栏阻止 lane1 越过老 lane0 提前退休。

该路径不改变默认 Q1。默认 RTL 不定义该宏。

## 结果

- RTL/testbench 编译通过。
- `tb_issue_stage`、`tb_multi_issue_l2`、`tb_multi_issue_l3`、`tb_perf_counters` 均通过。
- 完整 benchmark 在实验宏下仍为 `1,751,323 cycles`、`2,279,454 instret`、`IPC 1.301`，未观察到周期收益。

## 决策

当前顺序 bundle 的 ID/EX 联动仍会在老 M 停顿时阻止前端继续填充，因此只提前释放 lane1 的 EX/MEM 位置不足以提高整体 IPC。实验宏保留用于后续流水线拆分后的复测，但不进入 Q1 默认配置，也不作为当前发布候选。
