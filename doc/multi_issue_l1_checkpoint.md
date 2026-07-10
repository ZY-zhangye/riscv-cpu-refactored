# 顺序多发 L1 阶段检查点

## 阶段目标

L1 在保持严格顺序、无 ROB、无寄存器重命名和无乱序完成的前提下，实现可运行的保守 2-wide 整数双发射流水线。所有不能安全配对的指令自动退化为 lane0 单发，年轻指令留在 issue buffer 中等待。

完成日期：2026-07-10

## 已完成架构

### 双字取指

- IF 与 CPU/SoC 指令存储接口扩展为两个 32-bit 同步读端口。
- 每拍请求 `PC` 与 `PC+4`，顺序取指基地址按 `PC+8` 推进。
- lane0 保留现有分支预测查询；lane0 预测跳转时取消顺序 lane1。
- lane1 控制流指令在 L1 被 issue 串行化，下一拍转为 lane0 后解析。

### 顺序 issue stage

- 新增两项顺序 holding buffer，`buf0` 永远比 `buf1` 老。
- 只有两条均为合法、单周期 RV32I 整数 ALU/LUI/AUIPC 指令时才考虑双发。
- 禁止包内 lane0→lane1 RAW，禁止包内 WAW。
- load/store、branch/jump、CSR/system/fence、M 扩展、FPU、Z 扩展和未知指令全部串行化。
- 配对失败时只发射 `buf0`，`buf1` 保留并在下一拍成为 lane0。
- redirect 或 exception 会同时清空两个 issue 槽位。

### 原子 bundle 流水

- 两个现有 ID/EXE/MEM/WB lane 以 `valid[1:0]` 语义组合使用。
- ID→EX 和 EX→MEM 分别计算共享推进条件。
- 任一有效 lane 因相关、多周期执行或下游反压未就绪时，整个 bundle 停止。
- lane1 不会越过 lane0，也不会在 lane0 多周期停顿时先行退休。
- load/store、branch、CSR、异常和多周期指令只进入 lane0，因此 L1 仍保持单 LSU、单控制流和单 CSR 副作用路径。

### 4R2W GPR 与双退休

- GPR 从 2R1W 扩展为 4R2W。
- 两个写口和四个读口均支持同周期 WB 旁路。
- lane1 是较年轻写口；issue 已禁止同包 WAW，寄存器堆仍保留 lane1 优先的防御性规则。
- MEM/WB 支持两个 lane 同周期退休，`retire_count` 可产生 0、1 或 2。
- commit trace 扩展为 `COMMIT0` 与 `COMMIT1`，保留两条指令的 PC、指令字和写回信息。

### L1 相关处理策略

- lane0 保留原有 EX/MEM 前递路径。
- lane1 不使用跨 lane EX/MEM 组合前递，避免 lane0 ALU→lane1 ALU 长组合路径。
- 对来自旧 lane1 的跨周期依赖，两个 ID lane 都等待结果到达 WB，再通过双写回旁路读取。
- lane1 自身对旧 lane0/lane1 的依赖同样采用保守等待策略。
- 该方案优先保证顺序正确性，性能优化留到 L2/L3。

### 中断 bundle 边界

- 当一个双发 bundle 正在 MEM 退休时，PLIC 外部中断不会只截断 lane0。
- 中断请求会锁存在 `irq_pending`，等 lane1 不再有效的 bundle 边界再交给 lane0 trap 路径。
- 同步异常、CSR、mret、ecall、ebreak 均已被 issue 串行化。

## 新增性能计数

在 L0 的性能 CSR 基础上增加：

| CSR | 含义 |
| --- | --- |
| `0x7CA perf_dual_issue` | 成功双发射周期数 |
| `0x7CB perf_single_issue` | 仅发射 lane0 的周期数 |
| `0x7CC perf_issue_raw` | 因包内 RAW 拒绝双发的次数 |
| `0x7CD perf_issue_waw` | 因包内 WAW 拒绝双发的次数 |
| `0x7CE perf_issue_struct` | 因指令类别/结构限制拒绝双发的次数 |

## 验证记录

- QuestaSim 2024.1 全 RTL 与 testbench 编译：Errors 0，Warnings 0。
- `tb_perf_counters`：通过。
- `tb_issue_stage`：通过，覆盖安全配对、RAW、WAW、复杂指令串行、下游反压和 flush。
- 当前用户激活的 ISA 镜像整核冒烟：通过，观察到 26 个真实双发周期。
- `run_all.bat all`：77/77 ISA 用例通过。
- 每个 ISA 用例都要求至少观察到一次 `dual_issue_event` 才允许报告通过。
- 77 个用例累计观察到 6037 个双发周期；单用例最少 16、最多 163、平均 78.4。
- 完整回归在隔离 Git worktree 执行，主工作区中的用户 HEX 修改未被覆盖。

## 综合决策

L1 已引入第二套整数执行 lane、4R2W GPR 和新的 bundle 组合控制，综合后资源和 Fmax 必然需要在进入 FPGA 收敛前评估。但当前未观察到功能、仿真速度或组合不稳定问题，完整回归全部通过；用户要求优先避免耗时综合，因此本阶段不启动综合。

在以下任一情况出现前继续以仿真推进：

- bundle 推进逻辑形成无法通过寄存切分解决的组合环；
- 4R2W GPR 无法由目标工具接受或产生明显不可控结构；
- L2 放开 load/branch 配对后必须依据资源或 Fmax 选择架构；
- 准备进入 FPGA 实现与最终性能收敛。

## 已知边界

- lane1 目前只执行简单 RV32I 整数指令。
- lane1 相关结果在 EX/MEM 不做跨 lane 前递，依赖者可能等待到 WB。
- 只有 lane0 参与分支预测；控制流指令仍单发。
- 数据存储器、MMIO、CSR、乘除法和 FPU 保持单路。
- store 仍在 EX 产生实际写使能，精确副作用提交属于 L2 风险项。
- 当前双路指令 RAM 适合仿真和双端口 BRAM；后续接 Cache 时需要封装为宽 fetch 接口。

## 下一阶段入口

下一阶段为 L2“功能完整的 2-wide”。优先处理完整双 lane 前递矩阵、单 LSU 安全配对、store 精确副作用、lane1 branch/jump 和 oldest-first exception/commit mask。
