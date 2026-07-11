# 后续性能结构设计路线图

## 1. 范围与目标

本文只讨论微架构性能结构，不讨论流水级如何切分、寄存器插在哪里、物理布局或具体时序修复。所有模块边界优先定义成 `valid/ready + tag + payload`，后续可以在不改变架构语义的前提下单独增加流水级。

目标不是继续堆叠顺序多发宽度，而是逐步解除当前核心的三个根本限制：

1. 两条指令作为原子 bundle 推进，任一长操作会冻结整个执行通路；
2. issue 只能看队首连续指令，年轻独立指令不能绕过 RAW、load 或 M 扩展阻塞；
3. 单 LSU、无 store queue、无完成队列，所有副作用必须跟随固定流水同步前进。

最终推荐形态是“小窗口、2-wide、有限乱序执行、有序退休”的 RV32 核。它比继续扩展 3/4-wide 顺序多发更符合当前 FPGA 资源和负载特征，也给后续流水线拆分留下清晰边界。

## 2. 当前瓶颈依据

| 现象 | 当前数据 | 结构含义 |
| --- | ---: | --- |
| MEXT EX stall | 152,000 | 长乘除法冻结整个 bundle，是最明确的可隐藏延迟 |
| multiplier latency | 6 cycles | 适合改为独立、可标记完成的执行单元 |
| divider latency | FPGA IP 35 cycles | 更需要允许年轻独立指令继续执行 |
| MEMORY load-use | 46,081 | 队首依赖会形成持续后端空泡 |
| 静态 load/store | 28.97% | LSU 是长期重要资源，但当前还没有双端口需求证据 |
| 静态控制流 | 17.87% | BTB、2-bit、JALR 和 RAS 已有较完整基础 |
| RETURN mispredict | 11 | 返回预测已接近饱和，继续投入优先级较低 |
| 完整同周期 ALU 旁路 | cycles -3.29% | 有收益，但需要跨两套 ALU 的长组合路径 |
| 8-entry 顺序 queue | cycles 无变化 | 单纯加深队列不能解决队首阻塞 |

因此后续优先解决“长延迟操作阻塞”和“队首阻塞”，而不是先扩大取指、发射或提交宽度。

## 3. 推荐总体结构

```text
Fetch blocks / predictor
          |
          v
  Decode + dispatch (2-wide)
          |
          +------> small ROB / in-order commit ------> architectural state
          |
          v
   issue window / scoreboard
      |       |       |       |
      v       v       v       v
    ALU0    ALU1    LSU     MUL/DIV
      |       |       |       |
      +-------+-------+-------+
              result packets {rob_tag, value, exception, metadata}
```

核心原则：

- dispatch 和 commit 保持 2-wide；执行单元不再以原子 bundle 锁步推进；
- 每条指令分配单调递增的 `rob_tag`，所有结果和异常按 tag 回到 ROB；
- 执行可以不同周期完成，程序可见更新只能从 ROB 头部按顺序发生；
- store、CSR、异常、中断和预测恢复统一在提交序边界处理；
- 初期不做寄存器重命名，后续再按收益加入。

## 4. 阶段 A：独立执行与有序完成

### A1. 小型 ROB / completion queue

先实现 8-entry ROB，保留 2-wide 顺序 dispatch 和 2-wide 顺序 commit。建议每项至少保存：

```text
valid, done, pc, inst, rd, write_gpr, result,
exception, branch metadata, store metadata, csr metadata
```

首版不要求动态调度。指令仍按顺序进入执行单元，但 ALU、LSU 和 M 单元使用独立握手；某条 M 指令等待结果时，后续无依赖 ALU 可以继续进入空闲 ALU 并把结果写入自己的 ROB 项。

收益来源：

- 解除当前 `ex_bundle_advance` 对两条 lane 的全局锁步；
- 隐藏 6 拍乘法和 35 拍除法的一部分延迟；
- 为后续 LSU response、cache miss 和多周期 bitman/FPU 提供统一完成接口。

### A2. 保守 scoreboard

在不重命名的阶段，为 32 个架构整数寄存器维护 pending/tag：

- source 的生产者未完成时，消费者等待或从完成结果旁路；
- 同一架构目的寄存器存在未退休写时，新的写先保守阻塞；
- WAR/WAW 暂不绕过，避免第一版立即引入 rename map 和 free list；
- x0 永不分配 pending 状态。

scoreboard 只负责依赖，不负责架构提交。ROB 始终是异常、分支恢复和退休顺序的唯一依据。

### A3. 独立 MUL/DIV request queue

M 单元改为明确请求/响应协议：

```text
request  = {rob_tag, op, src1, src2, signed_mode}
response = {rob_tag, result, div_zero/exception metadata}
```

首版使用 1-entry request slot 即可。乘法和除法可以共享入口，但要分别统计 busy cycles；若后续 multiplier 支持每拍接受请求，再扩大为 2~4 项请求队列。除法继续单请求运行，不需要复制 divider。

本阶段预期是当前工程最高优先级的性能结构，因为它能利用已经存在的两套 ALU 去覆盖长 M 延迟，不依赖跨 ALU 同周期组合旁路。

## 5. 阶段 B：小窗口 oldest-ready 调度

ROB 稳定后，把顺序 issue queue 改为 8~12 项 issue window。每项保存轻量预译码、源 tag/ready、目的 ROB tag 和执行类别。

选择规则：

1. 每类执行资源从窗口中选择最老的 ready 指令；
2. 同周期最多发两条，保持 ALU0/ALU1/LSU/M 的端口限制；
3. 没有重命名时继续阻塞 WAR/WAW；
4. control、CSR、MMIO 可先限制为窗口中最老指令；
5. 任何结果都写 ROB，不直接改变程序可见状态。

该阶段可以让年轻独立指令绕过：

- 等待 load data 的消费者；
- 正在执行的 MUL/DIV；
- 被单 LSU 或结构冲突挡住的队首指令。

窗口不宜一开始做大。8~12 项已经足以验证队首阻塞是否是主要限制，也能控制比较器、wakeup 和选择网络规模。

## 6. 阶段 C：寄存器重命名

只有 scoreboard 版本的 WAR/WAW 阻塞仍然显著时，再加入整数物理寄存器重命名：

- 32 个架构寄存器，建议先使用 48 个物理寄存器；
- 维护 speculative map、committed map 和 free list；
- ROB 项保存旧 physical destination，提交后释放；
- branch 至少保存 rename checkpoint 或 ROB tail 恢复点；
- x0 固定映射到只读物理零寄存器。

重命名的价值不是提高理论发射宽度，而是移除假相关，使小窗口调度真正能够绕开 WAR/WAW。若动态计数证明假相关很少，可以停留在无重命名的有限乱序版本。

## 7. 阶段 D：LSU 与内存顺序

### D1. 有序 store queue

建议先实现 2~4 项 store queue：地址和数据可提前生成，但只有对应 ROB 项到达提交头且无异常时才对 RAM 生效。

- 普通 RAM store 可以进入 queue 后由提交端排空；
- MMIO store 必须保持强顺序，且不能推测执行；
- 年轻 load 与旧 store 地址匹配时，从最年轻匹配 store 前递；
- 地址未知时，首版保守阻塞年轻 load，不做 replay。

当前 benchmark 的 `lsu_conflict=0`，所以 store queue 不是短期首选；它主要是 ROB/乱序执行后的正确性配套结构。

### D2. Load queue 和保守内存消歧

在 issue window 能乱序发射 LSU 后，需要 4~8 项 load queue：

- load 记录 ROB tag、地址、大小和符号扩展模式；
- 检查所有更老未提交 store；
- 首版只允许在更老 store 地址全部已知且不匹配时越过；
- 后续若加入预测性 load，必须支持 store-load violation 检测和 replay。

### D3. 双 LSU 的进入条件

当前 data RAM/bridge 是单请求端口。只有以下条件同时满足才评估双 LSU：

- 动态统计显示 LSU 端口长期饱和；
- memory 可以 bank 化，或引入双端口 D-cache/scratchpad；
- load/store 地址冲突和 MMIO 顺序已有完整验证。

在此之前复制第二套 LSU 只会增加选择和仲裁，不会增加实际内存吞吐。

## 8. 前端结构演进

### E1. Fetch block queue

把当前“两条指令直接送 issue”改成 fetch block queue。每个 block 保存基地址、有效指令 mask、预测 taken slot、预测目标和 predictor checkpoint。后端停顿时前端可以继续积累多个 block，redirect 时按 checkpoint 丢弃错误路径。

它与单纯扩大 instruction queue 不同：重点是把预测、取指返回和 decode/dispatch 解耦，而不是只增加相同粒度的队列深度。

### E2. 预测器后续候选

现有 128-entry BTB、2-bit counter、JALR prediction 和 RAS 已覆盖主要低成本收益。后续只在动态 trace 证明需要时考虑：

- 2-way BTB，缓解直接映射冲突；
- 小型 global-history/gshare，改善相关条件分支；
- loop predictor，减少稳定计数循环退出误判；
- indirect target cache，处理单 PC 多目标 JALR。

预测器升级应晚于 ROB 和独立执行，因为当前 RETURN miss 已只有 11，后端 stall 的收益空间更大。

### E3. 宏操作融合

可以在 decode/dispatch 前识别常见 RISC-V 指令对，并作为一个内部 uop 执行、两个架构指令退休：

- `AUIPC + JALR`；
- `LUI + ADDI`；
- 地址生成 `ADD/ADDI + load/store`；
- 比较结果只供紧随 branch 使用的模式。

融合能降低 issue/ROB 压力，但必须保留两个 PC、两个 instret 和逐条异常语义。优先级低于独立 M 和小 ROB，只有真实 trace 显示对应模式频繁时实施。

## 9. 发射宽度与执行资源

推荐长期保持 2-wide dispatch/commit，执行资源采用非对称配置：

```text
2 x integer ALU
1 x branch unit
1 x LSU
1 x pipelined multiplier
1 x iterative/pipelined divider
```

在有限乱序下，2-wide 的利用率通常会明显高于 3-wide 顺序发射。只有同时满足以下条件才进入 3-wide：

- 2-wide issue 连续多周期满发；
- ROB/issue window 中经常存在第三条 ready 指令；
- ALU 和寄存器端口而不是 LSU/M/branch 是主要瓶颈；
- 每秒提交指令数的预估收益足以覆盖额外端口和选择网络。

若实施 3-wide，仍建议非对称：两个完整整数槽 + 一个简单 ALU 槽，并限制每拍最多两个 GPR 写回。4-wide 不作为当前 FPGA 的主线目标。

## 10. Cache 与更大存储系统

当前程序和数据位于片上 BRAM，cache 不会天然带来命中延迟收益。只有代码/数据迁移到 DDR、AXI 或其他高延迟存储后，再引入：

- 2-way I-cache + next-line prefetch；
- write-back/write-through D-cache；
- MSHR 和 non-blocking load；
- stride/stream prefetcher。

如果仍使用片上 RAM，更实际的结构是 banked scratchpad，而不是套一层 cache 标签和替换逻辑。

## 11. 不建议优先投入的方向

- 继续加深严格顺序 issue queue：已经证明不能解除队首阻塞；
- 直接做对称 3/4-wide：寄存器端口和依赖矩阵成本先增长，实际利用率不足；
- 大规模同周期跨 lane 旁路：IPC 收益有限，后续应由 tag/result network 取代；
- 在单端口 RAM 上复制 LSU：没有额外内存带宽；
- 在 ROB 之前做激进 store buffer 或推测 load：恢复和精确异常边界不完整；
- 继续扩大 RAS 或为当前 benchmark 过拟合预测器：现有返回预测已经接近饱和。

## 12. 推荐实施顺序

| 顺序 | 结构阶段 | 主要目标 | 继续条件 |
| ---: | --- | --- | --- |
| 1 | A1 ROB + 独立 lane 完成 | 移除原子 bundle 锁步 | M/ALU 能不同周期完成且按序退休 |
| 2 | A2 scoreboard + A3 M queue | 隐藏乘除长延迟 | MEXT 与真实程序 cycles 明显下降 |
| 3 | B oldest-ready issue window | 绕过队首 RAW/结构阻塞 | ready 指令绕过次数和 IPC 有稳定收益 |
| 4 | D1 store queue | 支撑精确乱序执行 | store/LSU 动态画像证明需要 |
| 5 | C physical rename | 移除 WAR/WAW | 假相关仍是显著阻塞来源 |
| 6 | D2 load queue / memory disambiguation | 提高 LSU 并行度 | 内存依赖阻塞占比足够高 |
| 7 | E1 fetch block queue | 前后端解耦 | 后端已能持续消费且前端空泡可见 |
| 8 | 预测器、融合、3-wide | 针对剩余瓶颈 | 必须由真实动态 trace 触发 |

## 13. 结构验证与性能计数

进入 ROB/乱序完成后，现有固定 PC 冒烟测试不够。必须建立按 commit 顺序的差分 trace，至少包含：

```text
rob_tag, pc, inst, rd/value, store addr/data/mask,
csr write, exception, interrupt, branch result
```

建议新增计数器：

- ROB occupancy 分布、ROB full cycles；
- issue window occupancy、无 ready 指令周期；
- ALU/LSU/M/DIV 利用率；
- source-not-ready、WAR/WAW、结构冲突周期；
- M latency 被其他指令覆盖的周期数；
- load 等待旧 store、store-to-load forward 和 replay 次数；
- branch flush 丢弃的 ROB/issue 项数；
- 1/2-wide dispatch、issue、commit 分布。

每个阶段都同时比较 cycles、IPC、目标频率下的每秒退休指令、资源和完整差分结果。若新增结构只提高局部计数但没有降低总 cycles，应立即停止扩展。

## 14. 最终建议

下一代结构不要以“更宽的顺序多发”作为主轴，而应以 8-entry ROB 为中心，把当前双 lane 改造成独立执行、tagged completion、有序退休。先用保守 scoreboard 和单请求 M queue 获得大部分长延迟隐藏收益，再根据动态数据决定是否加入 oldest-ready 调度、重命名和 LSQ。

这条路线能够最大程度复用当前双 ALU、双 decode、分支预测、精确 lane 年龄和双 commit 基础；同时各模块都有明确 token/tag 接口，适合后续再单独拆分流水线以提高频率。
