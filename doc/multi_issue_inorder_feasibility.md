# 顺序多发射流水线改造可行性评估

## 1. 评估基线

- 开发分支：`codex/multi-issue-inorder`
- 基线提交：`fe91db1 fix pipeline flush and bridge read timing`
- 基线来源：当前 `main`
- 推荐第一阶段目标：2-wide 顺序双发射；接口保留后续参数化扩展的余地，但不在第一版实现 3-wide/4-wide。
- 工作区中原有的 `hex/riscv-tests/rv32-p-riscv.hex` 修改不属于本次改造，必须持续保留。

## 2. 结论

在当前无 Cache、五级顺序流水线基础上实现“保守的 2-wide 顺序双发射”是可行的，整体风险为中高，主要工作集中在取指带宽、双端口寄存器堆、相关性检查、双路前递、精确异常和全流水线 flush/反压一致性。

第一版不需要 ROB、寄存器重命名或乱序调度。只要坚持以下约束，就能维持顺序语义：

1. lane0 永远是较老指令，lane1 永远是较年轻指令。
2. 两条指令作为一个流水级 bundle 同步前进，使用共享的 `allowin`/skid-buffer 控制，bundle 内保留独立 `valid[1:0]`。
3. 第一版只允许两条彼此独立的简单整数 ALU 指令同时发射。
4. load/store、branch/jump、CSR/system、fence、乘除法、多周期指令和 FPU 指令全部退化为 lane0 单发射。
5. 第一版禁止同包 lane0 到 lane1 的 RAW，禁止同包 WAW；不做同周期跨 lane 前递。
6. 写回和异常处理必须按 lane0、lane1 的程序顺序提交。

在这一保守范围内，改造成功概率较高。若一开始就要求任意指令双发、两路访存、两路分支或 4-wide，则寄存器端口、存储器带宽、精确异常和组合相关性矩阵会同时膨胀，不适合作为当前工程的第一步。

## 3. 当前设计对多发射的主要限制

### 3.1 取指只有单条带宽

`cpu_top.sv` 当前只有一组 32-bit 指令存储器数据/地址端口；`if_stage.sv` 每次按 `PC + 4` 取下一条指令，并只产生一份 `fs_to_ds_bus`。因此，即使复制后端，也无法形成持续大于 1 IPC 的供给能力。

需要改为以下方案之一：

- 两个 32-bit 顺序读端口，分别读取 `PC` 和 `PC + 4`；实现直接，也便于借鉴历史双发射分支。
- 64-bit 取指端口加取指对齐/缓冲逻辑；更接近后续 Cache 接口，但要处理 `PC[2]` 导致的跨 64-bit 边界。

第一版推荐“两路 32-bit 读端口 + 2~4 项 fetch queue”，后续再封装为 64-bit fetch adapter。

### 3.2 级间总线和握手均为标量

当前 IF/ID、ID/EXE、EXE/MEM、MEM/WB 只有单个 valid 和单份数据包。各边界已使用注册化 `allowin` 与 1-entry skid buffer，解决了长组合 ready 链，但也意味着双发改造不能只复制组合数据通路；必须同步扩展每一级的 bundle 数据、valid mask、flush mask 和 skid 内容。

推荐保持“单个 bundle 握手 + 两个 lane valid”，避免两条 lane 独立滑动后产生年龄关系和异常提交困难。

### 3.3 整数寄存器堆只有 2R1W

当前 `regfiles.sv` 只有两个读端口和一个写端口。双发射简单整数指令需要最多 4 个读端口和 2 个写端口，并需要两个 WB 写口对四个 ID 源操作数的同周期旁路。

第一版应改为 4R2W，并定义：

- lane0/lane1 同地址写入在 issue 阶段禁止；寄存器堆仍保留确定的年轻 lane 优先规则作为防御。
- 两个 WB 写口同时命中某个读口时，年轻且程序序更后的写口优先。
- x0 永不写入，读取始终为零。

### 3.4 冒险与前递网络只有单生产者

当前 ID 只比较一条指令的 rs1/rs2 与单个 EXE、MEM、WB 目的寄存器；load-use 也只处理一个 EXE 生产者。双发后，每个源至少要检查两个 EXE lane、两个 MEM lane 和两个 WB lane，并保持“距离最近且程序序最新的生产者优先”。

第一版禁止包内 RAW，可以显著降低复杂度；跨周期仍需完整的双 lane 前递/阻塞矩阵。

### 3.5 数据存储器只有单端口

CPU 和 `bridge.sv` 目前只有一组 data-memory 请求接口，因此一个周期最多安全处理一条 load/store。第一版应把所有访存指令串行化到 lane0，不复制 LSU，也不改变 SoC 外设接口。

后续可以逐步允许“lane0 简单 ALU + lane1 load”，前提是整个 bundle 只有一条访存指令。store 更敏感，因为写存储器属于不可回滚副作用，在精确异常模型完成前不应与另一条指令配对。

### 3.6 异常、CSR 和退休计数是单路模型

当前 MEM 阶段只产生一份异常信息，CSR 只有一个读写端口，`instret` 每个有效写回周期只增加 1。双发后必须改为：

- lane0 异常：取消同 bundle 的 lane1，并冲刷所有更年轻指令。
- lane1 异常：允许 lane0 正常提交，再以 lane1 PC 进入 trap。
- 两条均正常：按 lane0 后 lane1 的顺序提交。
- `instret` 按实际提交的 lane 数量增加，即 `popcount(commit_valid[1:0])`。
- CSR/system/mret/ecall/ebreak 和中断边界第一版全部串行化。

当前 store 写使能在 EXE 阶段产生，而部分地址未对齐异常在 MEM 阶段判定。开始允许访存配对前，应把 store 的异常检查和副作用提交时机收紧，避免年轻 store 在较老异常确定前已经修改内存。

### 3.7 多周期单元与 FPU

EXE 当前会因乘除法或 FPU stall 停住整个执行级。第一版应只保留一套共享乘除法/FPU，并强制相关指令 lane0 单发。当前 `fpu.sv` 仍是占位实现，不应把双路 FPU 纳入本阶段范围。

## 4. 推荐的最小目标架构

```text
双字取指 / 64-bit fetch
          |
     2~4 项取指队列
          |
轻量预译码与 2-wide 顺序 issue
          |
  lane0(older) + lane1(younger)
          |
共享 bundle allowin/skid，双 ID、双整数 ALU
          |
单 LSU、单 branch/CSR、单 mul/div/FPU
          |
按 lane0 -> lane1 顺序提交的双写回
```

第一版 `can_pair` 建议仅在以下条件全部成立时为真：

```text
valid0 && valid1
两条都是已知合法的单周期整数 ALU 指令
lane0.rd 不被 lane1.rs1/rs2 读取
lane0.rd 与 lane1.rd 不相同（忽略 x0）
不存在 branch/CSR/system/fence/load/store/muldiv/FPU
下游能够接收完整 bundle
```

不能配对时只发射较老指令，年轻指令保留在 issue queue 中，下一拍成为 lane0，绝不能丢失或越过。

## 5. 建议实施阶段

### 阶段 A：建立可验证的 issue 边界

1. 新增独立 `issue_stage.sv` 和轻量预译码。
2. 先用单取指输入构造双条测试包，完成 issue 单元测试。
3. 加入顺序、不丢指令、不重复指令、RAW/WAW 禁止配对和 flush 清空的断言。

### 阶段 B：简单整数双发射

1. 扩展 IF 与 SoC 指令 RAM 为双字供给，并加入 2~4 项 fetch queue。
2. 把级间数据改成 bundle + `valid[1:0]`，沿用共享注册化 `allowin`/skid-buffer。
3. 增加第二套整数译码/ALU通路。
4. 将整数寄存器堆扩展为 4R2W。
5. 扩展 EXE/MEM/WB 前递矩阵和双写回调试接口。
6. 访存、分支、CSR、异常和多周期指令仍强制 lane0 单发。

这一阶段完成后，设计已经是功能完整的保守双发射 CPU；不满足配对条件时能够自动退化为原有单发射语义。

### 阶段 C：逐类放宽配对规则

建议按以下顺序推进，每放开一类都独立回归：

1. bitman 单周期指令。
2. lane0 简单 ALU + lane1 load（整个 bundle 只允许一个 LSU 操作）。
3. lane1 branch/jump，并完善预测和 redirect 年龄处理。
4. store 配对与精确副作用提交。
5. CSR 或多周期单元；只有性能数据证明有必要时再考虑。

不建议在这一工程阶段实现双 LSU、双 CSR 或双 mul/div/FPU。

## 6. 长期路线图与顺序多发上限

### 6.1 长期架构边界

本计划中的“顺序多发”采用严格定义：指令按程序顺序取指、进入 issue、执行和提交，不引入 ROB、寄存器重命名、保留站、动态唤醒选择、推测性乱序访存或乱序完成。允许使用取指队列、顺序 issue queue、流水化功能单元和有序 store buffer，但队首指令不能被年轻指令越过。

在这一约束下，硬件可以做成 2-wide、3-wide，甚至理论上的 4-wide，但 issue 宽度并不等于实际 IPC。严格顺序 issue 会受到以下根本限制：

- 队首指令阻塞会形成 head-of-line blocking，后面即使有独立指令也不能越过。
- 没有寄存器重命名时，同名寄存器造成的 WAW 等假相关只能等待或拆包。
- 单 LSU、分支和多周期单元会频繁迫使整个发射组降级。
- 发射宽度增加后，依赖比较器、寄存器端口和旁路 MUX 近似按宽度平方增长。
- 编译器未针对多发槽位进行调度时，连续可配对指令数量有限。

因此，对当前 FPGA/毕业设计规模的 RV32 核心，长期工程最优目标是“功能完整、时序稳定的 2-wide 顺序超标量”；3-wide 适合作为有条件的非对称实验扩展；4-wide 只能作为研究型上限，不应作为默认交付目标。4-wide 以上在不引入乱序的前提下投入产出很低，本计划不再向上扩展。

### 6.2 各宽度可达到的程度

| 宽度 | 前端与寄存器堆 | 执行资源 | 存储与提交 | 定位 |
| --- | --- | --- | --- | --- |
| 成熟 2-wide | 每拍取 2 条，4~8 项 fetch queue，4R2W GPR，双译码 | 2 个整数 ALU；共享 branch、LSU、CSR、mul/div、FPU | 每组最多 1 条访存，最多提交 2 条 | 推荐长期主目标，可覆盖大多数有价值的顺序多发优化 |
| 非对称 3-wide | 推荐 128-bit 取指，6~12 项队列，最多 6R3W；也可限制每拍最多 2 个 GPR 写以降低端口成本 | 2~3 个整数 ALU，其中 slot0 为完整 lane，其他槽位限制为简单整数/bitman | 仍只允许 1 条 LSU/控制类指令，最多提交 3 条 | 可行但收益不确定，仅在成熟 2-wide 被宽度而非依赖限制时启动 |
| 研究型 4-wide | 128-bit 取指，8~16 项队列，8R4W GPR，四译码和大规模旁路矩阵 | 3~4 个整数 ALU；若仍只有单 LSU，利用率会很低 | 理论每拍提交 4 条；实用版本往往需要 banked memory/cache 支撑 | 理论可实现，但面积、Fmax、验证和实际 IPC 均不适合当前主线目标 |

顺序 4-wide 的理论峰值可以达到 4 IPC，但只有连续四条合法、无依赖、无结构冲突且下游全部就绪时才可能出现。当前设计若长期保持单 LSU、单 CSR、单分支单元和共享多周期单元，实际可持续性能会远低于该峰值。因此“最多能做到”应区分为：

- 架构理论上限：4-wide 严格顺序取指/发射/提交。
- 当前工程可控上限：非对称 3-wide。
- 推荐长期完成形态：功能完整且充分优化的 2-wide。

### 6.3 长期阶段 L0：测量基础与单发基线冻结

状态：已于 2026-07-10 完成。实现与验证记录见 `multi_issue_l0_checkpoint.md`。

目标是在修改数据通路前，让所有后续性能和正确性结论可复现。

1. 建立逐条 commit trace，记录 PC、指令、GPR/FPR/CSR 写回、访存地址与写数据。
2. 修正 `instret`，直接按实际 commit 数量计数，不再按分支/异常周期估算。
3. 增加 stall 分类计数：前端空泡、RAW、load-use、结构冲突、多周期、分支误预测、异常冲刷。
4. 保存当前 ISA 回归、CoreMark/性能程序的 cycle、instret、IPC 和仿真 trace 基线。
5. 建立综合基线：LUT、FF、BRAM、DSP、Fmax 和关键路径。

完成门槛：回归结果可重复，commit trace 可与单发基线或参考模型逐条比较。

### 6.4 长期阶段 L1：保守 2-wide 整数双发

状态：已于 2026-07-10 完成。实现与验证记录见 `multi_issue_l1_checkpoint.md`。

目标是得到第一个可长期维护的双发版本。

1. 双字取指、4~8 项 fetch queue 和 2-entry 以上的顺序 issue buffer。
2. 使用 `valid[1:0]` 的原子 bundle 贯穿 ID/EXE/MEM/WB，保持共享 `allowin`/skid-buffer。
3. GPR 扩展为 4R2W，增加第二套整数译码和 ALU。
4. 只允许两条独立的 RV32I 简单整数指令双发；RAW、WAW 或复杂指令自动拆包。
5. 建立双 commit trace、双写回旁路和双 lane 断言。
6. load/store、branch、CSR、system、mul/div 和 FPU 全部独占 lane0。

完成门槛：全部单发回归无回退，新增双发测试通过，并能在连续独立 ALU 程序上稳定达到接近 2 IPC。

### 6.5 长期阶段 L2：功能完整的 2-wide

状态：已于 2026-07-10 完成。实现与验证记录见 `multi_issue_l2_checkpoint.md`。

目标是让双发能力覆盖实际程序中的主要安全组合，而不仅是人工 ALU 序列。

1. 完成两个消费者对双 EX/MEM/WB 生产者的跨周期前递矩阵。
2. 允许单个 bundle 中出现一条 LSU 指令，例如 ALU+load、独立 load+ALU；每拍仍最多一个数据存储请求。
3. 在修正 store 异常检测和有序副作用后，允许安全的 ALU+store 组合。
4. 支持 lane1 branch/jump；每个 bundle 最多一条控制流指令，并按 lane 年龄精确 redirect。
5. 完成 oldest-first exception/interrupt/commit mask：lane0 异常取消 lane1，lane1 异常保留 lane0 提交。
6. CSR/system/fence/mret/ecall/ebreak 继续独占发射，并等待更老指令完成。
7. mul/div/FPU 保持共享、单发，但其 stall 必须正确冻结整个 bundle。

完成门槛：完整 ISA、异常、中断、MMIO 和性能回归通过；双发版最终架构状态与单发参考完全一致。

### 6.6 长期阶段 L3：高性能 2-wide

状态：L3A、L3B、L3C 已完成仿真与后路由分析；L3C 已移除 DRAM BRAM `ENARDEN` 关键路径。L3D 已完成 issue payload flush 扇出清理及完整 RTL 回归，等待后路由复测。记录见 `multi_issue_l3a_checkpoint.md`、`multi_issue_l3b_checkpoint.md`、`multi_issue_l3c_checkpoint.md` 与 `multi_issue_l3d_checkpoint.md`。

目标是在不引入乱序的前提下，尽量接近 2-wide 的实际性能上限。

1. 根据时序结果选择是否加入 lane0 ALU 到 lane1 ALU 的同周期旁路；若形成过长关键路径则继续拆包。
2. 将轻量预译码、依赖检查和最终 issue 选择合理分级流水，避免 `can_pair` 成为 Fmax 瓶颈。
3. 扩大 fetch queue，支持分支重定向后的快速恢复，并优化两个 PC 的预测查询。
4. 允许更多单周期 bitman/简单扩展指令参与配对。
5. 对乘法器做流水化评估，但结果仍按程序顺序接受；除法器继续独占。
6. 增加小型有序 store buffer，使 store 只在确认无更老异常后对 RAM/MMIO 生效。
7. 根据综合结果优化 4R2W GPR 的复制、旁路和物理实现。

完成门槛：目标程序的 IPC 提升来自真实双发，而非降低时钟频率换取；必须同时报告 IPC、Fmax 和每秒有效指令数。

### 6.7 长期阶段 L4：非对称 3-wide 可选实验

只有成熟 2-wide 满足以下条件时才进入本阶段：

- 目标负载中有足够多连续三条独立简单整数指令。
- 2-wide 的主要瓶颈是发射宽度饱和，而不是分支、访存、RAW 或多周期停顿。
- FPGA 仍有足够 LUT/寄存器资源，且 2-wide 的 Fmax 已稳定。

推荐采用非对称槽位，而不是三条完全等价的 lane：

```text
slot0：完整指令槽，承担 branch/LSU/CSR/system/muldiv
slot1：整数 ALU/bitman
slot2：简单整数 ALU/bitman
```

具体工作：

1. 前端改为 128-bit 取指或等效四字 fetch block，从中最多选择前三条顺序指令。
2. issue 检查扩展为三条指令间的 RAW/WAW/结构冲突矩阵，仍只检查队首连续指令，禁止跨越。
3. GPR 评估 6R3W；若成本过高，规定每组最多两条写 GPR 指令。
4. 增加第三套简单整数译码/ALU和第三 commit 槽。
5. 继续限制每组最多一条 load/store、一条 control/CSR/system 和一条多周期指令。
6. 重新测量 Fmax、资源和真实 IPC；若每秒有效指令数没有明显超过高性能 2-wide，则停止 3-wide 主线化。

本阶段属于研究扩展，可以保留在独立分支，不应阻塞成熟 2-wide 的稳定版本。

### 6.8 长期阶段 L5：4-wide 理论研究上限

4-wide 仍可保持严格顺序，但需要 128-bit 取指、四译码、8R4W 级别寄存器访问、四路 commit、六组包内依赖关系和更大的跨级旁路网络。若希望获得与硬件投入相称的性能，通常还需要更宽的指令存储接口、banked data memory 或 Cache，以及至少两个可并行的简单执行/访存通道。

本项目只在以下情况下把 4-wide 作为独立研究任务：

1. 非对称 3-wide 已证明目标负载仍受发射宽度限制。
2. 目标 FPGA 资源和存储器结构可以支持宽取指与多端口寄存器堆。
3. 允许显著重构前端、寄存器堆和存储系统。
4. 有完善的差分验证、形式断言和自动性能/综合回归。

否则长期路线应停在高性能 2-wide，或最多保留非对称 3-wide 实验。4-wide 以上不再规划，因为严格顺序带来的队首阻塞会使新增硬件大部分时间得不到利用，而这类瓶颈通常只有动态乱序调度才能根本缓解；乱序不在当前计划范围内。

### 6.9 长期决策原则

每次扩大发射宽度之前，都使用以下指标作继续/停止判断：

1. 正确性：完整 ISA、异常、中断、MMIO 和差分 trace 必须无回退。
2. 吞吐：同时比较理论 IPC、实际 IPC、Fmax 和每秒提交指令数。
3. 利用率：统计 1/2/3/4 发周期比例以及拒绝配对的具体原因。
4. 成本：比较 LUT、FF、BRAM、DSP、功耗和关键路径变化。
5. 瓶颈归因：只有当前宽度经常满发时才增加宽度；若主要瓶颈是 RAW、分支或 LSU，应优化这些环节而不是继续加 lane。
6. 可维护性：稳定 2-wide 始终保留为可综合、可回归的长期基线，3-wide/4-wide 使用独立实验分支。

## 7. 风险分级

| 项目 | 风险 | 原因与控制措施 |
| --- | --- | --- |
| flush、反压和 skid-buffer 一致性 | 高 | 当前握手已注册化；必须以 bundle 为单位推进并对每个 lane 保存 valid/flush |
| 精确异常与 store 副作用 | 高 | 年轻 lane 不能在较老异常确定前产生不可回滚副作用；首版串行化 store |
| 双 lane 前递和 load-use | 高 | 比较矩阵显著扩大；首版禁止包内 RAW，跨周期按年龄定义优先级 |
| 双字取指和分支重定向 | 中高 | 需要处理队列清空、lane1 PC 和跨边界取指；首版分支单发 |
| 4R2W 寄存器堆的 FPGA 映射 | 中高 | 可能增加 LUT/复制 RAM；32x32 规模仍可控，但必须做综合评估 |
| CSR、中断与退休计数 | 中 | 首版串行化 CSR/system，中断只在明确的 bundle 提交边界采样 |
| 面积和最高频率 | 中 | 两套译码/ALU和前递 MUX 增加关键路径；issue 预译码应保持轻量并单独流水化 |
| 3-wide/4-wide 扩展 | 高 | 取指、寄存器端口和 O(W^2) 相关性检查快速膨胀；暂不建议实现 |

## 8. 验证策略与完成标准

必须同时验证“原功能没有回退”和“确实发生双发射”。建议完成标准如下：

1. 当前 `base` 与 `all` 回归全部通过。
2. 新增 issue 单元测试：安全配对、包内 RAW、WAW、串行指令、单 lane 反压、全局 flush。
3. 新增小程序覆盖：连续独立 ALU、跨包依赖、load-use、分支误预测、lane0/lane1 异常优先级、中断边界。
4. debug/trace 每周期输出两个 commit 槽，并可按 PC 顺序还原唯一指令流。
5. 增加计数器：提交指令数、双发射周期数、因 RAW/WAW/结构冲突退化的周期数。
6. 用单发基线与双发版本比较架构状态；条件允许时增加 Spike/参考模型差分测试。
7. 对 CoreMark 或现有性能程序比较 cycle、instret、IPC，同时记录 LUT、FF、BRAM 和 Fmax。

现有回归框架还需要补强：`run_all.bat` 虽然编译了 `test/*.sv`，批量回归实际只启动 `tb_my_cpu`；当前通过条件主要依赖写回 PC 到达固定地址并检查一个调试寄存器。这可以继续作为 ISA 冒烟回归，但不足以证明双 lane 没有丢失、重复、越序提交或错误处理异常。新增的 issue/dual-commit 测试必须显式接入批量回归。

本次已在工作区外的独立 Questa work library 中完成当前基线的全 RTL/testbench 编译：Errors 0，Warnings 0。未执行 `run_all.bat`，因为该脚本会覆盖用户当前修改的 `rv32-p-riscv.hex`。

## 9. 历史双发射分支的利用方式

仓库已有 `codex/dual-issue-design`，包含 issue stage、双路流水线、寄存器堆扩展、分支预测器和双发射测试，证明本工程完成保守双发射在技术上可行。该分支与当前主线的共同基线是 `fa7eb0b`，而当前主线随后增加了注册化 allowin/skid-buffer、板级同步以及 flush/bridge 读时序修复。

因此不建议把历史分支整体 merge 或大段 cherry-pick。推荐复用其以下内容：

- `issue_stage` 的轻量预译码字段和 RAW/WAW 配对规则。
- `tb_issue_stage.sv`、`tb_dual_issue_simple.sv` 的测试场景。
- 双读/双写寄存器堆接口和双路 debug 信号的接口思路。
- lane0 为老、lane1 为新的程序序约束。

应以当前 `fe91db1` 为实现基线，重新把双 lane 数据组织成共享握手的 bundle，从而保留当前主线已经验证过的 flush、skid-buffer 和 bridge 时序修复。

历史分支的异常路径也不能原样照搬：其异常仲裁和全局 `exception_flag` 对两条写回使用统一禁止条件，无法完整表达“lane1 异常时 lane0 仍应先退休”的 oldest-first 语义。当前分支必须重新设计 per-lane exception/commit mask。
