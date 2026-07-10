# 顺序多发 L2 阶段检查点

## 阶段目标

L2 将 L1 的保守双整数 ALU 配对扩展为功能完整的严格顺序 2-wide：两个消费者能够使用双 EX/MEM 生产者结果；单个 bundle 可包含一条 LSU；lane1 可执行 branch/jump；异常、退休和 store 副作用按指令年龄精确处理。

完成日期：2026-07-10

## 已完成架构

### 双 lane 完整整数前递

- GPR 源操作数前递选择由 2 bit 扩展为 3 bit，编码寄存器值、EX0、EX1、MEM0 和 MEM1。
- 两个 EX lane 在接收新指令时同时锁存四个生产者结果快照，因此 lane0/lane1 消费者都可使用任一旧 lane 的结果。
- EX 生产者是 load 或多周期未完成结果时，整个 bundle 继续停顿；结果进入 MEM 或执行完成后再推进。
- WB 保留双写口旁路，形成 EX0/EX1/MEM0/MEM1/WB0/WB1 的完整跨周期整数相关处理。
- 包内 lane0→lane1 RAW 与 WAW 仍由 issue 拆包，未引入同周期长旁路。

### 单 LSU 安全配对

- 允许 `lane0 LSU + lane1 simple ALU`。
- 允许 `lane0 simple ALU + lane1 LSU`。
- 一个 bundle 最多一条 load/store；双 LSU、FPU load/store 配对仍禁止。
- 两个 EX lane 的访存请求在顶层仲裁到单路数据存储器。
- 当已到 MEM 的老 store 与年轻 EX load 同周期争用端口时，store 优先，整个 EX bundle 冻结一拍，保持内存顺序。

### 精确 store 副作用

- EX 只计算 store 地址、字节写掩码和写数据，不再直接写外部 RAM/MMIO。
- store 信息随 `ES_MS` bus 进入 MEM。
- 仅当 store 到达 MEM、下游允许提交、本 lane 无异常且未被更老 lane 取消时，才产生真实 `dmem_wen`。
- 未对齐 store 在 MEM 产生 `EXC_SAM`，不会产生任何外部写副作用，也不会退休。
- store debug trace 改为记录 MEM 提交事件，因此 trace 与真实外部写请求一致。

### lane1 branch/jump

- 允许 `lane0 simple ALU + lane1 branch/jal/jalr`，每个 bundle 最多一条控制流指令。
- lane1 当前按未预测处理，在 EX 解析后产生 redirect；taken 与 not-taken 均按实际结果冲刷年轻指令。
- 顶层按 lane 年龄选择 redirect、目标地址、预测器更新和分支性能事件。
- 修正了 EX 无有效指令时旧控制流信息可能残留 redirect 的问题，redirect 现在显式由 `es_valid` 门控。

### oldest-first 异常、提交与中断边界

- MEM lane 增加独立 `commit_kill`，不再用全局 `exception_flag` 同时取消两个 lane 的当前提交。
- lane0 异常优先，并取消同组 lane1 的 GPR/FPR/CSR 写回、store 和退休。
- lane1 异常保留 lane0 的正常提交，并使用 lane1 的 PC/mtval 写入 `mepc/mtval`。
- lane0 自身异常与 lane1 自身异常均不会退休。
- 外部中断继续只在没有 lane1 退休的 bundle 边界交给 lane0，已有 `irq_pending` 保留等待中的请求。
- CSR/system/fence/mret/ecall/ebreak、mul/div、FPU 继续单发，避免共享副作用与多周期完成次序复杂化。

## 新增性能计数

| CSR | 含义 |
| --- | --- |
| `0x7CF perf_lsu_pair` | 成功发射“单 LSU + 简单 ALU”组合的次数 |
| `0x7D0 perf_lane1_control` | 成功在 lane1 发射 branch/jump 的次数 |
| `0x7D1 perf_lsu_conflict` | MEM store 优先导致年轻 EX load bundle 冻结的周期数 |

原有 `dual_issue`、`single_issue`、RAW/WAW/结构拒绝、load-use、执行停顿、分支和异常计数继续有效。

## 验证记录

- QuestaSim 2024.1 全 RTL 与全部 testbench 编译：Errors 0，Warnings 0。
- `tb_issue_stage`：通过；覆盖双 ALU、ALU/LSU 双向配对、store 配对、lane1 branch、包内 RAW/WAW、CSR 串行、反压和 flush。
- `tb_perf_counters`：通过；覆盖 L0/L1 计数与新增 L2 三项计数。
- `tb_mem_commit`：通过；覆盖 aligned store 提交、misaligned store 无副作用、`commit_kill` 取消 store/GPR 写回与退休。
- `tb_multi_issue_l2`：通过；覆盖 EX0+EX1 同时前递、MEM1 load 前递、store/load 单端口冲突、lane1 load、lane1 taken branch 冲刷、双 store 提交及年龄相关异常。
- 年龄专项：lane1 load misaligned 时 lane0 正常退休，`mepc=lane1 PC`；lane0 load misaligned 时 lane1 写回被取消。
- `run_all.bat all`：77/77 ISA 用例通过，包含 RV32I、机器态、M 扩展和已实现的 Zba/Zbb/Zbkb/Zbs。
- 完整回归在 `F:\Tools` 下的隔离 Git worktree 执行，主工作区用户已有的 `hex/riscv-tests/rv32-p-riscv.hex` 修改未被覆盖。

## 综合决策

本阶段没有发现必须依赖综合结果才能决定功能架构的实际风险：单 LSU 仲裁没有组合环，完整前递采用进入 EX 时的结果快照，包内 RAW 仍拆包，避免了 lane0→lane1 同周期长路径。按用户要求，本阶段不启动耗时综合。

进入 L3 后，下列项目需要以综合结果为依据：是否加入包内同周期旁路、扩大 fetch queue 后的 issue 关键路径、4R2W GPR 的物理实现，以及 IPC 提升能否抵消 Fmax 下降。

## 已知边界

- 仍是严格顺序发射、原子 bundle 推进和有序提交；没有 ROB、重命名或乱序访存。
- 包内 RAW/WAW 继续拆包，尚未实现 lane0 ALU 到 lane1 的同周期前递。
- 每个 bundle 最多一个 LSU 请求；没有双 LSU 或 store buffer。
- lane1 branch/jump 不做前端预测，taken branch 必须等待 EX redirect。
- CSR/system/fence、mul/div、FPU 和 Z 扩展配对仍保持保守单发策略。
- 当前 issue buffer 只有两项；前端容量和 redirect 恢复吞吐属于 L3 优化项。

## 下一阶段入口

下一阶段为 L3“高性能 2-wide”。优先以性能数据选择扩大 fetch queue、放开单周期 bitman 配对、优化 issue 判定分级；包内同周期旁路和有序 store buffer只有在综合与目标负载证明收益后再引入。
