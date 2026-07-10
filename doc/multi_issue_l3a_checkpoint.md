# 顺序多发 L3A 性能优化检查点

## 检查点定位

L3A 完成不依赖目标 FPGA 综合即可验证的高性能 2-wide 优化：扩大顺序 issue queue、将配对预译码前移、允许已实现的单周期 bitman 参与双发，并为两个取指 PC 同时查询分支预测器。

本检查点不宣称完整 L3 已收敛。完整 L3 的完成门槛包含 Fmax、资源和每秒有效指令数；当前环境没有 Vivado、Quartus、Yosys 或 nextpnr，因此需要综合判断的包内同周期旁路、乘法器流水化、4R2W 物理映射和 store buffer 继续保留。

完成日期：2026-07-10

## 已完成优化

### 四项顺序 issue queue

- issue holding buffer 从 2 项扩展为 4 项，可容纳两个完整双字 fetch packet。
- 队列继续严格按程序顺序出队，只检查队首连续两条，年轻指令不能越过队首。
- 单发后保留的包尾指令可以与下一 fetch packet 的队首重新配对，消除 L2 的 packet 边界人为气泡。
- 支持同周期出队 0/1/2 条并入队 1/2 条，保持下游反压和原子 bundle 语义。
- redirect/exception 会一次清空四个槽位、预译码和 packet 标签。

### 入队预译码分级

- GPR 源/目的寄存器、读写需求、简单整数、LSU、控制流和 bitman 类别在入队时计算并锁存。
- 最终 `can_pair` 只读取预译码寄存器并完成 RAW/WAW/类别比较，不再重复穿过完整 bitman 指令识别网络。
- 包内 RAW/WAW 仍拆包，没有引入 lane0→lane1 同周期长旁路。

### 单周期 bitman 双发

- 已实现的 Zba、Zbb、Zbkb、Zbs 单周期指令归入 simple lane 类别。
- 支持 bitman+bitman、ALU+bitman、bitman+ALU、单 LSU+bitman，以及 bitman+lane1 control 的既有安全组合。
- issue 预译码精确区分寄存器双源、立即数和单源 bitman，继续执行包内 RAW/WAW 检查。
- mul/div/FPU 和 CSR/system 类别没有放宽。

### 双 PC 分支预测查询

- 分支预测表同时查询 `PC` 和 `PC+4`。
- lane0 预测 taken 时取消顺序 lane1；lane1 预测 taken 时保留两条指令，并让下一 fetch 转向 lane1 目标。
- 两个 lane 的预测信息分别随指令进入流水线，EX 继续统一验证 taken/target 并精确 redirect。
- lane1 循环分支训练后可命中预测，不再每次 taken 都等待 EX redirect。

## 新增性能计数

| CSR | 含义 |
| --- | --- |
| `0x7D2 perf_bitman_pair` | 包含至少一条 bitman 的成功双发次数 |
| `0x7D3 perf_cross_packet` | 两条指令来自不同 fetch packet 的成功双发次数 |
| `0x7D4 perf_issue_qfull` | IF 有有效 packet 但四项 issue queue 无空间接收的周期数 |

## L2/L3A 同程序对比

使用 `tb_multi_issue_l3` 中相同的 34 条动态退休指令进行对比。程序包含连续包内 RAW、跨 packet 可配对指令、双 bitman、store+bitman 和五次 lane1 循环分支。

| 版本 | 周期 | instret | IPC | 分支误预测 |
| --- | ---: | ---: | ---: | ---: |
| L2 `d74df3a` | 43 | 34 | 0.790 | 5 |
| L3A | 27 | 34 | 1.259 | 2 |

结果：周期减少 16 拍，约 37.2%；IPC 提升约 59.4%。L3A 实际观察到 3 次跨 packet 双发和 2 次 bitman 配对。该结果是针对本检查点瓶颈构造的微基准，用于证明优化路径真实生效，不替代 CoreMark 或目标应用测量。

## 验证记录

- QuestaSim 2024.1 全 RTL 与全部 testbench 编译：Errors 0，Warnings 0。
- `tb_perf_counters`：通过，覆盖新增 L3A 计数器。
- `tb_issue_stage`：通过，新增覆盖四项队列满载、同周期出入队、跨 packet 配对、bitman 配对、RAW 和 flush。
- `tb_mem_commit`：通过。
- `tb_multi_issue_l2`：通过，L2 精确 store、LSU、前递和异常年龄语义无回退。
- `tb_multi_issue_l3`：通过，测得 `cycles=27`、`instret=34`、`IPC=1.259`、跨 packet 配对 3 次、bitman 配对 2 次、分支误预测 2 次。
- `run_all.bat all`：5 个单元/专项测试全部通过，77/77 ISA 用例通过。
- 完整回归在 `F:\Tools` 下的隔离 worktree 执行，主工作区用户已有 HEX 修改未被覆盖。

## 尚未执行综合的原因

当前 PATH 中未发现 Vivado、Quartus、Yosys 或 nextpnr，仓库也没有现成目标器件综合工程。用户此前要求只有遇到必须综合判断的实际风险时才进行耗时综合。

L3A 的功能和周期收益已经由仿真闭环验证，但以下决策必须等待综合数据：

- 四项队列同周期出入队路径是否需要再加一级寄存。
- lane0 ALU 到 lane1 的包内同周期旁路是否会降低 Fmax。
- 4R2W GPR 在目标 FPGA 上采用 LUT、复制 RAM 还是其他物理结构。
- 乘法器流水化后的 DSP、延迟和 bundle 冻结策略。
- 有序 store buffer 对 RAM/MMIO 路径、资源和时序的影响。

因此本次提交标记为 L3A 检查点，而不是完整 L3 完成版本。

## 下一步入口

下一部分应先建立目标 FPGA 综合基线，报告 L2 与 L3A 的 LUT、FF、BRAM、DSP、Fmax 和“IPC×Fmax”。若 L3A 每秒有效指令数仍有净收益，再选择以下一项继续：

1. 保持拆包，优化四项 queue 的 allowin/shift 物理结构。
2. 加入受限的 lane0 简单 ALU→lane1 简单 ALU 同周期旁路。
3. 增加 1～2 项有序 store buffer，隐藏 store/load 单端口冲突。

在没有综合数据前不进入非对称 3-wide。
