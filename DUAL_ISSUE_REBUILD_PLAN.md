# 顺序双发 CPU 重构实施计划

日期：2026-07-13  
用途：本文件是重置对话上下文后的实施入口。后续实现应先完整阅读本文件，再查看文末列出的历史文档；不要从已经回退的 P7A 代码或当前 P5 双发 RTL 直接继续修改。

## 1. 结论与目标

本轮从最后一个经过完整官方 RTL 回归的单发 L0 提交重新构建顺序双发架构。设计从第一天就按双取指、双发射、双写回和精确顺序提交规划，但首版配对规则可以保守扩展。

主要目标：

- 目标器件：`xc7k325tffg900-2`。
- 目标频率：优先争取 `200 MHz`，对应周期 `5.000 ns`；最低阶段目标为稳定超过 `175 MHz`。
- IF、Issue、Decode 之间用注册边界切断长组合路径。
- BTB 保持 128 项，改为与 IROM 一致的单周期同步读。
- IF 与 Issue 之间使用双入双出 Fetch FIFO。
- Issue 只做最小预译码、配对和结构/包内相关检查，并通过 bundle FIFO 与 Decode 隔离。
- GPR 从 FIFO 头部发起同步读；Decode 与 EX 之间仍保留流水线寄存器，但两级之间使用局部组合握手，不额外注册握手信号。
- EX 模块化；分支、LSU、乘法、除法等单元均提供局部 `start/busy/done` 或等价 stall 接口。
- 所有多周期等待集中在 EX。Load 在 EX 驻留四拍，Store 在 EX 仅额外停一拍；EX 到 MEM 必须是注册边界。
- `flush/kill` 是随指令传递的“禁止消费”标志。EX 及以后阶段看到 kill 后不得产生任何架构副作用，也不得启动或等待多周期单元。
- 功能正确性、九窗口 sink、异常数和 IPC 优先于频率；不得用 false path 或临时禁止关键双发能力掩盖错误。

## 2. Git 基线与分支策略

### 2.1 RTL 实现基线

新实现必须从以下提交创建独立分支：

```text
774f8ce974a9e10f7ffcf4f0a9117aa6fe31e18b
feat: establish L0 commit and performance baseline
```

选择原因：

- 这是引入双发架构之前的单发 L0 检查点，结构比当前 P5 简单。
- 已记录 QuestaSim 2024.1 全量编译 `0 errors / 0 warnings`。
- `run_all.bat all` 和当时的 77/77 ISA 回归通过。
- 已具备精确 `instret`、性能窗口和 commit/store trace，可作为重构时的功能参照。

当前工作分支和提交仅作为历史与测试夹具来源：

```text
branch: codex/multi-issue-inorder
HEAD:   bf94455 checkpoint: archive P7A rollback findings
remote baseline: d8742af (tag: p5-175mhz-checkpoint-20260712)
```

不要从 `bf94455` 或 `d8742af` 直接删除双发逻辑来构造新架构。它们包含多轮局部时序修补和已经暴露出边界问题的握手关系，只用于参考配对规则、性能计数、九窗口 benchmark 和失败教训。

建议新分支名：

```text
codex/dual-issue-rebuild-v1
```

建议使用独立 worktree，避免污染当前历史分支：

```powershell
git worktree add F:\riscv-cpu-dual-rebuild -b codex/dual-issue-rebuild-v1 774f8ce974a9e10f7ffcf4f0a9117aa6fe31e18b
```

创建分支后的第一个提交只做两件事：移入本计划，以及冻结九窗口测试夹具；不要在同一提交修改 RTL。

### 2.2 提交与回退规则

每个阶段都必须形成一个“编译通过、定向测试通过”的小提交。建议提交顺序：

1. `docs/test: freeze rebuild plan and nine-window fixture`
2. `frontend: add synchronous dual-lane IROM/BTB request stage`
3. `frontend: add dual-push dual-pop fetch FIFO and epoch recovery`
4. `issue: add pairing-only stage and atomic bundle FIFO`
5. `regfile: add synchronous 4R2W read launch and bypass`
6. `execute: add dual-lane modular EX shell and local hold protocol`
7. `lsu: add blocking four-beat load and two-beat store protocol`
8. `commit: add precise dual-lane MEM/WB side effects and counters`
9. `test: sign off official RTL regression and nine-window IPC`

每次提交前记录测试日志。若某阶段长时间无法修复，回退该阶段提交，不要在稳定提交上堆积临时 bypass、全局 stall 或关闭双发能力的补丁。禁止覆盖或误删用户已有的 `hex/riscv-tests/rv32-p-riscv.hex`。

## 3. 目标流水线

```text
IF0
  PC / PC+4，发起双路同步 IROM 与双路同步 BTB 查询
    |
IF1
  接收两条指令和对应预测元数据，形成 0/1/2 条 fetch uop
    |
Fetch FIFO
  2 push / 2 peek / 0-2 pop，保存 PC、inst、预测、epoch、age
    |
Issue
  仅做最小预译码、配对、包内 RAW/WAW 与结构检查
    |
Issue->Decode Bundle FIFO
  原子保存 lane0/lane1；lane0 永远更老
    |
RF launch / Decode
  FIFO 头同时驱动四个同步 GPR 读地址；锁存 bundle 元数据
    |
ID/EX register
  Decode 与 EX 之间保留寄存器；allowin/hold 为局部组合握手
    |
EX resident bundle
  forwarding + ALU/branch/LSU/mul/div 独立模块；多周期指令在此驻留
    |
EX/MEM register
  固定注册隔离，不使用 FIFO
    |
MEM / commit
  load 对齐、异常优先级、store/CSR/GPR 架构副作用、双退休
    |
MEM/WB register -> WB
```

全局原则：FIFO 用于吸收前端吞吐波动；Decode、EX、MEM 之间是有 resident-valid 的固定流水线寄存器，不用 FIFO 隐藏后端顺序和异常问题。

## 4. 前端设计

### 4.1 同步双取指 IROM

- 每拍查询 `PC` 和 `PC+4`，IF1 下一拍取得两条指令。
- 实现可以使用双端口 IROM，或复制两份只读存储体；两路内容必须一致。
- 请求时锁存 packet base PC、epoch 和 lane tag，响应必须按 tag 对齐，不能依赖下一拍的当前 PC。
- IF1 最多向 Fetch FIFO 推入两条 uop；FIFO 空间不足时必须整体保持响应 packet，不得只丢 lane1。

### 4.2 128 项同步 BTB

- 保持 128 项 direct-mapped 结构、tag、target、类型和 2-bit 饱和计数器。
- 为 `PC` 和 `PC+4` 提供两个同步查询口。优先采用两个读副本，commit/update 广播到所有副本。
- 查询请求与 IROM 同拍发出，IF1 同拍获得指令和预测元数据。
- BTB 更新必须带有效位、更新 PC、实际 target、taken 和 branch 类型；读写同地址的行为应在 RTL 中显式定义并测试。
- 保留 RAS 的规划。可沿用 8 深度，但推测更新和提交/恢复必须带 epoch 或 age，不能依赖同周期 IROM decode 闭环。

双取指预测规则：

- lane0 预测 taken：lane1 标记无效，下一个请求 PC 为 lane0 target。
- lane0 不 taken、lane1 预测 taken：两条均有效，下一个请求 PC 为 lane1 target。
- 两条均不 taken：下一个请求 PC 为 `PC+8`。
- 后端 redirect 优先级最高，产生新 epoch；旧 epoch 的 FIFO 项不得执行。

### 4.3 Fetch FIFO

建议首版深度 8 条 uop，接口至少支持：

```text
push_count = 0/1/2
pop_count  = 0/1/2
peek lane0/lane1
occupancy/free_count
redirect_epoch
```

FIFO 每项至少保存：

```text
valid, epoch, age, pc, inst,
pred_taken, pred_target, pred_type, btb_hit, ras_metadata
```

redirect 后可以清空 FIFO 计数，也可以依靠 epoch 丢弃旧项；无论采用哪种方式，都必须证明不会把旧 epoch uop 配入新 packet。

## 5. 发射与同步寄存器堆

### 5.1 Issue 只做配对

Issue 不执行 forwarding、分支决策、访存控制、异常提交或全流水线 stall 传播。它只完成配对所必需的最小预译码：指令类别、源/目的寄存器使用、控制/LSU/MULDIV 类型。

首版允许保守白名单，但数据结构从一开始支持两条有效 uop：

- `simple + simple`，两条独立整数指令；
- `simple + control`，仅在 lane1 控制流年龄和 redirect 已有定向测试后开放；
- `simple + LSU`、`LSU + simple`，仅在单 LSU 端口及顺序副作用规则完成后开放；
- MULDIV 配对在模块化 EX 稳定后开放。

包内规则：

- lane0 永远比 lane1 老。
- RAW 和 WAW 首版禁止双发；x0 不形成依赖。
- WAR 不阻止顺序双发。
- 若不能配对，只弹出 lane0，lane1 留在 Fetch FIFO 成为下一拍最老指令。
- Issue 输出 bundle 原子进入 Issue->Decode FIFO；redirect、exception 或 epoch 变化不能留下半个 bundle。

### 5.2 Issue->Decode Bundle FIFO

建议深度 2 或 4 个 bundle。每项同时携带 lane0/lane1，禁止两个 lane 分别 ready。该 FIFO 用于切断配对逻辑到 Decode/RF launch 的路径，不得变成可越过老指令的 issue window。

### 5.3 同步 4R2W GPR

GPR 目标接口为四读两写。首版优先使用 FF/LUTRAM 复制实现注册读，不强行推断 BRAM；32x32 的 4R2W 用 BRAM 会带来复制、一致性和读写语义复杂度。

时序约定：

1. Issue->Decode FIFO 头部组合产生两条指令的四个 `rs` 地址。
2. 弹出 bundle 的时钟沿同时启动/锁存同步读，并锁存 PC、inst、epoch、kill 和控制元数据。
3. 下一拍 RF 数据与对应 bundle 一起进入 Decode resident。
4. Decode 到 EX 仍有 ID/EX 寄存器；EX 的局部 allowin 可以组合返回 Decode，但路径只能包含 valid/busy/ready，不得包含 ALU、branch compare 或 DRAM 数据 mux。

必须保留：

- x0 恒为 0；
- 两个 WB 写口，lane1/年轻写与 lane0 写同一目的时的明确优先级；正常情况下 WAW 已在 issue 阻止；
- WB-to-synchronous-read bypass；
- EX/MEM/WB forwarding；
- 读地址发起后 bundle 被 hold/kill 时，读数据仍与原 tag 对齐；
- load 和 mul/div 结果在 `done` 前标记 pending，不能旁路旧数据。

## 6. 模块化 EX 与局部停顿

建议统一执行单元协议：

```text
req_valid/start       // 对同一 resident uop 只脉冲一次
req operands/control
busy
done/response_valid
result
exception metadata
```

单周期 ALU 可以视为 `done=1`。Branch、LSU、MUL、DIV 均为独立模块；共享单元要显式仲裁 lane0/lane1，lane0 优先。

EX bundle 只观察本 bundle 实际选中的单元：

```text
ex_hold = selected_valid && !selected_done
```

不得把所有模块的 stall 简单 OR 成高扇出全局链。`start` 在 EX 首拍发出一次，EX hold 期间不得重复发请求或重复更新状态。

初始结构资源建议：

- 两个简单整数 ALU；
- 一个 branch/redirect 单元；
- 一个 LSU/AGU；
- 一个共享 multiplier；
- 一个共享 divider；
- CSR/系统指令按老序串行处理。

## 7. 四拍 Load、两拍 Store 与 MEM 边界

### 7.1 Load 时序

Load 从进入 EX 的首拍起共驻留四拍：

```text
E0：计算地址、字节选择和异常；发出已注册的 LSU request
E1：请求进入 BRAM/bridge；EX hold
E2：BRAM 输出及 bridge 选择/响应寄存；EX hold
E3：response_valid 和数据到达；EX 不再 hold，指令与数据同拍进入 EX/MEM 寄存器
```

实现不能只延迟 `rdata`。request/response 必须携带并对齐：

```text
valid, epoch/age, lane, kill,
address, size, signedness, destination,
writeback select, alignment/exception metadata
```

首版可以是 blocking、单 outstanding LSU，因为 EX 本身驻留并阻止年轻 bundle 越过。接口仍应保留 tag/valid，使后续增加请求队列时不必重写协议。

### 7.2 Store 时序

Store 不等待读响应，EX 只额外停一拍：

```text
E0：计算地址、写数据、mask 和异常，形成 store command
E1：command 被注册，EX 完成并进入 MEM
MEM：在 valid && !kill && !older_exception 时产生唯一一次实际写副作用
```

关键限制：不得在 E0/E1 直接拉高最终 DRAM `WEA`。Store 的真实副作用必须在 MEM/commit 点发生，否则无法处理 lane0 异常、lane1 kill、外部中断和错误路径 store。

### 7.3 MEM/commit

- EX/MEM 是固定注册边界，不使用 FIFO。
- Load 对齐、符号扩展及最终异常信息在 MEM 完成。
- lane0 异常或 redirect 必须阻止同 bundle lane1 的所有副作用。
- 双 lane GPR/CSR/store/retire 的优先级按年龄固定。
- store、CSR、fence、mret 等不写 GPR 的正常指令也必须正确退休。
- killed uop 不退休、不写 GPR/CSR/memory、不更新 predictor、不产生异常。

## 8. flush、redirect、kill 的唯一语义

不要继续复用一个模糊的全局 `flush` 同时表示清寄存器、redirect 和禁止提交。统一拆成：

- `redirect_event`：由有效且未 kill 的控制流/异常产生，携带新 PC 和新 epoch，作用于 IF 与两个前端 FIFO。
- `kill`：随每条 uop 传递的 sticky 标志，表示该 uop 不应被消费。

EX 及以后阶段对 kill 的处理只有一种：把它当作无副作用 bubble 向后排空。

```text
kill => no unit start
kill => no EX hold/busy wait
kill => no memory request or store write
kill => no redirect or predictor update
kill => no GPR/CSR write
kill => no exception/trap and no retire
```

不能在多个后端模块用异步/组合 flush 清 resident valid；这会重新引入跨级控制长路径，并可能造成“请求已取消但 MEM 仍等 response”的 P7A 死锁。

## 9. Hazard、forwarding 与双发顺序

从第一版建立显式阶段状态：

```text
decode lane0/lane1: valid, dest, pending, kill
ex     lane0/lane1: valid, dest, pending, kill
mem    lane0/lane1: valid, dest, result_valid, kill
wb     lane0/lane1: valid, dest, result_valid, kill
```

规则：

- Issue 只处理同 bundle 的 RAW/WAW 和结构冲突。
- 跨 bundle 依赖由 Decode/EX hazard 和 forwarding 处理。
- ALU 结果在实际可用阶段直接 forward；load 仅在 E3 response 到达后可用；mul/div 仅在 done 后可用。
- 当老 producer 仍 pending 时，年轻 consumer 必须停在 Decode 或更前，不得把旧 RF 值锁存成最终操作数。
- lane0 结果不得在没有专门同包 bypass 的情况下供同 bundle lane1 使用；首版直接禁止此类 RAW 配对。
- 后端只允许整个 EX bundle hold/advance，避免 lane1 越过 lane0。

## 10. 实施阶段与阶段验收

### A0：冻结基线与测试

- 从 `774f8ce` 创建新分支/worktree。
- 保存本文件、九窗口源码/HEX/testbench 和 SHA256。
- 在未改 RTL 前运行 `run_all.bat all`。
- 把九窗口 testbench 的后续双发层次观察改为可选，不改变软件、邮箱布局、golden sink 或窗口定义。
- 先得到新分支单发 RTL 跑同一九窗口镜像的基准数据；没有该数据不得开始比较 IPC。

### A1：同步双取指与 BTB

- 建立 IF0/IF1、双路同步 IROM 和 128 项双查询同步 BTB。
- 暂时仍可单条送入后端，以先验证 PC/redirect/RAS。
- 定向覆盖 lane0 taken、lane1 taken、同地址 BTB update/read、JAL/JALR/return。

### A2：两个前端 FIFO 与 pairing-only Issue

- Fetch FIFO 支持 2 push/2 pop。
- Issue->Decode FIFO 保存原子 bundle。
- 先开放 independent simple+simple。
- 验证 full/empty/wrap、同拍 push/pop、redirect epoch 和不能配对时 pop1。

### A3：同步 GPR 与双 lane 数据通路

- 完成 4R2W 同步读、双 WB bypass、ID/EX 寄存和 stage scoreboard。
- 首先只跑双 ALU，再逐步开放控制流。

### A4：模块化 EX

- 分离 ALU、branch、mul、div、LSU 壳层。
- 验证 start 单脉冲、busy hold、done release、kill 不启动单元。

### A5：四拍 LSU 与精确 MEM

- 实现 load E0-E3 和 store E0-E1。
- Store 只在 MEM 有一次副作用。
- 完成 load/store 与 lane0/lane1 年龄、异常和 redirect 的组合测试。

### A6：逐步扩展配对

按以下顺序逐项开放，每项独立提交并跑完整回归：

1. `simple + simple`
2. `simple + control`
3. `simple + LSU` / `LSU + simple`
4. `simple + MULDIV` / `MULDIV + simple`

不得为了 IPC 一次开放全部组合。

### A7：性能恢复与 200 MHz 时序收敛

A7 在最终时序签核前先完成可观测性、性能恢复与安全执行域融合，按以下子阶段独立提交、回归和九窗口签核，不得跨阶段混入未经验证的白名单扩展：

1. **A7.1 性能可观测性与冻结基线**
   - 使用冻结 `tb_uart_benchmark` 外的 measurement-only probe，记录前端 request/packet/uop、单 uop packet、Issue 可接收但 Fetch FIFO 为空、实际 dual launch、实际 simple pair、双退休、pair 回退 legacy、prefer-legacy 回退、等待 legacy 排空和等待 dual resident。
   - probe 只观察既有层次信号，不修改 RTL、`test/tb_top.sv`、21-word 报告、软件、HEX 或 golden。
   - 以 A6.4 九窗口为基线，要求 cycles/instret/IPC、sink、exceptions 和原报告 21 项逐窗口完全不变，并检查 `actual dual launch = simple + control + LSU + MULDIV` 与 `fetch uops = 2 * packets - single packets`。
2. **A7.2 前端连续取指请求**
   - 消除 `req_valid` 导致的隔拍请求，在同步 IROM 一拍响应条件下允许每拍接受一个新的 PC/PC+4 request。
   - request/response 必须携带 PC、epoch、BTB/RAS 快照；redirect 同拍及迟到 response 不得进入 Fetch FIFO。
   - 定向覆盖连续 request、backpressure、slot0 taken 单 uop packet、lane1 taken、redirect in-flight 和 FIFO full/release；九窗口必须报告供给率与 IPC A/B。
3. **A7.3 降低 dual/legacy 域切换**
   - 优先使 dual 数据通路接收可安全执行的 singleton simple uop，使 RAW/WAW 拆单或短片段不必仅因未配对而切回 legacy。
   - 以实际 dual launch、legacy pair fallback、legacy drain wait 和双退休计数签核；不得绕过老指令排空、异常年龄、Store commit 或 shared-unit exclusion。
4. **A7.4 数据驱动的选择性配对**
   - 只根据 A7.1–A7.3 数据选择候选；优先评估纯 simple WAW younger-wins、单周期 simple RAW lane0->lane1 bypass、bitman+simple 和 control0+simple1 精确取消。
   - 双 LSU、双 MULDIV 在没有新增物理端口/执行单元时继续禁止；当前原子 LSU resident 下不得仅为提高配对计数放宽门限。
5. **A7.5 消除安全 singleton 的空退役与域切换**
   - measurement probe 增加零退役、Dispatch 零退役、control/MULDIV singleton、legacy→dual 和 dual→legacy 计数。
   - 只把已经具备完整执行、kill、异常和退休语义的 lane0 control 与 MULDIV singleton 纳入 dual backend；LSU singleton/isolated pair 保留原成本门限。
   - `MULDIV_PAIR` 等既有事件继续只统计真正双 lane bundle；所有 singleton 只退休 lane0，禁止制造 lane1 或 pair-class 事件。
6. **A7.6 200 MHz 最终收敛**
   - 功能和九窗口性能门槛通过后再做综合/实现。
   - 首先检查 RF output -> forwarding -> ALU/branch/AGU，以及 Fetch FIFO peek -> pairing -> bundle FIFO write。
   - 若 5.000 ns 未通过，只在报告指出的边界增加寄存，不进行平均切拍；每次时序改动都重新运行九窗口 IPC A/B。

## 11. RTL 回归计划

### 11.1 官方/现有回归

基线完整命令：

```powershell
cd F:\riscv-cpu-dual-rebuild
cmd /c run_all.bat all
```

验收要求：

- 全 RTL 与 testbench 编译 `0 errors / 0 warnings`。
- `run_all.bat all` 全通过；以 `774f8ce` 记录的 77/77 为最低基准。
- 不允许只跑 `base` 后声明官方回归通过。
- 每次运行后恢复并检查 `hex/riscv-tests/rv32-p-riscv.hex`，该文件会被 batch 测试覆盖。

必须保留或重建的定向测试：

```text
tb_perf_counters
tb_issue_stage
tb_mem_commit
tb_my_cpu
tb_if_sync_btb
tb_fetch_fifo_2wide
tb_issue_bundle_fifo
tb_sync_regfile_bypass
tb_ex_modular_hold
tb_ex_pipeline_forwarding
tb_ex_pipeline_branch_flush
tb_lsu_four_beat_load
tb_lsu_store_commit
tb_lsu_store_load_order
tb_lsu_exception_age
```

关键断言：

- lane0/lane1 PC 与 age 单调；
- killed uop 无任何副作用；
- 每个 LSU/MULDIV resident uop 只产生一次 start 和一次完成；
- store 写使能只出现一次且位于 commit；
- FIFO 计数不越界，redirect 后无旧 epoch 执行；
- 每拍退休 0/1/2，lane1 不得在 lane0 异常时退休。

## 12. 九窗口 IPC benchmark：必须原样保留

### 12.1 测试内容

当前 benchmark 包含九个独立性能窗口：

```text
ALU
MEXT
BRANCH_RANDOM
BRANCH_REGULAR
BRANCH_SHORT
BRANCH_CALL
BRANCH_CAPACITY
BRANCH_RETURN
MEMORY
```

每个窗口保存 21 个 32-bit word，核心字段包括：

```text
cycles, instret, branch, branch_mispredict, branch_hit, branch_miss,
load_use, exe_stall, exception, dual_issue, single_issue,
issue_raw, issue_waw, issue_struct, lsu_pair, lane1_control,
lsu_conflict, bitman_pair, cross_packet, issue_qfull, multidep
```

当前 testbench 契约：

```text
top               tb_uart_benchmark
mailbox base      0x6000_0800
magic             0x4C33_4A30  ("L3J0")
version           5
expected sink     0x9D3B_F787
window count      9
timeout           5,000,000 CPU cycles
```

README 中仍有 `0x6000_0700` 和旧 L3E 表述，实施时以 `test/tb_top.sv`、`linker.ld` 和本节的 `0x6000_0800` 为准，并应同步修正文档，不能改回旧邮箱。

### 12.2 必须冻结的文件

九窗口夹具从当前 `bf94455` 工作树选择性移植，不能整体 cherry-pick P5/P7 RTL：

```text
riscv_sim_perf_bench/benchmark.c
riscv_sim_perf_bench/startup.S
riscv_sim_perf_bench/linker.ld
riscv_sim_perf_bench/Makefile
riscv_sim_perf_bench/out/inst.hex
riscv_sim_perf_bench/out/data.hex
test/tb_top.sv
```

当前 SHA256：

```text
test/tb_top.sv
2672EEF7D95902293E4C17E4074AC675CB313A2AE58AB2BF14C7B37E0E799170

riscv_sim_perf_bench/benchmark.c
B91D22759F82E3872A65796ED23BF935F0C12E6BE876A29AFB56081A8AA34D5F

riscv_sim_perf_bench/startup.S
9FFC7C4A74EB76CA7EC68EDB6C3255B415ABAB87B6E46234E57D8F0842A5E514

riscv_sim_perf_bench/linker.ld
42D11987DE1AC460D50AB2DD614305890EB354D3AD9C8D70C665A93B230A361A

riscv_sim_perf_bench/Makefile
D4651025676521709768C1BBA5EB7885EA5D9D7204104B1CC4896BCA16E3CCF3

riscv_sim_perf_bench/out/inst.hex
459D81149CDD2A8886AE58F32AD27F58976AEECB82844B9BF4B1174FE96F9C7C

riscv_sim_perf_bench/out/data.hex
DDB214EE5E790F797FD84456E23DB9CBFF3DCA8E37DF59DC7AD8EB3EB409364B
```

`test/tb_top.sv` 当前含有 P5 issue queue 的层次观察信号。移植到新架构时可以改写这些观察路径，但必须保持九个窗口、邮箱布局、magic/version、sink 检查、exceptions 检查和 overall IPC 算法不变。

### 12.3 构建与运行

预生成 `out/inst.hex` 和 `out/data.hex` 是默认签核镜像。正常 RTL A/B 不要重新生成它们，以确保前后使用完全相同的程序。

需要重建软件时，在 WSL 中执行，并把编译器版本和新 SHA256 一并提交：

```powershell
wsl.exe -d Ubuntu-22.04 -- bash -lc "cd /mnt/f/riscv-cpu-dual-rebuild/riscv_sim_perf_bench && make clean && make"
```

Questa 运行示例：

```powershell
vlog -sv +define+PERF_BENCH +define+DEBUG_EN `
  +incdir+rtl/cpu_top +incdir+rtl/my_cpu `
  rtl/cpu_top/*.sv rtl/cpu_top/*.svh `
  rtl/my_cpu/*.svh rtl/my_cpu/*.sv `
  test/*.sv

vsim -c -do "run -all; quit -force" tb_uart_benchmark `
  > results/nine_window_benchmark.txt
```

签核日志必须包含九条 report、overall 和 pass：

```text
L3J_REPORT name=...
L3J_OVERALL cycles=... instret=... ipc_x1000=...
PERF_BENCHMARK_PASSED
```

每次比较记录：

```text
每窗口 cycles / instret / IPC
overall cycles / instret / IPC
sink / exceptions
dual_issue / single_issue
RAW / WAW / struct reject
load-use / LSU stall / mul-div stall
branch / mispredict / RAS return
FIFO full / occupancy
```

### 12.4 当前已知参考数据与冲突

P5 回退版本的最近一次实测：

```text
cycles       1,790,178
instret      2,279,455
IPC              1.273
exceptions           0
actual sink  0x4A27AD51
TB expected  0x9D3BF787
```

历史 P5 签核文档曾记录同样 cycles/instret、`IPC=1.273`，但 sink 写为 `0x9D3BF787`。最近实测与文档不一致，且 P7 回退后仍为 `0x4A27AD51`。因此：

- `1.273` 只能作为 P5 性能参考，不能作为新单发基线，也不能视为当前完整签核通过。
- A0 必须先用冻结镜像在 `774f8ce` 移植环境中复现 sink；先判断是 fixture/编译器版本、testbench 层次适配还是 RTL 行为差异。
- 未确认 golden 来源前不得把 expected sink 改成 `0x4A27AD51` 来换取 PASS。
- 新架构正式验收仍以冻结 fixture 的 `0x9D3BF787`、九窗口 exceptions=0 为目标。

## 13. 本机工具环境

### 13.1 Windows / QuestaSim

已安装并可直接从 PowerShell PATH 调用：

```text
Questa Sim-64 2024.1
build string: Simulator 2024.02 Feb 1 2024
path: F:\questasim64_2024.1\win64
commands: vlog.exe, vopt.exe, vsim.exe
```

版本检查：

```powershell
vsim -version
```

当前未在 PATH 中检测到 Vivado。现有 P5 Vivado 报告位于忽略目录 `vivado-project/jyd2025-reference/artifacts/latest175_p5`；综合和实现仍由有 Vivado 环境的一侧执行，不要把 Questa 通过等同于 200 MHz 时序通过。

### 13.2 WSL 与 RISC-V 工具链

WSL 注册名称和实际系统版本不同，应按以下实际状态记录：

```text
registered distro: Ubuntu-22.04
WSL version:       2
actual userspace:  Ubuntu 24.04.3 LTS (Noble)
kernel:            6.18.33.2-microsoft-standard-WSL2
repo path:         /mnt/f/riscv-cpu-refactored
```

可用工具：

```text
/usr/bin/riscv64-unknown-elf-gcc
riscv64-unknown-elf-gcc (GCC) 15.2.0

/usr/bin/riscv64-unknown-elf-objcopy
GNU Binutils 2.45

/usr/bin/make
GNU Make 4.3

/usr/bin/iverilog
Icarus Verilog 12.0 stable
```

WSL 主要用于 benchmark C/汇编构建；正式 RTL 回归以 QuestaSim 2024.1 为准。

## 14. 频率与性能验收

功能验收：

- `run_all.bat all` 全通过，编译 0 error/0 warning。
- 新增 FIFO、同步 RF、模块化 EX、四拍 LSU 和 kill/age 定向测试全通过。
- 九窗口 `sink=0x9D3BF787`、exceptions=0、九窗口均只完成一次。
- 无错误提交、错误 store、年轻 lane 越过老 lane、重复 LSU 请求、错误 redirect 或 RAS 恢复。

性能验收：

- A0 先记录同一冻结镜像下的新单发基线 IPC。
- 每阶段报告绝对 IPC 和相对 A0 的变化，不只与 P5 的 1.273 比较。
- 双发版本 IPC 必须高于 A0；若因四拍 load 降低 overall IPC，应分别报告 MEMORY 与非 MEMORY 窗口。
- 最终比较 `IPC x Fmax`，不能只比较 IPC 或频率。

时序验收：

```text
target clock     200 MHz / 5.000 ns
setup WNS        >= 0
hold WPWS        >= 0
routing errors   0
```

若 200 MHz 不通过但 175 MHz 以上通过，保留报告并根据 `IPC x Fmax` 决定是否接受；不得宣称未实际实现的频率。

每个实现检查点记录：

```text
WNS / TNS / failing endpoints
WPWS / TPWS
LUT / FF / BRAM / DSP
overall 和九窗口 IPC
instret / cycle / sink / exceptions
branch mispredict / load-use / LSU stall / MULDIV stall
FIFO occupancy/full 和双发率
```

## 15. 已知教训与禁止事项

1. P7A 中 EX 输出端新增 LSU stall，但 ID 仍依据旧 `allowin` 前进，导致 resident load 被覆盖。新架构所有 hold/advance 必须由同一个 resident 状态机决定。
2. 被 flush 的 load 曾进入 MEM 等待一个永远不会到达的 response。kill uop 不得启动请求，也不得等待 done。
3. 临时禁止 lane1 control 虽能让 P7A benchmark 完成，但 IPC 降至 1.043，且没有修复 redirect 根因。新架构必须保留 lane1 control 的数据结构和定向测试，不能以永久关闭作为签核方案。
4. Store 不能在 EX 提前产生不可撤销副作用。
5. 不能只给最终 `dmem_rdata` 打拍；请求地址/使能和 BRAM/bridge response 必须分别注册并携带元数据。
6. 不能让 MEM ready 组合穿过 EX、Decode、Issue、IF；Decode/EX 仅允许局部短握手。
7. 不要在没有固定 ELF/HEX 和 SHA256 时比较 sink/IPC。
8. 不要同时实施同步 RF、全部配对、四拍 LSU 和新 BTB 后只跑一个大 benchmark；每一边界都必须先有 directed test 和独立提交。

## 16. 接手时首先执行

1. 阅读本文件和 `doc/latest175_p7_retrospective.md`。
2. 确认当前 `bf94455` 工作树干净，并保护用户的 HEX 修改。
3. 从完整 hash `774f8ce974a9e10f7ffcf4f0a9117aa6fe31e18b` 创建新 worktree/分支。
4. 把本文件和第 12.2 节列出的九窗口夹具作为第一个独立提交移入新分支。
5. 运行 `run_all.bat all`，保存原始日志。
6. 先完成 A0 的九窗口 fixture 适配和 golden/sink 复现，不修改 golden。
7. A0 通过后，严格按 A1 到 A7 顺序实施；每阶段提交、回归、记录 IPC。

历史参考：

- `doc/multi_issue_l0_checkpoint.md`：单发实现基线。
- `doc/latest175_p7_retrospective.md`：P7A 失败与回退教训。
- `doc/latest175_p5_signoff_checkpoint.md`：P5 时序瓶颈与历史 IPC。
- `riscv_sim_perf_bench/README.md`：benchmark 工程说明；邮箱地址以本文件第 12 节为准。

## 17. 执行状态与阶段签核表

本节是实施过程中的唯一状态入口。每个阶段开始、签核或回退时都要更新本节；阶段只有在代码、定向测试、回归日志和提交记录齐全后才能标记为完成。

当前工作区：

```text
worktree: F:\riscv-cpu-dual-rebuild
branch:   codex/dual-issue-rebuild-v1
baseline: 774f8ce974a9e10f7ffcf4f0a9117aa6fe31e18b
fixture:  65ee12efe65fb21fe6e0a812d34c927c3e9ee12e
```

状态定义：

```text
PENDING      尚未开始
IN_PROGRESS  正在实现或验证
SIGNED_OFF   阶段全部签核门槛通过
ROLLED_BACK  阶段失败并已回退到上一稳定提交
```

| 阶段 | 状态 | 实施范围 | 阶段签核门槛 |
| --- | --- | --- | --- |
| A0 | SIGNED_OFF | 单发基线、完整 RTL 回归、九窗口夹具适配与 golden/sink 复现 | `run_all.bat all` 全通过；编译 0 error/0 warning；夹具 SHA256 不变；记录九窗口单发 cycles/instret/IPC；exceptions=0；不修改 golden |
| A1 | SIGNED_OFF | IF0/IF1、同步双路 IROM、128 项同步双查询 BTB | PC/指令/预测 tag 对齐；lane0/lane1 taken、BTB 同址读写、JAL/JALR/return 定向测试通过；redirect/epoch 无旧路径执行 |
| A2 | SIGNED_OFF | 2 push/2 pop Fetch FIFO、原子 Bundle FIFO、pairing-only Issue | full/empty/wrap、同拍 push/pop、redirect epoch、pop1 全覆盖；bundle 不拆分；RAW/WAW 与结构冲突规则正确 |
| A3 | SIGNED_OFF | 同步 4R2W GPR、双 lane 数据通路、scoreboard 与 forwarding | x0、双写回、WB bypass、跨 bundle hazard、pending、hold/kill tag 对齐定向测试通过；双 ALU 回归通过 |
| A4 | SIGNED_OFF | 模块化 ALU/Branch/LSU/MUL/DIV 与局部 resident hold | 同一 uop 只 start/done 一次；hold 不覆盖 resident；kill 不启动或等待单元；branch/forwarding/MULDIV 定向测试通过 |
| A5 | SIGNED_OFF | 四拍 Load、两拍 Store、固定 EX/MEM、精确 MEM/commit | Load 请求/响应及 metadata 对齐；Store 只在 commit 写一次；异常年龄和 lane1 抑制正确；四项 LSU 定向测试通过 |
| A6 | SIGNED_OFF | 依次开放 simple、control、LSU、MULDIV 配对 | 每种配对独立提交并跑完整回归与九窗口；sink/exceptions 不变；lane1 不越过 lane0；记录双发率和拒绝原因 |
| A7 | IN_PROGRESS | A7.1 可观测性、A7.2 前端供给、A7.3 域切换、A7.4 选择性配对、A7.5 安全 singleton 驻留、A7.6 最终时序 | 每个子阶段独立提交、回归和九窗口 A/B；最终官方回归与全部定向测试通过；sink=`0x9D3BF787`、exceptions=0；以修正后有效退休口径报告 IPC，并同时记录相对 A0 的 cycles 与 `IPC x Fmax`；5.000 ns 下 setup/hold 通过，或如实记录 175 MHz 以上结果 |

### 17.1 每阶段统一签核流程

1. 开始前记录当前提交、工作树状态、测试夹具 SHA256 和受保护 HEX 状态。
2. 一个提交只改变一个架构边界；不得混入临时 bypass、全局 stall、false path 或关闭关键双发能力的补丁。
3. 先完成编译与该阶段 directed tests，再运行受影响的现有回归；A0、A6 每个子阶段和 A7 必须运行 `run_all.bat all`。
4. 九窗口 A/B 始终使用冻结的 `out/inst.hex` 和 `out/data.hex`；除非专门重建软件并记录编译器版本与新 SHA256，否则不得重新生成。
5. 每次测试后恢复并核对 `hex/riscv-tests/rv32-p-riscv.hex`，避免 batch 覆盖用户或基线内容。
6. 签核记录至少包含测试命令、日志路径、pass/fail、commit、cycles、instret、IPC、sink、exceptions，以及该阶段新增的断言或覆盖点。
7. 阶段通过后把状态改为 `SIGNED_OFF` 并提交文档；失败且无法在当前阶段干净修复时回退该阶段提交并标记 `ROLLED_BACK`。

### 17.2 当前进度

```text
2026-07-13  A0 SIGNED_OFF
              - created codex/dual-issue-rebuild-v1 from 774f8ce
              - froze rebuild plan and nine-window fixture in 65ee12e
              - verified all seven original fixture SHA256 values against section 12.2
              - adapted only P5-specific debug ports and optional queue hierarchy in test/tb_top.sv
              - run_all.bat all: 78/78 passed (1 perf-counter unit test + 77 ISA), 0 failed
              - nine-window: sink=0x9D3BF787, exceptions=0, IPC=0.824, PASS
              - protected rv32-p-riscv.hex remained at its pre-run SHA256
2026-07-13  A1 SIGNED_OFF
              - added synchronous PC/PC+4 IROM request and tagged IF0/IF1 response
              - added 128-entry replicated synchronous BTB, 2-bit counters and write-through
              - added branch/JAL/JALR/call/return types and an 8-entry resolved-update RAS
              - serialized IF1 packets into the old Decode with one backpressure prefetch slot
              - redirect epoch discards in-flight responses and resident/prefetched wrong-path packets
              - predictor, RAS, redirect and branch event share one branch_resolve_fire pulse
              - tb_if_sync_btb passed; run_all.bat all passed 78/78
              - nine-window: sink=0x9D3BF787, exceptions=0, IPC=0.832, PASS
              - next: begin A2 Fetch FIFO, atomic Bundle FIFO and pairing-only Issue
2026-07-13  A2 SIGNED_OFF
              - added an 8-uop Fetch FIFO with atomic 2-push and 0/1/2-pop
              - added pairing-only Issue and a 4-entry atomic Issue Bundle FIFO
              - first whitelist is independent simple+simple; RAW/WAW/structure rejects pop lane0 only
              - serialized each atomic bundle into the old single-uop Decode without an inter-lane bubble
              - added committed/speculative RAS recovery and same-edge call/return request bypass
              - four directed tests passed; run_all.bat all passed 78/78
              - nine-window: sink=0x9D3BF787, exceptions=0, IPC=0.821, PASS
              - A2 IPC is an expected interim regression while the old Decode remains single-lane
              - next: A3 synchronous 4R2W GPR, dual-lane datapath and scoreboard
2026-07-13  A3 SIGNED_OFF
              - preserve the legacy backend for single/control/LSU/MULDIV while A4/A5 are pending
              - added a dual path for supported independent two-lane integer ALU bundles
              - implement synchronous 4R2W, 2W commit, WB read bypass and explicit stage scoreboard
              - final legacy WB overlaps dual RF launch through same-edge bypass; dual commit may overlap younger legacy Decode intake
              - scoreboard, dispatch and 4R2W directed tests passed; run_all.bat all passed 78/78
              - nine-window: sink=0x9D3BF787, exceptions=0, IPC=0.815, PASS
              - A3 remains an interim performance regression until the legacy backend is replaced in A4/A5
              - next: A4 modular ALU/Branch/LSU/MUL/DIV and local resident hold
2026-07-13  A4 SIGNED_OFF
              - freeze A3 implementation commit f3d4b6a and protected HEX SHA256 before edits
              - split ALU, branch, LSU shell, multiplier and divider behind explicit local execution protocols
              - make the EX resident the sole owner of start-once, completion retention, kill and release
              - keep A3 dual-issue eligibility unchanged; A4 does not pre-open control/LSU/MULDIV pairing
              - defer four-cycle load, two-cycle store and precise memory side effects to A5
              - seven directed tests and all eight M-extension ISA tests passed
              - run_all.bat all passed 78/78 with compile 0 errors / 0 warnings
              - nine-window: sink=0x9D3BF787, exceptions=0, IPC=0.815, PASS; metrics exactly match A3
              - protected HEX and all frozen benchmark fixture hashes remained unchanged
              - next: A5 four-cycle Load, two-cycle Store, fixed EX/MEM and precise memory commit
2026-07-13  A5 SIGNED_OFF
              - freeze A4 signoff commit 19014ee and protected HEX SHA256 before edits
              - add an explicit bridge read-response-valid path and carry response data in EX/MEM metadata
              - make Load occupy E0-E3 and Store occupy E0-E1 under the EX resident owner
              - move the only physical Store write pulse from EX to precise MEM commit
              - arbitrate the single data port in age order: older MEM Store commit before younger EX LSU start
              - keep A3/A4 pairing whitelist unchanged; LSU dual pairing remains an A6 step
              - implementation commit c2f0ecd; 11/11 directed and 8/8 load/store ISA tests passed
              - run_all.bat all passed 78/78 with compile 0 errors / 0 warnings
              - nine-window: sink=0x9D3BF787, exceptions=0, IPC=0.758, PASS
              - protected HEX and all frozen benchmark fixture hashes remained unchanged
              - next: A6, open pairing classes one at a time with an independent commit and full signoff per class
2026-07-13  A6 SIGNED_OFF
              - freeze A5 signoff commit d5a0973 and protected HEX SHA256 before edits
              - A6.1 first freezes and independently signs off the existing simple+simple path
              - A6.2 only adds lane0 simple + lane1 control after precise redirect/age tests
              - A6.3 adds exactly one LSU per bundle with registered response and precise Store/exception commit
              - A6.4 adds exactly one shared MUL/DIV per bundle and holds both lanes until completion
              - every substage has a separate commit, directed tests, run_all.bat all and frozen nine-window run
              - A6.1 SIGNED_OFF in 40eb13a: unified simple predecode; 78/78 and nine-window PASS
              - A6.2 SIGNED_OFF in 7f063ba: lane0 simple + lane1 control; precise redirect/IAM; 78/78 and nine-window PASS
              - A6.3 SIGNED_OFF in 8fa3608: one LSU per pair, registered MEM/precise Store and LAM/SAM; 78/78 and nine-window PASS
              - A6.4 SIGNED_OFF in c2924e6: one shared MUL/DIV, atomic hold/retire and completion-edge bypass; 78/78 and nine-window PASS
              - A6 final: cycles=2999204, instret=2279454, ipc_x1000=760, sink=0x9D3BF787, exceptions=0
              - next: A7 final functional/performance audit and 200 MHz timing convergence
2026-07-13  A7 IN_PROGRESS
              - A7.1 SIGNED_OFF in 7640bee: measurement-only probe; no RTL or frozen fixture changes
              - A7.1 run_all.bat all passed 78/78; direct and wrapped nine-window reports match A6.4 exactly
              - A7.1 measured 354773 actual dual launches, 379273 legacy pair fallbacks and 458102 fetch-empty cycles
              - A7.2 SIGNED_OFF in 5ba2046: tagged live-response bypass plus one complete skid packet
              - A7.2 run_all.bat all passed 78/78; cycles=2831734, exact IPC=0.804968, sink/exceptions unchanged
              - A7.3 SIGNED_OFF in 2baec50: safe simple singleton residency; all A6 pair classes and cost gates unchanged
              - A7.3 directed tests passed 6/6 and run_all.bat all passed 78/78 with compile 0 errors / 0 warnings
              - A7.3 cycles=2686213, exact IPC=0.848575; sink/exceptions/hashes unchanged
              - A7.3 measured 197652 singleton launches and 435860 retire2 cycles; actual dual launches rose to 633512
              - A7.4.1 SIGNED_OFF in 6051e2d: older control0 + younger independent simple1, with precise lane1 kill on mispredict
              - A7.4.1 affected directed tests passed 8/8 and run_all.bat all passed 78/78; compile 0 errors / 0 warnings
              - A7.4.1 cycles=2454505, exact IPC=0.928682; sink/instret/branch/brmisp/exceptions/hashes unchanged
              - A7.4.1 measured 74506 control0 launches and 5308 lane1 kills; structural rejects fell from 145238 to 19971
              - A7.4.1 also qualified MEM exception outputs with ms_valid; this removed a stale-exception frontend redirect exposed by rv32mi-p-ma_fetch
              - WAW-only and bitman+simple each have zero frozen-workload opportunities; simple RAW remains deferred behind a separate timing gate
              - A7.5 SIGNED_OFF in ff35e70: lane0 control and MULDIV singleton reuse the existing dual branch/shared-unit residents
              - A7.5 affected directed tests passed 8/8 and run_all.bat all passed 78/78; compile 0 errors / 0 warnings
              - A7.5 cycles=2394076, exact IPC=0.952123; sink/instret/branch/brmisp/exceptions/hashes unchanged
              - A7.5 measured 91163 control-singleton and 2000 MULDIV-singleton launches; zero-retire cycles fell by 57686
              - dual-to-legacy transitions fell from 27420 to 8182; the remainder is concentrated at frozen LSU boundaries
              - A7.5.1 SIGNED_OFF in 5b451e8: fixed-four-beat LSU keeps dual residency only for a signed-off fast follower
              - A7.5.1 directed tests passed 8/8 and run_all.bat all passed 78/78; compile 0 errors / 0 warnings
              - A7.5.1 cycles=2285194, exact IPC=0.997488; sink/instret/branch/brmisp/exceptions/hashes unchanged
              - LSU pair launches rose from 8180 to 108164; MEMORY cycles fell by 92874 and RETURN by 16008
              - next: measure the remaining 8000 non-prefer domain exits before any deeper LSU change; A7.6 timing remains deferred
```

### 17.3 A0 签核记录

签核提交基线：

```text
RTL baseline:       774f8ce974a9e10f7ffcf4f0a9117aa6fe31e18b
fixture commit:     65ee12efe65fb21fe6e0a812d34c927c3e9ee12e
status tracker:     73e66e4
protected HEX SHA:  C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
adapted tb_top SHA: 77F2DABDCA7F9E0A7B179A8EA0FA9FE7FD031BD2EFBCF68A0F6067C7E0E59701
```

官方回归：

```text
command: cmd /c run_all.bat all
result:  78 passed / 0 failed
detail:  1 tb_perf_counters + 77 ISA tests
compile: QuestaSim 2024.1, 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a0\run_all_all_after_fixture.log
```

九窗口签核：

| Window | Cycles | Instret | IPC x1000 | Exceptions |
| --- | ---: | ---: | ---: | ---: |
| ALU | 216020 | 216015 | 999 | 0 |
| MEXT | 190033 | 54020 | 284 | 0 |
| BRANCH_RANDOM | 279812 | 257254 | 919 | 0 |
| BRANCH_REGULAR | 105030 | 99021 | 942 | 0 |
| BRANCH_SHORT | 111028 | 99019 | 891 | 0 |
| BRANCH_CALL | 204337 | 164127 | 803 | 0 |
| BRANCH_CAPACITY | 267281 | 135182 | 505 | 0 |
| BRANCH_RETURN | 1024052 | 848034 | 828 | 0 |
| MEMORY | 602331 | 601602 | 998 | 0 |
| **Overall** | **2999924** | **2474274** | **824** | **0** |

```text
command: vlog -sv +define+PERF_BENCH +define+DEBUG_EN ...
         vsim -c -do "run -all; quit -force" tb_uart_benchmark
header:  version=5, cpu_freq_hz=125000000, sink=0x9D3BF787
result:  PERF_BENCHMARK_PASSED
compile: 0 errors / 0 warnings
compile log: F:\Tools\temp\riscv-dual-rebuild-a0\nine_window_compile_final.log
run log:     F:\Tools\temp\riscv-dual-rebuild-a0\nine_window_benchmark_final.log
```

`test/tb_top.sv` 的 A0 适配只移除 L0 不存在的 P5 第二 lane debug 端口，并把 P5 issue queue 层次观察放到默认关闭的 `P5_ISSUE_QUEUE_PROFILE` 宏下。软件、预生成 HEX、21-word 报告布局、九个窗口、邮箱、magic/version、timeout、expected sink、exceptions 检查和 overall IPC 算法均未修改。

Questa 在仿真时刻 0 对 `rtl/cpu_top/divider.sv:43` 报告一次 `Infinity results from division operation` warning；它不属于编译 warning，未影响九窗口结果。后续 A4 模块化 Divider 时应消除该未初始化组合除法诊断。

### 17.4 A1 签核记录

实现提交：

```text
commit:  915e441e2de76932247ea3b9e4300e7b4fe99f6d
subject: frontend: add synchronous dual-lane IROM/BTB request stage
```

实现边界：

- `soc_inst_ram` 和 CPU IROM 接口增加 `PC+4` 同步读口；两路用同一个原子 request enable。
- IF0 锁存 packet PC、epoch 和 RAS top；IF1 同拍接收两路 IROM 与两路同步 BTB 响应。
- A1 仍向旧 Decode 每拍最多发送一条 uop，lane0/lane1 按年龄串行输出；一个最小预取 packet 槽只用于吸收 Decode backpressure，不执行 A2 的 FIFO、配对或双发功能。
- BTB 为 128 项 direct-mapped、双读副本、2-bit 饱和 counter，保存 tag、target 和 branch/JAL/JALR/call/return type；update 同步广播到两个副本。
- BTB 查询和 update 同索引时采用显式 write-through，新 tag 与新 counter/target/type 在该次同步响应中可见。
- RAS 深度 8，A1 采用已解析控制流单脉冲更新；return 查询优先使用随 request 锁存的 RAS top。
- redirect 翻转 epoch，并原子丢弃飞行中 IROM/BTB 响应、active packet 和 prefetch packet。
- EX 中的 redirect、predictor update、RAS update 和 branch 性能事件统一由 `branch_resolve_fire` 驱动，避免下游阻塞时重复消费。

定向测试：

```text
test:    tb_if_sync_btb
result:  IF SYNC BTB TEST PASSED
compile: QuestaSim 2024.1, 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a1-if-directed-final.log
```

覆盖点：

- 冷启动双路同步 IROM 的 PC/指令 tag 对齐和 lane0→lane1 年龄顺序；
- lane0 taken 使 lane1 无效，lane1 taken 保留两条并选择 lane1 target；
- BTB update/read 同址 write-through；
- JAL 与通用 JALR target；
- resolved call push 后 return 使用 RAS target；
- redirect 发生在 request in-flight 时旧 epoch response 不得输出；
- Decode stall 时 active uop 保持稳定、下一 packet 进入 prefetch，恢复后顺序不变。

官方回归：

```text
command: cmd /c run_all.bat all
result:  78 passed / 0 failed
detail:  1 tb_perf_counters + 77 ISA tests
compile: 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a1-run_all_all-final.log
```

九窗口签核：

| Window | Cycles | Instret | IPC x1000 | Brmisp | Exceptions |
| --- | ---: | ---: | ---: | ---: | ---: |
| ALU | 216022 | 216013 | 999 | 2 | 0 |
| MEXT | 192031 | 54016 | 281 | 4 | 0 |
| BRANCH_RANDOM | 293209 | 245975 | 838 | 9475 | 0 |
| BRANCH_REGULAR | 105036 | 96017 | 914 | 1505 | 0 |
| BRANCH_SHORT | 111036 | 93015 | 837 | 3005 | 0 |
| BRANCH_CALL | 184262 | 144022 | 781 | 4061 | 0 |
| BRANCH_CAPACITY | 138639 | 69133 | 498 | 1152 | 0 |
| BRANCH_RETURN | 848082 | 760025 | 896 | 16 | 0 |
| MEMORY | 648310 | 601238 | 927 | 185 | 0 |
| **Overall** | **2736627** | **2279454** | **832** | **19405** | **0** |

```text
header:      version=5, cpu_freq_hz=125000000, sink=0x9D3BF787
result:      PERF_BENCHMARK_PASSED
A0 overall:  cycles=2999924, instret=2474274, ipc_x1000=824
A1 overall:  cycles=2736627, instret=2279454, ipc_x1000=832
IPC change:  +8 x1000 (+0.97%)
compile log: F:\Tools\temp\riscv-dual-rebuild-a1-nine-window-compile-final.log
run log:     F:\Tools\temp\riscv-dual-rebuild-a1-nine-window-final.log
```

A1 发现 A0 的每个窗口都满足：

```text
A0 instret - A1 instret = A0 branch_mispredict
```

九窗口合计差值为 `2474274 - 2279454 = 194820`，也等于 A0 九窗口 mispredict 合计。根因是旧 `if_stage` 在 redirect 时把 `NOP_INST` 作为有效 uop 送入后端并退休；A1 的 epoch/valid 丢弃不再把错误路径 bubble 计入 `instret`。软件镜像、sink 和 exceptions 均未变化。后续 IPC 比较以保留该修正的 A1/A2 计数语义为准，同时继续通过 commit trace 断言保证真实指令不丢失。

### 17.5 A2 签核记录

实现提交：

```text
commit:  9ce9bd467e1d30b460b1b642f33bd4c5dd6876de
subject: frontend: add fetch and atomic issue bundle FIFOs
```

实现边界：

- IF1 以原子 packet 向深度 8 的 Fetch FIFO 推送 1/2 条 uop；每条 uop 保存 epoch、32-bit age、PC、指令及 BTB/RAS 预测 metadata。
- Fetch FIFO 支持 2 push、0/1/2 pop、回绕、同拍 push/pop 和 redirect clear；IF 只有在整包空间足够时才发送，不拆分双路响应。
- pairing-only Issue 首版只允许 independent `simple+simple`：LUI、AUIPC、OP-IMM 和非 M 的 OP；检测 lane0→lane1 RAW、WAW 及非白名单结构冲突，`x0` 不形成依赖。
- 深度 4 的 Issue Bundle FIFO 以 `{lane-valid, uop1, uop0}` 原子保存 bundle；不能配对时只弹出 lane0，lane1 保留为下一次最老 uop。
- A2 尚未改造 Decode/后端为双 lane；`bundle_decode_adapter` 连续两拍发送 lane0/lane1，并在 redirect 时清除 resident lane1。这是 A3 前的兼容边界，不代表已经实现双退休。
- RAS 分为 committed 与 speculative 两份：控制流解析更新 committed，packet 进入 Fetch FIFO 更新 speculative，redirect 用包含当前 resolving op 的 committed image 恢复；同拍 packet fire/request fire 对 call push 和 return pop 显式旁路。
- 新增 `dual_issue`、`single_issue`、`issue_raw`、`issue_waw`、`issue_struct`、`issue_qfull` 性能 CSR，并扩展清零/读回测试。

定向测试：

```text
test:    tb_perf_counters
result:  PERF COUNTER TEST PASSED
test:    tb_if_sync_btb
result:  IF SYNC BTB TEST PASSED
test:    tb_fetch_fifo_2wide
result:  FETCH FIFO 2WIDE TEST PASSED
test:    tb_issue_bundle_fifo
result:  ISSUE BUNDLE FIFO TEST PASSED
compile: QuestaSim 2024.1, 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a2-directed-final.log
```

覆盖点：

- Fetch FIFO empty/full、指针回绕、1/2 push、1/2 pop、同拍 push/pop、redirect clear、overflow/underflow assertion；
- 同一 IF packet 在空间不足时保持完整稳定，空间恢复后一次性推入，PC/指令、age/epoch 和预测 tag 对齐；
- independent simple+simple 原子成 bundle，Decode adapter 保持 lane0→lane1 顺序且中间无气泡；
- RAW、WAW、结构冲突均拒绝配对并只 pop lane0，`x0` 读写不制造假依赖；
- Bundle FIFO 不拆分，full/empty 与 redirect clear 正确；
- speculative RAS call push 后的下一 request 使用 post-push top，redirect 后恢复到 committed 深度；return mispredict 保持 A1 的 16 次。

官方回归：

```text
command: cmd /c "run_all.bat all < nul"
result:  78 passed / 0 failed
detail:  1 tb_perf_counters + 77 ISA tests
compile: 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a2-run_all_all-post-ras.log
protected HEX after restore:
         C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

九窗口签核：

| Window | Cycles | Instret | IPC x1000 | Brmisp | Exceptions |
| --- | ---: | ---: | ---: | ---: | ---: |
| ALU | 216026 | 216013 | 999 | 2 | 0 |
| MEXT | 190041 | 54016 | 284 | 4 | 0 |
| BRANCH_RANDOM | 312159 | 245975 | 787 | 9475 | 0 |
| BRANCH_REGULAR | 108046 | 96017 | 888 | 1505 | 0 |
| BRANCH_SHORT | 117046 | 93015 | 794 | 3005 | 0 |
| BRANCH_CALL | 192384 | 144022 | 748 | 4061 | 0 |
| BRANCH_CAPACITY | 140943 | 69133 | 490 | 1152 | 0 |
| BRANCH_RETURN | 848114 | 760025 | 896 | 16 | 0 |
| MEMORY | 648680 | 601238 | 926 | 185 | 0 |
| **Overall** | **2773439** | **2279454** | **821** | **19405** | **0** |

```text
header:      version=5, cpu_freq_hz=125000000, sink=0x9D3BF787
result:      PERF_BENCHMARK_PASSED
A1 overall:  cycles=2736627, instret=2279454, ipc_x1000=832
A2 overall:  cycles=2773439, instret=2279454, ipc_x1000=821
IPC change:  -11 x1000 (-1.32%)
compile log: F:\Tools\temp\riscv-dual-rebuild-a2-nine-window-compile-final.log
run log:     F:\Tools\temp\riscv-dual-rebuild-a2-nine-window-final.log
```

A2 的真实退休数、sink、exceptions 和 branch mispredict 总数均与 A1 一致，新增 issue 计数器也在九窗口报告中产生非零值。IPC 从 `0.832` 降到 `0.821`，主要是 Fetch/Bundle 阶段边界和单 lane Decode adapter 仍需串行消费 bundle；该回退被如实保留，A3 完成真实双 lane Decode/执行后再判断前端 FIFO 的性能收益，不能把 A2 的 pairing 计数误称为双退休性能。

签核时重新核对冻结夹具：`benchmark.c`、`startup.S`、`linker.ld`、`Makefile`、`out/inst.hex`、`out/data.hex` 六项 SHA256 均与 12.2 相同；A0 适配后的 `test/tb_top.sv` 保持 `77F2DABDCA7F9E0A7B179A8EA0FA9FE7FD031BD2EFBCF68A0F6067C7E0E59701`。

### 17.6 A3 签核记录

实现提交：

```text
commit:  fb67141c70c48f53dac33d44073ad719ee49bea3
subject: backend: add synchronous dual ALU path
```

实现边界：

- GPR 增加两个架构写口和四个同步读口；A3 双 lane 在 bundle launch 边沿同时发起四读，下一拍 ID/EX resident 与四路数据严格对齐。
- 两写口同地址时显式规定年轻的 write1 优先；正常 pairing 已禁止 WAW。两个写口都忽略 `x0`，同步读 `x0` 恒为 0。
- 同拍 WB→同步读采用 write1、write0、array 的固定优先级。相邻 dual bundle 的 ready ALU producer 通过该旁路直接供下一 bundle，避免读取旧 GPR 值。
- `dual_scoreboard` 提供六个从年轻到年老的 EX1/EX0/MEM1/MEM0/WB1/WB0 producer 槽；匹配最年轻 producer，`pending` 或 `!result_valid` 时阻塞，ready 时给出 forwarding select，kill producer 不参与依赖。
- A3 快速路径仅接受真正的双 lane、independent、受支持基础整数 ALU bundle：LUI、AUIPC、标准 OP-IMM，以及非 M、非 bitman 的标准 OP。单条 simple、控制流、LSU、MULDIV、CSR/FPU 和 bitman 继续走 legacy backend。
- 双 ALU 支持 ADD/SUB、逻辑、比较、立即数和移位；SRA/SRAI 使用显式有符号分支，避免有符号/无符号三元表达式改变算术右移语义。
- Bundle FIFO 增加一个 lookahead。尚未进入 dual mode 时只有连续两个可支持双 bundle 才切换；进入后跨短暂 FIFO 空档保持 mode。长延迟 legacy producer 会启动四 bundle cooldown，避免在 MULDIV/LSU 周围为孤立 ALU 片段反复排空切换。
- legacy adapter/ID/EX/MEM 排空后允许 final legacy WB 与 dual 同拍 RF launch，依靠 WB bypass 对齐；dual resident 本拍提交时允许下一条 legacy uop 同边沿进入 Decode，但两域禁止同拍退休，且同一 bundle 禁止被两域同时选择。
- dual commit 把 `retire_count=2` 送入标准/perf `instret`；新增 `CSR_PERF_RESULT_DEP=0x7D5` 记录已识别的跨 bundle result dependency。

定向测试：

```text
test:    tb_regfiles_4r2w
result:  REGFILES 4R2W TEST PASSED
test:    tb_a3_dual_backend
result:  A3 DUAL BACKEND TEST PASSED
test:    tb_perf_counters
result:  PERF COUNTER TEST PASSED
test:    tb_fetch_fifo_2wide
result:  FETCH FIFO 2WIDE TEST PASSED
test:    tb_issue_bundle_fifo
result:  ISSUE BUNDLE FIFO TEST PASSED
test:    tb_if_sync_btb
result:  IF SYNC BTB TEST PASSED
compile: QuestaSim 2024.1, 0 errors / 0 warnings
sim:     all six tests, 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a3-directed-final.log
```

覆盖点：

- 4R2W GPR 双写、四路同步读、同拍 WB bypass、`x0`、read hold、write1 WAW 优先；
- 连续双 ALU bundle、跨 bundle 同时依赖前一 bundle 两个结果、双写回与双退休；
- LUI/AUIPC、ADD/SUB、负数 SRA/SRAI，以及 PC/inst/age/epoch tag 对齐；
- redirect 抑制 resident pair 的 GPR 写和退休；
- scoreboard pending 阻塞、ready forwarding、kill 忽略、最年轻 pending producer 不得被更老 ready producer 绕过；
- dispatch lookahead、dual-mode 保持、legacy cooldown、single/MUL 回 legacy、旧域未排空时不切入 dual、dual→legacy 同边沿有序交接；
- assertion：同一 bundle 不得双选两个 backend，legacy/dual 不得同拍退休，双 lane age/epoch 必须一致。

官方回归：

```text
command: cmd /c "run_all.bat all < nul"
result:  78 passed / 0 failed
detail:  1 tb_perf_counters + 77 ISA tests
compile: 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a3-run_all_all-final.log
tightest observed UM test: rv32um-p-mul passed at 9.81 us under the unchanged 10 us timeout
protected HEX after restore:
         C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

九窗口签核：

| Window | Cycles | Instret | IPC x1000 | Brmisp | Result dependency | Exceptions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ALU | 216029 | 216013 | 999 | 2 | 12002 | 0 |
| MEXT | 190041 | 54016 | 284 | 4 | 0 | 0 |
| BRANCH_RANDOM | 324355 | 245975 | 758 | 9475 | 24000 | 0 |
| BRANCH_REGULAR | 111046 | 96017 | 864 | 1505 | 1501 | 0 |
| BRANCH_SHORT | 117046 | 93015 | 794 | 3005 | 23999 | 0 |
| BRANCH_CALL | 196442 | 144022 | 733 | 4061 | 0 | 0 |
| BRANCH_CAPACITY | 141968 | 69133 | 486 | 1152 | 0 | 0 |
| BRANCH_RETURN | 848131 | 760025 | 896 | 16 | 1 | 0 |
| MEMORY | 649046 | 601238 | 926 | 185 | 2 | 0 |
| **Overall** | **2794104** | **2279454** | **815** | **19405** | **61505** | **0** |

```text
command: vlog -sv +define+PERF_BENCH +define+DEBUG_EN ...
header:      version=5, cpu_freq_hz=125000000, sink=0x9D3BF787
result:      PERF_BENCHMARK_PASSED
A2 overall:  cycles=2773439, instret=2279454, ipc_x1000=821
A3 overall:  cycles=2794104, instret=2279454, ipc_x1000=815
IPC change:  -6 x1000 (-0.73%)
compile log: F:\Tools\temp\riscv-dual-rebuild-a3-nine-window-compile-final.log
run log:     F:\Tools\temp\riscv-dual-rebuild-a3-nine-window-final.log
```

A3 的真实退休数、sink、exceptions、branch mispredict 总数均与 A2 一致，九窗口产生 `61505` 次 ready result dependency 观测。整体 IPC 从 `0.821` 降到 `0.815`：当前只把可支持的双 ALU pair 送到新路径，而 single/control/LSU/MULDIV/bitman 仍走 legacy，域间排空、lookahead 和 cooldown 的开销尚未被 A4/A5 的统一双 lane 后端抵消。该回退被保留为 A4 的性能基线，不作为关闭顺序保护或扩大不安全配对的理由。

诊断期间曾遗漏 `+define+PERF_BENCH`，从 `0x8000_0000` 启动后使 AUIPC 软件栈落到未映射的 `0xE000_xxxx`，从而复现历史错误 sink `0x4A27AD51`。这不是有效的九窗口签核配置；未修改 golden，最终记录只采用本节明确列出的 PERF_BENCH 编译命令。

签核时再次核对冻结夹具：六项软件/HEX SHA256 与 12.2 相同；`test/tb_top.sv` 保持 A0 适配后的 `77F2DABDCA7F9E0A7B179A8EA0FA9FE7FD031BD2EFBCF68A0F6067C7E0E59701`。

### 17.7 A4 设计与签核记录

A4 开始基线：

```text
start commit:       f3d4b6a886a84757fd587a47489401965b01569e
protected HEX SHA:  C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
status:              SIGNED_OFF
```

实现边界：

- `ALU`、`Branch` 和 A5 前的 `LSU shell` 是单周期执行单元：只有有效且未 kill 的请求才产生 `done`；所有结果和分支 metadata 都由模块输出，不再散落在 EX resident 的控制逻辑中。
- `MUL` 与 `DIV` 是独立共享单元：请求边沿锁存 operands/op，执行期间 `busy=1`，完成只产生一次 `done`；除零和有符号溢出在 DIV 单元内按 RISC-V M 语义完成，不向底层组合除法传递零除数。
- EX resident 为每个 uop 保存 `valid/started/completed/killed`。多周期 `start` 只能由 `valid && !started && !killed` 产生；`done` 后锁存结果，在 MEM backpressure 下保持 resident 和结果；release 后才允许下一 uop 占用。
- kill uop 不发出任何单元 start，不因单元 busy 或 done 阻塞，并沿原有 flush 路径禁止 redirect、预测器更新、GPR/CSR 写、memory request 和 retire。
- A4 保持 A3 dispatch 白名单不变，不开放 control、LSU 或 MULDIV 双发；四拍 Load、两拍 Store、固定 EX/MEM 和 Store commit-only 副作用属于 A5。

阶段签核要点：

1. 单周期 ALU/Branch/LSU shell 的请求、结果、branch taken/target/mispredict、地址/mask 定向测试通过。
2. MUL/DIV 每个 resident uop 恰好一次 start 和一次 done；下游 hold 跨过 done 时结果稳定且不重新启动。
3. resident 被 hold 时不能被新输入覆盖；kill-before-start 不启动，kill-during-wait 立即释放且不提交。
4. forwarding 操作数在 start 边沿锁存，等待期间上游输入变化不改变在途运算。
5. A3 directed tests、MULDIV ISA 回归、`run_all.bat all` 和九窗口全部通过；sink、exceptions 与冻结夹具不变。

实现提交：

```text
commit:  542ea992082a9143330d0ea31ca46e251063c858
subject: backend: add modular resident execution units
status:  SIGNED_OFF
```

实现结果：

- 新增 `alu_exec_unit`、`simple_alu_exec_unit`、`branch_exec_unit` 和 `lsu_exec_unit`；A3 双 ALU 与 legacy EX 复用同一模块化 ALU 语义。
- 新增 `ex_resident_control`，统一保存 `started/completed/killed/result`。单周期单元在 start 拍完成；MUL/DIV 在完成拍释放，若 MEM backpressure 则锁存结果并保持，不重新 start。
- `mul` 与 `divider` 拆分为独立共享多周期单元。MUL 的 `MUL_CYCLE=4` 包含 start 边沿；DIV 对除零和 `INT_MIN/-1` 提供 RISC-V 规定结果，普通除法保持原 12 拍仿真延迟。
- LSU shell 只在 resident start 脉冲产生一次 request；kill 时 request/write-enable 为零。四拍 Load、两拍 Store 与 commit-only Store 仍明确留给 A5。
- Branch 的 taken/target/mispredict metadata 在 resident hold 期间保持稳定；redirect、预测器更新和 branch event 仍只在 bundle 真正离开 EX 时发生一次。
- 新增断言检查 busy 单元重复 start、无 resident start 的 done、killed resident 启动、killed side effect，以及非 start 拍的 LSU request。

定向测试：

```text
tests:   tb_perf_counters
         tb_fetch_fifo_2wide
         tb_issue_bundle_fifo
         tb_if_sync_btb
         tb_regfiles_4r2w
         tb_a3_dual_backend
         tb_a4_execute_units
result:  7/7 passed; simulations 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a4-directed-final.log
```

`tb_a4_execute_units` 覆盖 ALU 算术右移、signed branch、JALR target mask、byte-store 地址/data/mask、MUL/DIV start-once/done-once、输入在 start 后变化、完成后下游 hold、signed divide overflow、kill-before-start 和 kill-during-wait。八项 `rv32um-p-{mul,mulh,mulhu,mulhsu,div,divu,rem,remu}` 也逐项通过；最紧的 `rv32um-p-mul` 在不变的 10 us timeout 下约 9.55 us 完成。

官方回归：

```text
command: cmd /c "run_all.bat all < nul"
result:  78 passed / 0 failed
detail:  1 tb_perf_counters + 77 ISA tests
compile: QuestaSim 2024.1, 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a4-run_all_all-final.log
protected HEX after restore:
         C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

九窗口签核：

| Window | Cycles | Instret | IPC x1000 | Brmisp | Result dependency | Exceptions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ALU | 216029 | 216013 | 999 | 2 | 12002 | 0 |
| MEXT | 190041 | 54016 | 284 | 4 | 0 | 0 |
| BRANCH_RANDOM | 324355 | 245975 | 758 | 9475 | 24000 | 0 |
| BRANCH_REGULAR | 111046 | 96017 | 864 | 1505 | 1501 | 0 |
| BRANCH_SHORT | 117046 | 93015 | 794 | 3005 | 23999 | 0 |
| BRANCH_CALL | 196442 | 144022 | 733 | 4061 | 0 | 0 |
| BRANCH_CAPACITY | 141968 | 69133 | 486 | 1152 | 0 | 0 |
| BRANCH_RETURN | 848131 | 760025 | 896 | 16 | 1 | 0 |
| MEMORY | 649046 | 601238 | 926 | 185 | 2 | 0 |

```text
command:      vlog -sv +define+PERF_BENCH +define+DEBUG_EN ...; vsim tb_uart_benchmark
sink:         0x9D3BF787
overall:      cycles=2794104, instret=2279454, ipc_x1000=815
result:       PERF_BENCHMARK_PASSED
compile:      0 errors / 0 warnings
simulation:   0 errors / 0 warnings
compile log:  F:\Tools\temp\riscv-dual-rebuild-a4-nine-window-compile-final.log
run log:      F:\Tools\temp\riscv-dual-rebuild-a4-nine-window-final.log
```

A4 九个窗口的 cycles、instret、IPC、branch mispredict、result dependency、sink 和 exceptions 与 A3 逐项完全一致。A4 因此只签核执行协议边界，不宣称吞吐提升；A3/A4 的 `0.815` 仍是 A5 统一 LSU/MEM 以及 A6 逐类开放配对前的稳定基线。

九窗口命令曾按第 12.3 节的历史示例引用当前工作树不存在的 `vivado-project/.../dram_driver.sv`，因此只产生一次编译前置失败、未运行仿真。第 12.3 节现已校正为 A3/A4 实际签核使用的源文件集合；最终日志均为 0 error / 0 warning。

签核时再次核对 protected HEX、六项冻结 benchmark 软件/HEX 和 `test/tb_top.sv`；SHA256 全部与 A0/A3 记录一致，未重建软件、未修改 golden。

### 17.8 A5 设计与签核记录

A5 开始基线：

```text
start commit:       19014ee05d4961ae6b5a9fe19976b085f4ca96ec
protected HEX SHA:  C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
status:              IN_PROGRESS
```

实现边界：

- bridge/CPU data-memory 接口增加显式 read response valid。Load 在 E0 只发一次 request；request 的 address、访问宽度/符号、目的寄存器及异常 metadata 随 resident 保存，E3 将锁存的 response data 与同一 uop 原子送入固定 EX/MEM 寄存器。
- Store 在 E0 形成 address/data/mask 并锁存，E1 完成并进入 EX/MEM；EX 的物理 `dmem_wen` 永远为零。MEM 只有在 `valid && commit && !kill && !exception` 时产生一次实际 write pulse。
- 数据端口为单端口、blocking、单 outstanding。若更老 Store 正在 MEM commit，年轻 EX LSU 的 start-ready 为零；resident 保持未 started，下一拍再发请求，禁止请求丢失或年轻访问越过。
- E0 计算 load/store alignment。misaligned 访问不发外部 request/write；地址和访问类型仍进入 MEM，由既有异常优先级产生 LAM/SAM，且不退休、不写 GPR/memory。
- kill-before-start 不产生请求；kill-after-load-request 清除 resident request-valid 并忽略随后 response，不等待 done、不进入 MEM。bridge 的旧 response valid 不能匹配到后续 resident。
- A5 不开放 LSU 双发，lane1 年龄/异常抑制继续由现有 atomic bundle 和 dispatch 边界保持；A6 开放 LSU pairing 前必须复用本阶段的单端口仲裁和 commit-only Store 规则。

阶段签核要点：

1. `tb_lsu_four_beat_load`：E0 唯一 request、E1/E2 hold、E3 response/release，byte/half/word 扩展与 metadata 对齐。
2. `tb_lsu_store_commit`：E0/E1 无物理写，MEM commit 只有一个 write pulse；MEM backpressure 不重复写。
3. `tb_lsu_store_load_order`：更老 Store commit 与年轻 Load/Store 冲突时 Store 优先，年轻 resident 未 start 且下一拍请求不丢。
4. `tb_lsu_exception_age`：misaligned、kill-before-start、kill-during-wait、外部异常均无 request/store/GPR/retire 副作用。
5. A4 directed tests、load/store ISA、`run_all.bat all` 与九窗口通过；sink/exceptions/夹具不变，并如实记录 MEMORY 与 overall IPC。

实现提交：

```text
commit:  c2f0ecdae77801c4170ab62b5c169bdd30c70777
subject: feat: implement precise four-beat LSU
status:  SIGNED_OFF
```

实现结果：

- `lsu_exec_unit` 在 E0 锁存地址、Store data/mask、访问宽度与符号；对齐 Load 只发一个 request 并等待显式 `response_valid`，E3 才携带锁存数据离开 EX。Store 在 E1 完成，但 EX 的物理写使能恒为零。
- `bridge` 对 read target 与 valid 各打两级，使 RAM/IO/PLIC 的锁存响应与 `dmem_rvalid` 同拍返回；被 kill 的旧 Load 响应即使与替代 Load 的 start 同拍到达，也不能完成年轻 resident。
- 新增 `mem_store_commit`，Store 只有在 MEM resident 被下游接受且未 kill、无异常时才产生一个写脉冲；backpressure、misaligned、flush 和 exception 均抑制写入。
- 单数据端口显式按年龄仲裁：更老的 MEM Store commit 优先，年轻 EX LSU 保持 `started=0` 并在端口释放后重试；A5 未扩大 A3/A4 pairing 白名单。
- 新增断言检查 EX 不得产生 Store 写使能、LSU request 必须来自有效 start、killed resident 不得产生副作用，以及 Store write 必须与精确 MEM commit 同拍。
- A5 的强制 LSU 驻留使 `rv32ui-p-sw/sh` 分别在约 `10.04/10.05 us` 完成，超过 A4 的固定 `10 us` watchdog。`tb_my_cpu` watchdog 调整为有限的 `20 us`，功能成功条件仍是明确退休到 `0x8000_0044` 且结果为 1，不能用单纯“未超时”判定通过。

定向与受影响回归：

```text
tests:   tb_perf_counters
         tb_fetch_fifo_2wide
         tb_issue_bundle_fifo
         tb_if_sync_btb
         tb_regfiles_4r2w
         tb_a3_dual_backend
         tb_a4_execute_units
         tb_lsu_four_beat_load
         tb_lsu_store_commit
         tb_lsu_store_load_order
         tb_lsu_exception_age
result:  11/11 passed; simulations 0 errors / 0 warnings
logs:    F:\Tools\temp\riscv-dual-rebuild-a5-directed-*-final.log
         F:\Tools\temp\riscv-dual-rebuild-a5-directed-tb_lsu_exception_age-post-review.log

ISA:     rv32ui-p-{lw,lh,lhu,lb,lbu,sw,sh,sb}
result:  8/8 passed
logs:    F:\Tools\temp\riscv-dual-rebuild-a5-ui-*-final.log

compile: 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a5-compile-post-review.log
```

官方回归：

```text
command: cmd /c "run_all.bat all < nul"
result:  78 passed / 0 failed
detail:  1 tb_perf_counters + 77 ISA tests
compile: QuestaSim 2024.1, 0 errors / 0 warnings
log:     F:\Tools\temp\riscv-dual-rebuild-a5-run_all_all-final.log
protected HEX after restore:
         C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

九窗口签核：

| Window | Cycles | Instret | IPC x1000 | Brmisp | Result dependency | Exceptions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ALU | 216032 | 216013 | 999 | 2 | 12002 | 0 |
| MEXT | 190045 | 54016 | 284 | 4 | 0 | 0 |
| BRANCH_RANDOM | 324358 | 245975 | 758 | 9475 | 24000 | 0 |
| BRANCH_REGULAR | 111050 | 96017 | 864 | 1505 | 1501 | 0 |
| BRANCH_SHORT | 117050 | 93015 | 794 | 3005 | 23999 | 0 |
| BRANCH_CALL | 196463 | 144022 | 733 | 4061 | 0 | 0 |
| BRANCH_CAPACITY | 141973 | 69133 | 486 | 1152 | 0 | 0 |
| BRANCH_RETURN | 920170 | 760025 | 825 | 16 | 0 | 0 |
| MEMORY | 787465 | 601238 | 763 | 185 | 2 | 0 |

```text
command:      vlog -sv +define+PERF_BENCH +define+DEBUG_EN ...; vsim tb_uart_benchmark
sink:         0x9D3BF787
overall:      cycles=3004606, instret=2279454, ipc_x1000=758
result:       PERF_BENCHMARK_PASSED
compile:      0 errors / 0 warnings
simulation:   0 errors / 0 warnings
compile log:  F:\Tools\temp\riscv-dual-rebuild-a5-nine-window-compile-final.log
run log:      F:\Tools\temp\riscv-dual-rebuild-a5-nine-window-final.log
```

A4→A5 的真实退休数、sink、exceptions 与九窗口完成次数不变。强制四拍 Load/两拍 Store 使 overall cycles 从 `2794104` 增至 `3004606`（`+210502`, `+7.534%`），IPC 从 `0.815809` 降至 `0.758653`。MEMORY cycles 从 `649046` 增至 `787465`（`+138419`, `+21.327%`），IPC 从 `0.926341` 降至 `0.763511`；其余八窗口聚合 cycles 从 `2145058` 增至 `2217141`（`+72083`, `+3.360%`），聚合 IPC 从 `0.782364` 降至 `0.756928`。其中非 MEMORY 增量几乎全部来自仍包含栈访存的 BRANCH_RETURN 窗口。该性能下降是计划规定的 LSU 时序代价，A6 将按类别逐步开放安全配对，不能通过缩短 LSU、提前 Store 副作用或扩大未经签核的白名单掩盖。

签核时再次核对 protected HEX、六项冻结 benchmark 软件/HEX 和 `test/tb_top.sv`；SHA256 全部与 A0/A4 记录一致，未重建软件、未修改 golden。

### 17.9 A6 设计与签核记录

A6 基线与最终状态：

```text
start commit:       d5a097369b0c3c6aa9a37385f690ebd652ced3b4
protected HEX SHA:  C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
status:              SIGNED_OFF
final implementation: c2924e6edd74a0efdaac09a5a085fd8d6f9001ab
completed substage:  A6.4 simple + MULDIV / MULDIV + simple
next stage:          A7
```

统一年龄与提交规则：

- Issue 仍然只做最小预译码、RAW/WAW/结构检查和原子 bundle 形成；`lane0` 永远更老，WAR 允许，RAW/WAW 禁止双发，`x0` 不形成依赖。
- 一个 dual resident 必须原子接收和释放两个 lane。共享 Branch、LSU、MUL、DIV 每包最多一个；单元 `start` 对同一 uop 只出现一次，等待期间两个 lane 都不能被覆盖或越过。
- 正常 bundle 只允许同拍按 lane0→lane1 顺序退休 0/1/2 条。lane0 同步异常时 lane1 的 GPR/Store/redirect/retire 全部抑制；lane1 同步异常时只允许已完成的更老 lane0 退休。
- redirect 清空两个 lane 及所有年轻 FIFO 状态；lane1 control 的 redirect 只能在 lane0 结果已确定且二者到达同一精确提交边界时生效。
- A5 的单端口 LSU 仲裁、四拍 Load、两拍 Store 和 commit-only Store 不得因配对而缩短；MULDIV 等待完成前结果保持 pending。
- 每个子阶段只增加一种 pairing class；未开放类别继续由 legacy adapter 顺序执行，不能用关闭既有安全类别换取通过。

子阶段顺序与签核点：

1. **A6.1 `simple + simple`**：冻结 A3 已开放的标准双 ALU 白名单；补充 pairing matrix、年龄、连续 pair、RAW/WAW/WAR、redirect 和双写回定向覆盖。完整回归与九窗口应与 A5 功能一致，作为后续类别的 A/B 基线。
2. **A6.2 `simple + control`**：只开放 lane1 control；覆盖 BEQ/BNE/有符号与无符号分支、JAL/JALR、taken/not-taken、预测正确/错误、target 对齐、lane0 写回与 lane1 redirect 同拍，以及 lane0 fault/kill 对 lane1 的抑制。
3. **A6.3 `simple + LSU` / `LSU + simple`**：每包恰好一个 LSU；覆盖 Load E0-E3、Store E0-E1→MEM commit、两种 lane 顺序、单端口冲突、load-use pending、misaligned LAM/SAM、kill/stale response 和按年龄的部分退休。
4. **A6.4 `simple + MULDIV` / `MULDIV + simple`**：每包恰好一个共享 MUL/DIV；覆盖两种 lane 顺序、start/done once、完成前双 lane hold、除零/溢出、redirect kill、结果稳定和精确双退休。

每个子阶段必须分别记录：实现提交、directed tests、`run_all.bat all` 的通过数和编译 0/0、九窗口九条 report、overall cycles/instret/IPC、sink、exceptions、实际 class pairing 次数与拒绝原因。A6 只有四个子阶段全部签核后才能标记 `SIGNED_OFF`。

#### 17.9.1 A6.1 `simple + simple` 签核

实现提交：

```text
commit:  40eb13a787159ee79ffb9cbccc086ba0f2d582b5
subject: issue: freeze simple pair classification
status:  SIGNED_OFF
```

`pair_predecode` 统一了 Issue 与 Dispatch 对标准双 ALU 指令的定义，并输出后续子阶段复用的 control/LSU/MULDIV、源寄存器和目的寄存器最小分类。Issue 新增显式 `pair_class`；A6.1 仍只接受 `PAIR_SIMPLE_SIMPLE`。此前会在 Issue 被计成 pair、随后又由 Dispatch 回退 legacy 的 bitman/非标准 OP 现在直接按结构冲突留在单发路径，因此 `dual` 计数继续只表示实际已开放的 simple pairing class。

定向测试覆盖独立 pair、连续 pair、双写回、同步读 WB bypass、年龄/epoch、redirect kill、RAW、WAW、WAR、`x0`、bitman/control/LSU/MULDIV 白名单边界。结果：

```text
tb_issue_bundle_fifo: PASS
tb_a3_dual_backend:   PASS
compile:              0 errors / 0 warnings
logs:                 F:\Tools\temp\riscv-dual-rebuild-a6-1-tb_issue_bundle_fifo-directed-1.log
                      F:\Tools\temp\riscv-dual-rebuild-a6-1-tb_a3_dual_backend-directed-1.log
compile log:          F:\Tools\temp\riscv-dual-rebuild-a6-1-compile-2.log
```

官方回归与九窗口：

```text
run_all.bat all: 78 passed / 0 failed; compile 0 errors / 0 warnings
run_all log:     F:\Tools\temp\riscv-dual-rebuild-a6-1-run_all_all-final.log
sink:            0x9D3BF787
overall:         cycles=3004606, instret=2279454, ipc_x1000=758
result:          PERF_BENCHMARK_PASSED; nine reports; exceptions=0
compile log:     F:\Tools\temp\riscv-dual-rebuild-a6-1-nine-window-compile-final.log
run log:         F:\Tools\temp\riscv-dual-rebuild-a6-1-nine-window-final.log
protected HEX:   C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

| Window | Cycles | Instret | IPC x1000 | Dual | Single | RAW | WAW | Struct | Exceptions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ALU | 216032 | 216013 | 999 | 48002 | 120014 | 48009 | 24004 | 12009 | 0 |
| MEXT | 190045 | 54016 | 284 | 10008 | 34018 | 16008 | 2003 | 32005 | 0 |
| BRANCH_RANDOM | 324358 | 245975 | 758 | 54312 | 164903 | 54314 | 25530 | 37560 | 0 |
| BRANCH_REGULAR | 111050 | 96017 | 864 | 27008 | 48016 | 3 | 0 | 22510 | 0 |
| BRANCH_SHORT | 117050 | 93015 | 794 | 39005 | 21019 | 3004 | 0 | 6011 | 0 |
| BRANCH_CALL | 196463 | 144022 | 733 | 12006 | 132197 | 44111 | 32106 | 24025 | 0 |
| BRANCH_CAPACITY | 141973 | 69133 | 486 | 1030 | 70407 | 1026 | 1025 | 2305 | 0 |
| BRANCH_RETURN | 920170 | 760025 | 825 | 152000 | 456092 | 80018 | 56004 | 320003 | 0 |
| MEMORY | 787465 | 601238 | 763 | 92785 | 416404 | 276913 | 138239 | 230664 | 0 |

A6.1 的九个 cycles/instret/IPC、dual/single/struct、sink 和 exceptions 与 A5 相同，证明 simple 双执行行为未改变。RAW 计数增加是统一预译码现在也观察到尚未开放的 control/LSU 类别中的真实包内相关；拒绝原因允许多因并存，不代表额外 stall 或执行行为变化。

#### 17.9.2 A6.2 `simple + control` 签核

实现提交：

```text
commit:  7f063ba7c392ba2b67ddd2d39fa375ecf1c67f95
subject: backend: pair simple with lane1 control
status:  SIGNED_OFF
```

实现只开放 lane0 simple + lane1 control。dual resident 保存 lane1 的预测 metadata 和同步 RF 数据，复用 `branch_exec_unit` 完成 BEQ/BNE/BLT/BGE/BLTU/BGEU、JAL 与 JALR。自身 mispredict 在两个 lane 到达同一提交边界后清空年轻前端，不作为 kill 反杀当前 pair；外部 redirect 仍会在提交前杀死两个 lane。JAL/JALR 的 link 写回 `pc+4`，predictor update 复用 Branch/JAL/JALR/Call/Return 类型。目标未按 4 字节对齐时输出 IAM：lane0 已完成的 simple 单独退休，lane1 不写 GPR、不 redirect、不退休，CSR 记录 lane1 PC/target。

`CSR_PERF_LANE1_CONTROL=0x7D0` 现在统计真正进入 dual resident 的 control pair。isolated control pair 在 legacy 域空闲时可直接进入 dual；这是为了真实开放 JAL/JALR，而不是只在双 ALU lookahead 已建立时偶然执行。当前 split dual/legacy backend 使 CALL 后立即切回尚未开放 LSU 的 legacy 序列仍有域切换代价，留给 A6.3 继续消除。

定向与受影响回归：

```text
tests:   tb_a6_simple_control
         tb_issue_bundle_fifo
         tb_a3_dual_backend
         tb_perf_counters
result:  4/4 passed; compile/simulation 0 errors / 0 warnings
logs:    F:\Tools\temp\riscv-dual-rebuild-a6-2-*-directed-final-2.log
compile: F:\Tools\temp\riscv-dual-rebuild-a6-2-compile-final-2.log

ISA:     rv32ui-p-{beq,bne,blt,bge,bltu,bgeu,jal,jalr}
result:  8/8 passed
logs:    F:\Tools\temp\riscv-dual-rebuild-a6-2-ui-*-final.log
```

官方回归与九窗口：

```text
run_all.bat all: 78 passed / 0 failed; compile 0 errors / 0 warnings
run_all log:     F:\Tools\temp\riscv-dual-rebuild-a6-2-run_all_all-final-3.log
sink:            0x9D3BF787
overall:         cycles=2999558, instret=2279454, ipc_x1000=759
result:          PERF_BENCHMARK_PASSED; nine reports; exceptions=0
compile log:     F:\Tools\temp\riscv-dual-rebuild-a6-2-nine-window-compile-final-3.log
run log:         F:\Tools\temp\riscv-dual-rebuild-a6-2-nine-window-final-3.log
protected HEX:   C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

| Window | Cycles | Instret | IPC x1000 | Dual | Single | Lane1 control | Brmisp | Exceptions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ALU | 216028 | 216013 | 999 | 60000 | 96014 | 11999 | 2 | 0 |
| MEXT | 190046 | 54016 | 284 | 10009 | 34016 | 0 | 4 | 0 |
| BRANCH_RANDOM | 319213 | 245975 | 770 | 60478 | 148867 | 5793 | 9475 | 0 |
| BRANCH_REGULAR | 111050 | 96017 | 864 | 37512 | 27011 | 10501 | 1505 | 0 |
| BRANCH_SHORT | 117048 | 93015 | 794 | 42007 | 15013 | 3000 | 3005 | 0 |
| BRANCH_CALL | 204567 | 144022 | 704 | 36007 | 92299 | 11999 | 4061 | 0 |
| BRANCH_CAPACITY | 141971 | 69133 | 486 | 1032 | 70402 | 0 | 1152 | 0 |
| BRANCH_RETURN | 912170 | 760025 | 833 | 255993 | 248111 | 55990 | 16 | 0 |
| MEMORY | 787465 | 601238 | 763 | 92787 | 416401 | 0 | 185 | 0 |

A6.1→A6.2 的 overall cycles 减少 `5048`（`-0.170%`），精确 IPC 从 `0.758653` 升至 `0.759930`；真实退休数、sink、exceptions 和 branch mispredict 总数保持不变。BRANCH_RANDOM 与 BRANCH_RETURN 分别减少 `5145` 和 `8000` cycles；BRANCH_CALL 因 control pair 后的 LSU/stack 序列仍切回 legacy 而增加 `8104` cycles。该局部回退如实保留，A6.3 必须用统一 LSU resident 和单端口精确提交解决，不能关闭已验证的 JAL/JALR pairing 来隐藏。

#### 17.9.3 A6.3 `simple + LSU` / `LSU + simple` 签核

实现提交：

```text
commit:  8fa360882fb0ed4af96ec68ab75e6cb802507752
subject: backend: pair simple with LSU
status:  SIGNED_OFF
```

Issue 现在接受 `PAIR_SIMPLE_LSU` 与 `PAIR_LSU_SIMPLE`，仍然禁止包内 RAW/WAW、两个 LSU 共用单端口以及所有尚未开放的 MULDIV/bitman 类别。`reject_lsu_conflict` 与 `CSR_PERF_LSU_CONFLICT=0x7D1` 记录双 LSU 结构冲突；`CSR_PERF_LSU_PAIR=0x7CF` 只统计真正进入 dual resident 的 LSU pair，而不是随后由 legacy adapter 串行执行的双 uop bundle。

dual resident 每包恰好一个 LSU，并复用 A5 的 `lsu_exec_unit`：同步 RF 数据到达后只产生一次 `start`；Load 只产生一次 request 并等待 `dmem_rvalid`，Store 在 EX 不产生物理写。LSU 完成后，两个 lane 的年龄/epoch、指令、PC、目的寄存器、simple 结果、地址、mask、Store data、Load metadata/response 一起进入注册 MEM resident。`mem_store_commit` 只在该 resident 的正常提交边界产生一次 Store 写脉冲；debug Store 事件也统一选择 legacy/dual 的真实提交事件。

错位 LSU 在 MEM 形成精确同步异常：lane0 LAM/SAM 时退休 `0` 条并抑制 lane1；lane1 LAM/SAM 时只退休更老的 lane0。外部 redirect 会杀死两个 lane；若 Load request 已在途，则保持 `stale_response_pending`，在吞掉迟到 response 前同时阻塞 dual launch 与 legacy fallback，避免无 tag 单端口把旧 response 交给新 resident。正常 MEM resident 在提交同拍允许下一 dual bundle 同步读，或允许下一 legacy bundle 进入 adapter；2W→4R WB bypass 覆盖对刚退休 lane 的同拍依赖。

分裂 dual/legacy 后端对长 resident 有实际切换成本，因此 Dispatch 使用可复现的成本门限：control pair 仍可直接进入 idle dual 域；孤立 LSU pair 走 legacy；只有已经处于 dual mode 且下一 bundle 是 simple+simple 时，LSU pair 才进入 dual resident。该策略不改变安全白名单，也不以关闭 A6.2 control pairing 隐藏回退；两种 LSU lane 顺序均由硬件与定向测试覆盖。

定向与受影响回归：

```text
tests:   tb_perf_counters
         tb_fetch_fifo_2wide
         tb_issue_bundle_fifo
         tb_if_sync_btb
         tb_regfiles_4r2w
         tb_a3_dual_backend
         tb_a4_execute_units
         tb_a6_simple_control
         tb_a6_lsu_pair
         tb_lsu_four_beat_load
         tb_lsu_store_commit
         tb_lsu_store_load_order
         tb_lsu_exception_age
result:  13/13 passed; compile/simulation 0 errors / 0 warnings
logs:    F:\Tools\temp\riscv-dual-rebuild-a6-3-*-directed-final.log
compile: F:\Tools\temp\riscv-dual-rebuild-a6-3-compile-final.log

ISA:     rv32ui-p-{lw,lh,lhu,lb,lbu,sw,sh,sb}
result:  8/8 passed
logs:    F:\Tools\temp\riscv-dual-rebuild-a6-3-ui-*-final.log
```

`tb_a6_lsu_pair` 覆盖两种 lane 顺序的 Load/Store、四拍 Load hold、端口占用后重试、EX 无 Store 副作用、注册 MEM 单次 Store、同拍 MEM release/WB bypass、lane0 LAM、lane1 SAM、外部 kill 与 stale response quarantine。Issue/Dispatch 测试另外覆盖 LSU RAW、双 LSU 冲突、孤立 legacy fallback 和已建立 dual run 的 LSU admission。

官方回归与九窗口：

```text
run_all.bat all: 78 passed / 0 failed; compile 0 errors / 0 warnings
run_all log:     F:\Tools\temp\riscv-dual-rebuild-a6-3-run_all_all-final.log
sink:            0x9D3BF787
overall:         cycles=3007198, instret=2279454, ipc_x1000=757
exact IPC:       0.757999306996081
result:          PERF_BENCHMARK_PASSED; nine reports; exceptions=0
compile log:     F:\Tools\temp\riscv-dual-rebuild-a6-3-nine-window-compile-final.log
run log:         F:\Tools\temp\riscv-dual-rebuild-a6-3-nine-window-final.log
protected HEX:   C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

| Window | Cycles | Instret | IPC x1000 | Dual | Single | LSU pair | Lane1 control | LSU conflict | Exceptions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ALU | 216028 | 216013 | 999 | 60001 | 96013 | 0 | 11999 | 0 | 0 |
| MEXT | 190046 | 54016 | 284 | 10009 | 34016 | 0 | 0 | 0 | 0 |
| BRANCH_RANDOM | 319213 | 245975 | 770 | 60481 | 148861 | 0 | 5793 | 0 | 0 |
| BRANCH_REGULAR | 111050 | 96017 | 864 | 37512 | 27011 | 0 | 10501 | 0 | 0 |
| BRANCH_SHORT | 117048 | 93015 | 794 | 42007 | 15013 | 0 | 3000 | 1 | 0 |
| BRANCH_CALL | 204567 | 144022 | 704 | 36011 | 92292 | 0 | 11999 | 5 | 0 |
| BRANCH_CAPACITY | 141971 | 69133 | 486 | 1032 | 70402 | 0 | 0 | 0 | 0 |
| BRANCH_RETURN | 920166 | 760025 | 825 | 304009 | 152084 | 7998 | 55990 | 6 | 0 |
| MEMORY | 787109 | 601238 | 763 | 184410 | 233334 | 0 | 0 | 3 | 0 |

A6.2→A6.3 的真实退休数、sink、exceptions 和九窗口完成次数不变。overall cycles 增加 `7640`（`+0.255%`），精确 IPC 从 `0.759930` 降至 `0.757999`；其中 BRANCH_RETURN 的 `7998` 个真实 LSU pair 对应 cycles 增加 `7996`，MEMORY 则减少 `356` cycles。BRANCH_CALL 没有满足 RAW/WAW、单 LSU 和成本门限的 simple/LSU bundle，因此保持 A6.2 的 `204567` cycles；不能通过强行配对相关栈访问或关闭已签核 control pairing 来制造改善。该小幅成本来自 A6.3 原子 bundle 边界与分裂后端，已与最初无门限调度造成的结构性长驻留回退区分，并如实保留给后续统一调度阶段处理。

签核时重新核对 protected HEX、六项冻结 benchmark 软件/HEX 与 A0 适配后的 `test/tb_top.sv`：全部 SHA256 与 12.2/17.3 相同，未重建软件、未修改 golden。下一子阶段是 A6.4 `simple + MULDIV` / `MULDIV + simple`。

#### 17.9.4 A6.4 `simple + MULDIV` / `MULDIV + simple` 签核

实现提交：

```text
commit:  c2924e6edd74a0efdaac09a5a085fd8d6f9001ab
subject: backend: pair simple with MULDIV
status:  SIGNED_OFF
```

Issue 现在接受 `PAIR_SIMPLE_MULDIV` 与 `PAIR_MULDIV_SIMPLE`，仍禁止包内 RAW/WAW、两个 RV32M 指令争用同一个共享单元以及 bitman 等尚未开放类别。两个 MULDIV 形成通用 `reject_struct`；`dual/single/raw/waw/struct` 继续记录 Issue 决策，新增 `CSR_PERF_MULDIV_PAIR=0x7D6` 只统计真正进入 dual resident 的 MULDIV bundle。

dual resident 根据 RV32M `funct3` 选择唯一的 `mul` 或 `divider`，并从对应 lane 的同步 RF 端口锁定操作数。一个 bundle 只产生一次 `mul_start` 或 `div_start`；等待期间两个 lane、年龄/epoch、目的寄存器和 simple 结果保持原子 resident，不允许提前退休或被年轻 bundle 覆盖。MUL/MULH/MULHSU/MULHU 的 signed/high-half 选择，以及 DIV/DIVU/REM/REMU 的 signed/remainder 选择与 legacy 解码一致；divider 的除零和 `INT_MIN / -1` 快速完成仍经过同一个原子双退休边界。

共享单元 `done` 有效时两条 lane 同拍退休，MULDIV lane 选择共享结果，simple lane 选择保持稳定的 ALU 结果。该完成拍解除 resident exclusion，允许下一 dual bundle 同步读或 legacy bundle 进入 adapter；若下一 bundle 消费刚完成的任一 lane，scoreboard 在 `done` 拍把结果从 pending 转为 valid，并由 2W→4R WB bypass 在同一边沿供数。外部 redirect 在完成前杀死共享单元与两个 lane，禁止迟到 `done`、GPR 写和 retire。

Dispatch 的最终规则保留 `legacy_idle` 作为硬跨域边界：旧 adapter/Decode/EX/MEM 未排空时不能进入 dual，最终 legacy WB 只通过已签核的同拍旁路重叠。独立 simple+MULDIV 本身可把 simple 与长运算重叠且不占数据端口，因此可直接建立 dual run；MULDIV candidate 不受历史 4-bundle legacy cooldown 永久回送，否则 MEXT 连续长运算会使已开放类别实际计数恒为零。该例外不绕过 `legacy_idle`、RAW/WAW 或共享单元结构检查。

定向与受影响回归：

```text
tests:   tb_perf_counters
         tb_fetch_fifo_2wide
         tb_issue_bundle_fifo
         tb_if_sync_btb
         tb_regfiles_4r2w
         tb_a3_dual_backend
         tb_a4_execute_units
         tb_a6_simple_control
         tb_a6_lsu_pair
         tb_a6_muldiv_pair
         tb_lsu_four_beat_load
         tb_lsu_store_commit
         tb_lsu_store_load_order
         tb_lsu_exception_age
result:  14/14 passed; compile/simulation 0 errors / 0 warnings
logs:    F:\Tools\temp\riscv-dual-rebuild-a6-4-*-directed-final.log
compile: F:\Tools\temp\riscv-dual-rebuild-a6-4-directed-compile-final.log

ISA:     rv32um-p-{mul,mulh,mulhu,mulhsu,div,divu,rem,remu}
result:  8/8 passed; simulation 0 errors / 0 warnings
logs:    F:\Tools\temp\riscv-dual-rebuild-a6-4-um-*-final.log
compile: F:\Tools\temp\riscv-dual-rebuild-a6-4-isa-compile-final.log
```

`tb_a6_muldiv_pair` 覆盖八种 RV32M 操作和两种 lane 顺序、每 uop 一次 start/done、完成前原子 hold、除零、signed overflow、MUL 与 DIV 等待期 redirect kill、结果在完成周期内稳定、精确双退休，以及完成同拍让依赖 pair 通过 2W→4R bypass 接续。Issue/Dispatch 测试另外覆盖 MULDIV RAW、双 MULDIV 结构冲突、直接建立 dual run、`legacy_idle` 排空边界和 cooldown 不得使类别不可达。`tb_a6_muldiv_perf_probe` 是冻结 `tb_uart_benchmark` 外的被动 wrapper，不改变 `test/tb_top.sv` 或 21-word 报告，只在九个窗口关闭时读取 `0x7D6` 实际计数。

官方回归与九窗口：

```text
run_all.bat all: 78 passed / 0 failed; compile 0 errors / 0 warnings
run_all log:     F:\Tools\temp\riscv-dual-rebuild-a6-4-run_all_all-final.log
sink:            0x9D3BF787
overall:         cycles=2999204, instret=2279454, ipc_x1000=760
exact IPC:       0.7600196585494018
result:          PERF_BENCHMARK_PASSED; nine reports; exceptions=0
compile log:     F:\Tools\temp\riscv-dual-rebuild-a6-4-nine-window-compile-final.log
run log:         F:\Tools\temp\riscv-dual-rebuild-a6-4-nine-window-final.log
probe log:       F:\Tools\temp\riscv-dual-rebuild-a6-4-nine-window-probe-final.log
actual pairs:    MEXT=13994; other eight windows=0; total=13994
protected HEX:   C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

| Window | Cycles | Instret | IPC x1000 | Dual | Single | MULDIV pair | RAW | WAW | Struct | Exceptions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ALU | 216028 | 216013 | 999 | 60001 | 96013 | 0 | 48008 | 24003 | 5 | 0 |
| MEXT | 182052 | 54016 | 296 | 24006 | 6025 | 13994 | 4013 | 2003 | 2002 | 0 |
| BRANCH_RANDOM | 319213 | 245975 | 770 | 60481 | 148861 | 0 | 53022 | 25449 | 15181 | 0 |
| BRANCH_REGULAR | 111050 | 96017 | 864 | 37512 | 27011 | 0 | 4 | 0 | 12003 | 0 |
| BRANCH_SHORT | 117048 | 93015 | 794 | 42007 | 15013 | 0 | 3003 | 1 | 4 | 0 |
| BRANCH_CALL | 204567 | 144022 | 704 | 36011 | 92292 | 0 | 32112 | 20108 | 12 | 0 |
| BRANCH_CAPACITY | 141971 | 69133 | 486 | 1032 | 70402 | 0 | 1026 | 1025 | 1790 | 0 |
| BRANCH_RETURN | 920166 | 760025 | 825 | 304009 | 152084 | 0 | 72019 | 48005 | 40012 | 0 |
| MEMORY | 787109 | 601238 | 763 | 184410 | 233334 | 0 | 230838 | 137883 | 186 | 0 |

表中 `Dual/Single` 是 Issue 原子 bundle 决策，`MULDIV pair` 是 `0x7D6` 的真实 dual resident 进入次数。A6.3→A6.4 的真实退休数、sink、exceptions、LSU pair 与其余八窗口 cycles 全部不变；MEXT cycles 从 `190046` 降到 `182052`（`-7994`, `-4.206%`），精确 MEXT IPC 从 `0.284226` 升到 `0.296706`。overall 同样减少 `7994` cycles（`-0.266%`），精确 IPC 从 `0.757999` 升到 `0.760020`（`+0.267%`）。

A6 的四个子阶段至此全部独立实现、提交并完成 full regression/九窗口签核，阶段状态改为 `SIGNED_OFF`。签核时再次核对 protected HEX、六项冻结 benchmark 软件/HEX 与 A0 适配后的 `test/tb_top.sv`，八项 SHA256 全部与 12.2/17.3 相同，未重建软件、未修改 golden。A7 必须继续恢复 A1 之后损失的有效执行周期并完成 200 MHz 时序收敛；A0 的 `0.824` 包含错误路径 NOP 退休，不能继续作为有效 IPC 的直接数值门槛，最终同时报告修正口径 IPC、相对 A0 cycles 与 `IPC x Fmax`。

### 17.10 A7 性能恢复与最终收敛记录

#### 17.10.1 A7.1 性能可观测性与冻结基线签核

规划与实现提交：

```text
plan commit:           30ae4ed15c64237c79b192f57547e5d1cf0535f9
implementation commit: 7640bee99c3d6d4b7df50c2e4db1f3f78bbfa69e
status:                SIGNED_OFF
next:                  A7.2 tagged continuous IF requests
```

`tb_a7_perf_profile` 是 `tb_uart_benchmark` 外的 measurement-only wrapper。它只观察已经存在的层次信号，并在既有 `perf_enable` 窗口内计数；本子阶段未修改任何 RTL、CPU 端口、CSR、冻结 `test/tb_top.sv`、21-word report、benchmark 软件/HEX 或 golden。probe 对每个窗口检查：

```text
fetch_uops = 2 * fetch_packets - single_uop_packets
actual_dual_launch = simple_pair + control_pair + lsu_pair + muldiv_pair
legacy_prefer_fallback <= legacy_pair_fallback
```

三项不变量在 boot 与九个正式窗口全部通过；九窗口合计还满足 `dual_retire2_cycles = actual_dual_launch = 354773`。`imem_requests - fetch_packets = 19405`，与九窗口 branch mispredict 合计相等，说明 redirect 丢弃的 in-flight response 没有混入 packet 统计。

官方回归与冻结基线：

```text
run_all.bat all: 78 passed / 0 failed; compile 0 errors / 0 warnings
run_all log:     F:\Tools\Temp\riscv-dual-rebuild-a7-1-run_all_all-final.log

direct result:   PERF_BENCHMARK_PASSED; nine reports; exceptions=0
overall:         cycles=2999204, instret=2279454, ipc_x1000=760
exact IPC:       0.7600196585494018
sink:            0x9D3BF787
compile log:     F:\Tools\Temp\riscv-dual-rebuild-a7-1-nine-window-compile-final.log
direct log:      F:\Tools\Temp\riscv-dual-rebuild-a7-1-nine-window-final.log
profile log:     F:\Tools\Temp\riscv-dual-rebuild-a7-1-profile-final.log
comparison:      A7.1 header, nine L3J_REPORT lines, overall and PASS are identical to A6.4
protected HEX:   C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

| Window | IMEM request | Fetch packet | 1-uop packet | Fetch empty | Issue pair | Actual dual | Legacy pair | Wait legacy | Wait dual |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ALU | 108012 | 108010 | 0 | 60001 | 60001 | 60000 | 3 | 36005 | 0 |
| MEXT | 28029 | 28025 | 1999 | 19 | 24006 | 13996 | 10004 | 20012 | 101976 |
| BRANCH_RANDOM | 156743 | 147268 | 14847 | 100388 | 60481 | 44796 | 9037 | 47896 | 0 |
| BRANCH_REGULAR | 55523 | 54018 | 2998 | 45021 | 37512 | 33004 | 3003 | 37499 | 0 |
| BRANCH_SHORT | 57023 | 54018 | 9000 | 57020 | 42007 | 39001 | 3 | 20998 | 0 |
| BRANCH_CALL | 100253 | 96192 | 28049 | 60187 | 36011 | 11999 | 19955 | 44117 | 0 |
| BRANCH_CAPACITY | 70410 | 69258 | 65408 | 69382 | 1032 | 0 | 1029 | 1022 | 0 |
| BRANCH_RETURN | 424080 | 424064 | 87995 | 64110 | 304009 | 151974 | 152013 | 279986 | 15996 |
| MEMORY | 325153 | 324968 | 46513 | 1974 | 184410 | 3 | 184226 | 91632 | 0 |
| **Overall** | **1325226** | **1305821** | **256809** | **458102** | **749469** | **354773** | **379273** | **579167** | **117972** |

九窗口实际 dual class 分解为 `simple=233499`、`control=99282`、`LSU=7998`、`MULDIV=13994`，合计 `354773`。只有 `47.337%` 的 Issue pair 实际进入 dual resident；`50.606%` 明确回退 legacy，剩余部分位于 redirect/窗口边界等未完成路径。`379273` 次 legacy pair fallback 中 `335898` 次（`88.564%`）发生在 `prefer_legacy_dispatch` 有效时。实际双退休覆盖 `31.128%` 的有效退休指令，但前端仍只有 `0.785153` fetched uop/cycle，并在 Issue FIFO 可接收时空供给 `458102` cycles（总周期 `15.274%`）。

窗口归因进一步冻结 A7 后续顺序：ALU 每 `216028` cycles 只有 `108012` 次 request，且每个实际 dual launch 对应一次 Fetch empty，证明 A7.2 连续 request 是提升纯算术 IPC 的必要条件；BRANCH_CAPACITY 的 `69258` 个 packet 中 `65408` 个仅含一个 uop（`94.436%`），隔拍 request 把该窗口压到约 `0.5 IPC`。另一方面，MEMORY 的 `184410` 个 Issue pair 只有 `3` 个实际 dual launch，BRANCH_RETURN 也有约一半 pair 回退 legacy，证明 A7.3 必须处理域切换而非继续扩大 LSU 白名单；MEXT 的 `101976` 个 wait-dual cycles 则来自共享长 resident，不能由前端供给修复。

A7.1 已独立签核，A7 总阶段保持 `IN_PROGRESS`。下一子阶段严格限于 A7.2 连续取指 request/response tag 管线，不混入 Dispatch、singleton 或配对白名单修改。

#### 17.10.2 A7.2 连续取指 request/response 设计记录

```text
baseline:              0cd312c (A7.1 signed off, clean worktree)
design record commit:  596a66010400737c8383d5b57b9a5fad0f2a24f6
implementation commit: 5ba20465123bada52b3b958afd603b8d883a9ec4
status:                SIGNED_OFF
scope:                 if_stage + tb_if_sync_btb only
next:                  A7.3 reduce dual/legacy domain switching
```

同步 IROM 在 request 边沿锁存 PC/PC+4，并在下一完整周期提供 response。A7.2 保留恰好一个 `req_valid` tag 和一个 `packet_valid` skid packet，冻结以下所有权不变量：

1. `req_valid` 表示本周期可消费的一拍 response；`packet_valid` 只表示此前因 Fetch FIFO 空间不足而保留的完整 packet，正常状态下二者不得同时有效。
2. 没有 held packet 且 Fetch FIFO 空间足够时，live response 直接形成 `fetch_push_*`，并在同一边沿使用该 packet 的预测 next PC 发出下一 request；因此可形成一拍一个 request/packet 的稳态。
3. live response 遇到 backpressure 时必须完整进入 skid，当前边沿不得再发 request；held packet 释放的同一边沿才允许用其已保存的 next PC 恢复 request。
4. request tag 必须保存 PC、epoch 和 request 时刻的 RAS top；BTB 双查询继续与 request 同边沿锁存。packet 进入 Fetch FIFO 时才分配 age 并更新 speculative RAS，同拍新 request 必须看到 call/return 更新后的 RAS top。
5. redirect 同拍同时抑制 packet push 和新 request，递增 epoch，并清除 in-flight tag 与 held packet；旧 IROM response 不得进入 Fetch FIFO。
6. A7.2 不改变 Fetch FIFO、Issue、Dispatch、dual/legacy backend、LSU/MULDIV 时序或任何 pairing class。

定向签核新增连续三拍 request/packet、slot0 taken 后目标 request、backpressure skid hold/release、释放同拍 request、redirect 覆盖 in-flight response，以及现有 BTB write-through、lane1 taken、JAL/JALR/RAS 和 age/epoch 检查。正式签核仍需 78/78、冻结九窗口直跑、A7 profile A/B 和全部夹具 SHA256 复核。

实现将同步 IROM response 在空间足够时直接组合到 `fetch_push_*`；该 packet 的预测 next PC 同时旁路到 PC/BTB request 端。若 Fetch FIFO 空间不足，response 的两个 uop、预测 metadata、epoch、RAS snapshot 和 next PC 一起进入原有 `packet_valid` 寄存器，此时 `req_valid` 清零并停止新请求；held packet 释放时才恢复 request。仿真断言禁止 skid 与 in-flight response 重叠、覆盖未消费 response，以及输出非法 packet count。未修改 Fetch FIFO 及其后的任何模块。

定向与完整回归：

```text
directed: tb_if_sync_btb
          tb_fetch_fifo_2wide
          tb_issue_bundle_fifo
          tb_a3_dual_backend
          tb_a6_simple_control
result:   5/5 passed; compile/simulation 0 errors / 0 warnings
logs:     F:\Tools\Temp\riscv-dual-rebuild-a7-2-*-directed-final.log
compile:  F:\Tools\Temp\riscv-dual-rebuild-a7-2-directed-compile-final.log

run_all.bat all: 78 passed / 0 failed; compile 0 errors / 0 warnings
run_all log:     F:\Tools\Temp\riscv-dual-rebuild-a7-2-run_all_all-final.log
```

冻结九窗口 A/B：

| Window | A7.1 cycles | A7.2 cycles | Delta | A7.1 IPC x1000 | A7.2 IPC x1000 |
| --- | ---: | ---: | ---: | ---: | ---: |
| ALU | 216028 | 204030 | -11998 | 999 | 1058 |
| MEXT | 182052 | 182042 | -10 | 296 | 296 |
| BRANCH_RANDOM | 319213 | 269939 | -49274 | 770 | 911 |
| BRANCH_REGULAR | 111050 | 117042 | +5992 | 864 | 820 |
| BRANCH_SHORT | 117048 | 96042 | -21006 | 794 | 968 |
| BRANCH_CALL | 204567 | 188347 | -16220 | 704 | 764 |
| BRANCH_CAPACITY | 141971 | 75411 | -66560 | 486 | 916 |
| BRANCH_RETURN | 920166 | 912135 | -8031 | 825 | 833 |
| MEMORY | 787109 | 786746 | -363 | 763 | 764 |
| **Overall** | **2999204** | **2831734** | **-167470** | **760** | **804** |

```text
result:       PERF_BENCHMARK_PASSED; nine reports; exceptions=0
overall:      cycles=2831734, instret=2279454, ipc_x1000=804
exact IPC:    0.8049675569809877
sink:         0x9D3BF787
compile log:  F:\Tools\Temp\riscv-dual-rebuild-a7-2-nine-window-compile-final.log
direct log:   F:\Tools\Temp\riscv-dual-rebuild-a7-2-nine-window-final.log
profile log:  F:\Tools\Temp\riscv-dual-rebuild-a7-2-profile-final.log
comparison:   direct and profile header, nine reports, overall and PASS are identical
protected HEX:C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

A7.1→A7.2 的真实退休数、branch mispredict、sink 和 exceptions 不变。overall cycles 减少 `167470`（`-5.584%`），精确 IPC 提升 `5.914%`。相对旧 A0 当前少 `168190` cycles（`-5.606%`）；相对正确退休口径的 A1 仍多 `95107` cycles，留给 A7.3 之后恢复。`BRANCH_REGULAR` 单窗增加 `5992` cycles，是连续供给改变包对齐后 actual dual 从 `33004` 降到 `24003`、legacy pair fallback 从 `3003` 增到 `13504` 的域切换成本；A7.2 未跨范围修改 Dispatch 来隐藏该回退。

| Profile metric | A7.1 | A7.2 | Delta |
| --- | ---: | ---: | ---: |
| IMEM request | 1325226 | 1403314 | +78088 |
| Fetch packet | 1305821 | 1383909 | +78088 |
| Fetched uop | 2354833 | 2496661 | +141828 |
| Fetch empty cycles | 458102 | 38810 | -419292 |
| Issue pair | 749469 | 846538 | +97069 |
| Actual dual launch / retire2 | 354773 | 407501 | +52728 |
| Legacy pair fallback | 379273 | 397807 | +18534 |
| Legacy drain wait cycles | 579167 | 637875 | +58708 |
| Dual backend wait cycles | 117972 | 118000 | +28 |

前端空供给下降 `91.528%`，实际双退休覆盖从有效退休指令的 `31.128%` 增至 `35.754%`。九窗口仍满足 `imem_requests - fetch_packets = 19405 = branch mispredict total`、fetch packet/uop 恒等式和 actual class launch 恒等式。BRANCH_CAPACITY request/cycle 已达到 `0.9643`，窗口 IPC 从 `0.486` 升至 `0.916`；MEXT 与 MEMORY cycles 几乎不变，同时 legacy fallback 和 legacy wait 继续增长，清晰地把下一瓶颈固定到 A7.3 的 dual/legacy 域切换，而不是继续扩大配对白名单。

签核后重新核对 protected HEX、六项冻结 benchmark 软件/HEX 与 `test/tb_top.sv`，八项 SHA256 全部与 A7.1/12.2 记录一致，未重建软件、未修改 golden。A7.2 已独立签核，A7 总阶段保持 `IN_PROGRESS`；下一子阶段只处理安全 singleton simple residency 与域切换，不混入 A7.4 白名单项目。

#### 17.10.3 A7.3 singleton simple dual residency 设计与签核记录

```text
baseline:              6e00e029cb5f5a237fda6c3d241259227b15aa17 (A7.2 signed off, clean worktree)
design record commit:  979e92dc2d91136815f62a28cde883fbae08c5ec
implementation commit: 2baec50eaa175c0ebf28d82b74bc89a245d5cfdf
status:                SIGNED_OFF
scope:                 bundle_dispatch + dual_alu_pipeline + directed test + A7 measurement probe
out of scope:          Issue pairing whitelist, control/LSU/MULDIV/bitman/CSR singleton,
                       legacy pipeline, shared-unit timing and A7.4 pair classes
rollback gate:         any architectural mismatch, exception/sink/hash change, regression failure,
                       or no overall nine-window cycle reduction
next:                  A7.4 counter-guided selective pairing
```

A7.2 将前端空供给从 `458102` 降至 `38810` cycles，但九窗口仍有 `397807` 个 pair 回退 legacy 和 `637875` 个 legacy-domain drain wait cycles。连续供给也让 single-uop packet 从 `256809` 增至 `271157`；若一个安全 simple singleton 夹在两个 dual-compatible bundle 之间，现有 Dispatch 会先把它送进 legacy，再等待 legacy 全部排空后切回 dual。A7.3 只消除这一类无收益的域往返。

冻结以下候选、所有权和成本规则：

1. `simple singleton` 的唯一合法定义是 `lane0_valid && !lane1_valid && simple0`；`simple0` 必须来自 A6.1 已签核的 `pair_predecode`。control、LSU、MULDIV、bitman、CSR、非法编码和 lane0 无效 bundle 均不得通过 singleton 路径进入 dual resident。
2. 当前与 lookahead 的 `dual_candidate` 含义扩展为“可由 dual backend 原子接收的 bundle”，即原 A6 pair 候选或 simple singleton；pair 内部 class、LSU run rule、MULDIV 例外与 lane1 control rule 不变，不新增任何配对组合。
3. simple singleton 只有在 `legacy_idle && !prefer_legacy`，并且 `(dual_mode || next_dual_candidate)` 时才发往 dual。未建立 dual run 且 lookahead 尚未有效时保持 head 等待一次观察；lookahead 有效但不兼容时回 legacy。已经建立 dual run 时不因暂时缺 lookahead 而退出。
4. `legacy_idle` 继续是跨域硬排斥；`dual_block_legacy` 继续阻止 active long resident 与 younger legacy 重叠；redirect 同拍同时抑制 dual/legacy dispatch。singleton 不使用 MULDIV 对 `prefer_legacy` 的历史例外。
5. dual pipeline 接收 singleton 后只置 lane0 resident：`commit_valid=2'b01`、`retire_count=1`，lane1 不读寄存器、不写回、不产生 control/LSU/MULDIV event。redirect/exception/scoreboard/forwarding 的现有精确语义不变。
6. 性能 probe 将 simple pair 与 simple singleton 分开计数，并增加 dual `retire1` 计数；每窗口必须满足 `dual_launch = simple_pair + simple_singleton + control_pair + lsu_pair + muldiv_pair`，且在无异常的冻结 workload 中 `dual_launch = retire1 + retire2`。

定向签核至少覆盖：dual mode 内 singleton、singleton 与 compatible lookahead 建立/维持 dual run、lookahead gap 等待、非兼容 lookahead 回 legacy、`prefer_legacy` 回退、active legacy/dual exclusion、非 simple singleton 保持 legacy，以及 singleton 的单 lane writeback/retire/redirect kill。随后运行受影响 directed tests、`run_all.bat all`、冻结九窗口直跑与 A7 profile A/B；直跑和 wrapper 的九条 report、overall、sink 与 PASS 行必须一致，并复核八项冻结 SHA256。

实现只扩展 `bundle_dispatch` 对 dual-resident bundle 的定义：原有 pair candidate 完全不变，新增候选严格限定为 `lane0` simple singleton；尚未处于 dual mode 时仍服从 `legacy_idle`、`prefer_legacy` 与 compatible lookahead，已处于 dual mode 时则允许 singleton 保持驻留。`dual_alu_pipeline` 原有 lane0-only 数据路径不需要增加第二套执行逻辑，本阶段只收紧 accepted-class、lane1 event/retire 禁止条件和单 lane 退休断言。probe 新增 singleton 与 `retire1` 计数，不改 CPU 接口、CSR、冻结 report 或 benchmark。

定向与完整回归：

```text
directed: tb_issue_bundle_fifo
          tb_regfiles_4r2w
          tb_a3_dual_backend
          tb_a6_simple_control
          tb_a6_lsu_pair
          tb_a6_muldiv_pair
result:   6/6 passed; compile and simulations 0 errors / 0 warnings
logs:     F:\Tools\Temp\riscv-dual-rebuild-a7-3-*-directed-final.log
compile:  F:\Tools\Temp\riscv-dual-rebuild-a7-3-directed-compile-final.log

run_all.bat all: 78 passed / 0 failed; compile 0 errors / 0 warnings
run_all log:     F:\Tools\Temp\riscv-dual-rebuild-a7-3-run_all_all-final.log
```

冻结九窗口 A/B：

| Window | A7.2 cycles | A7.3 cycles | Delta | A7.2 IPC x1000 | A7.3 IPC x1000 |
| --- | ---: | ---: | ---: | ---: | ---: |
| ALU | 204030 | 180026 | -24004 | 1058 | 1199 |
| MEXT | 182042 | 186043 | +4001 | 296 | 290 |
| BRANCH_RANDOM | 269939 | 270203 | +264 | 911 | 910 |
| BRANCH_REGULAR | 117042 | 117043 | +1 | 820 | 820 |
| BRANCH_SHORT | 96042 | 99043 | +3001 | 968 | 939 |
| BRANCH_CALL | 188347 | 180240 | -8107 | 764 | 799 |
| BRANCH_CAPACITY | 75411 | 74385 | -1026 | 916 | 929 |
| BRANCH_RETURN | 912135 | 792131 | -120004 | 833 | 959 |
| MEMORY | 786746 | 787099 | +353 | 764 | 763 |
| **Overall** | **2831734** | **2686213** | **-145521** | **804** | **848** |

```text
result:       PERF_BENCHMARK_PASSED; nine reports; exceptions=0
overall:      cycles=2686213, instret=2279454, ipc_x1000=848
exact IPC:    0.8485752991292947
sink:         0x9D3BF787
compile log:  F:\Tools\Temp\riscv-dual-rebuild-a7-3-nine-window-compile-final.log
direct log:   F:\Tools\Temp\riscv-dual-rebuild-a7-3-nine-window-final.log
profile log:  F:\Tools\Temp\riscv-dual-rebuild-a7-3-profile-final.log
comparison:   direct and profile header, nine reports, overall and PASS are identical
protected HEX:C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

A7.2→A7.3 的真实退休数、branch mispredict、sink 和 exceptions 不变。overall cycles 减少 `145521`（`-5.139%`），精确 IPC 提升 `5.417%`；相对旧 A0 已少 `313711` cycles（`-10.457%`），相对正确退休口径的 A1 也少 `50414` cycles（`-1.842%`）。收益主要来自 BRANCH_RETURN（`-120004`）、ALU（`-24004`）、BRANCH_CALL（`-8107`）和 BRANCH_CAPACITY（`-1026`）；MEXT、BRANCH_SHORT、BRANCH_RANDOM 与 MEMORY 的局部回退保留为 A7.4 候选成本审计的护栏，不在本阶段跨范围改写共享单元或配对白名单。rollback gate 因整体周期显著下降且所有正确性门槛不变而通过。

| Profile metric | A7.2 | A7.3 | Delta |
| --- | ---: | ---: | ---: |
| IMEM request | 1403314 | 1400329 | -2985 |
| Fetch packet | 1383909 | 1380924 | -2985 |
| Fetched uop | 2496661 | 2490691 | -5970 |
| Single-uop packet | 271157 | 271157 | 0 |
| Fetch empty cycles | 38810 | 38810 | 0 |
| Actual dual launch | 407501 | 633512 | +226011 |
| Simple pair | 265458 | 293637 | +28179 |
| Simple singleton | 0 | 197652 | +197652 |
| Dual retire1 | 0 | 197652 | +197652 |
| Dual retire2 | 407501 | 435860 | +28359 |
| Legacy pair fallback | 397807 | 369447 | -28360 |
| Prefer-legacy fallback | 345061 | 344701 | -360 |
| Non-prefer legacy fallback | 52746 | 24746 | -28000 |
| Legacy drain wait cycles | 637875 | 824620 | +186745 |
| Dual backend wait cycles | 118000 | 118720 | +720 |

每窗口与总计均满足 class 守恒：`633512 = 293637 simple pair + 197652 singleton + 120043 control + 8180 LSU + 14000 MULDIV`；退休守恒也成立：`633512 = 197652 retire1 + 435860 retire2`。dual backend 覆盖的有效退休指令从 A7.2 的 `815002`（`35.754%`）增至 `1069372`（`46.914%`）。`wait_legacy` 的候选定义在 A7.3 扩展后会额外计入等待 legacy 排空的 singleton，因此其数值不能与 A7.2 直接解释为退化；更稳定的域切换指标是 non-prefer legacy fallback 减少 `28000`，同时整体周期下降 `145521`。

签核后重新核对 protected HEX、六项冻结 benchmark 软件/HEX 与 A0 适配后的 `test/tb_top.sv`，八项 SHA256 全部与 A7.2/12.2 记录一致，未重建软件、未修改 golden。A7.3 已独立签核，A7 总阶段保持 `IN_PROGRESS`；下一子阶段 A7.4 只根据现有 rejection、class 与窗口计数选择性开放配对，不继续扩大 singleton 类别。

#### 17.10.4 A7.4 data-driven selective pairing 设计记录

```text
baseline:              262e88a1c9fefe2b64135cf2d56959203c3c4636 (A7.3 signed off, clean worktree)
status:                SIGNED_OFF
implementation tranche: A7.4.1
implementation commit: 6051e2d0eac3605f43f1dfdd3d51deb81ceccca1
selected class:        PAIR_CONTROL_SIMPLE = older control0 + younger simple1
scope:                 defines + Issue + Dispatch + dual branch/commit selection
                       + MEM exception-valid qualification + directed tests
                       + A7 measurement probe
out of scope:          simple RAW/WAW relaxation, bitman execution, control+control,
                       control+LSU/MULDIV, dual LSU/MULDIV, legacy backend,
                       predictor/RAS policy, frozen CSR/report and A7.6 timing edits
census compile log:    F:\Tools\Temp\riscv-dual-rebuild-a7-4-census-compile.log
census log:            F:\Tools\Temp\riscv-dual-rebuild-a7-4-census.log
rollback gate:         any correctness/event/hash mismatch, regression failure,
                       no control0 launch, no struct reduction, or no overall cycle reduction
```

A7.3 的九窗口报告含 `477997` 个 RAW、`255495` 个 WAW 和 `145238` 个 structural reject，但 A6.1 已确认这些原因允许重叠，不能直接作为可开放配对数。为避免按总计误选，本阶段先用工作区外的一次性 measurement-only wrapper 观察当前 Issue head；wrapper 源文件在采样后删除且不进入提交，只保留日志。该运行的九条原报告、overall `2686213/2279454/848`、sink、PASS 与 A7.3 完全相同，编译和仿真均为 `0 errors / 0 warnings`。

候选普查结果：

| Candidate | Clean dynamic opportunities | Decision | Reason |
| --- | ---: | --- | --- |
| pure simple WAW younger-wins | 0 WAW-only | 不实施 | `252968` 个 simple WAW 全部同时是 RAW；只放宽写优先级没有性能机会 |
| simple RAW lane0→lane1 | 100079 RAW-only；另有 252968 RAW+WAW | 本次延后 | 覆盖潜力大，但会形成 RF→ALU0→mux→ALU1 的双 ALU 组合链，直接冲突 A7.6 的 5.000 ns 目标 |
| bitman0+simple1 / simple0+bitman1 | 0 / 0 | 不实施 | 冻结 workload 无机会，且 dual backend 当前没有 bitman datapath |
| control0+simple1 | 125265，全部无 RAW/WAW | **本次唯一实施项** | 占全部 structural reject 的 `86.248%`，可复用现有单 branch unit，并行 branch/simple 不增加串联 ALU 路径 |

`control0+simple1` 的窗口分布：

| Window | Clean opportunities |
| --- | ---: |
| ALU | 12000 |
| MEXT | 2 |
| BRANCH_RANDOM | 23801 |
| BRANCH_REGULAR | 22505 |
| BRANCH_SHORT | 14999 |
| BRANCH_CALL | 19950 |
| BRANCH_CAPACITY | 4 |
| BRANCH_RETURN | 32004 |
| MEMORY | 0 |
| **Total** | **125265** |

类别中含 `93256` 个条件分支、`23998` 个 JAL 和 `8011` 个 JALR。`92498` 次 lane0 预测 taken，恰好对应 `92498` 次非顺序 lane1 PC；其余 `32767` 次 lane1 PC 为 `pc0+4`。因此实现不得把 lane1 重新生成为固定 `pc0+4`，不得交换 lane 年龄，也不得假设 pair 来自同一取指 packet；必须原样保留 Fetch FIFO 已选择的预测路径 uop、PC、age 和 epoch。

冻结以下实现边界：

1. 在两个镜像 `defines.svh` 的现有 3-bit class 最后一个空闲编码增加 `PAIR_CONTROL_SIMPLE=3'd7`，不扩大 Bundle 或 Fetch metadata。Issue 只在 `control0 && simple1 && !raw_hazard && !waw_hazard` 时接受；JAL/JALR 的 `rd0` 到 lane1 source/destination 相关继续拆单，`control0+control1` 和所有未列类别继续 structural reject。
2. Dispatch 的 current/next pair candidate 与 `complex_candidate` 增加 `control0+simple1`。它与现有 lane1 control 一样可在 `legacy_idle && !prefer_legacy` 时直接建立 dual run；active legacy、`dual_block_legacy`、redirect、LSU run rule、MULDIV 例外及 A7.3 singleton lookahead 规则全部不变。
3. dual pipeline 仍只有一个 `branch_exec_unit`。按 control 所在 lane 选择 instruction、PC、RF operands、prediction metadata 和 direct target；新增保存 lane0 `pred_taken/pred_target`，不复制 branch unit、不交换 lane，也不把 control 送入 simple ALU。
4. 条件分支、JAL 与 JALR 的 branch/BP/RAS update 均使用 control lane 的 PC 和 instruction。control0 JAL/JALR 的 link 写回为 `pc0+4`；lane1 simple 继续使用其自己的 PC，因此 predicted-taken target 上的 AUIPC 等指令必须得到 target PC 而不是 fall-through PC。
5. dual resident 自己产生的 redirect 在当前 commit edge 清 frontend 并释放自身 resident，但不作为 external kill 在组合上抹去本 pair。control0 mispredict 时 fault-free control0 正常退休，预测路径上的 younger simple1 被精确取消；control0 IAM 时 faulting control0 和 younger simple1 都不退休。外部 redirect/exception 仍杀死两个 lane。
6. 保留现有 `lane1_control_event` 口径，新增内部 `control0_simple_event` 供 directed test 和 measurement-only probe 使用；不得占用冻结 CSR、修改 21-word report 或改变旧 lane1-control 计数。A7 probe 增加 `control0_simple_launches` 与 `control0_lane1_kills`，class/retire 恒等式同步包含新类。
7. simple RAW、WAW 和 bitman 不得借本次重构顺带开放。若 A7.4.1 签核后仍要评估 RAW，必须另建 A7.4.2 设计记录，先按 producer/consumer 操作细分并给出 5.000 ns 路径证据；不能把组合旁路隐藏在本类提交中。

精确退休矩阵：

| Resident / outcome | `commit_valid` | Redirect / exception rule |
| --- | ---: | --- |
| existing simple0+control1, correct or mispredict | `2'b11` | lane0 更老、lane1 是 control 本身，两条均可退休，保持现有行为 |
| existing simple0+control1, control1 IAM | `2'b01` | 只退更老 simple0，保持现有行为 |
| new control0+simple1, prediction correct | `2'b11` | lane1 是已验证预测路径，可退休 |
| new control0+simple1, direction/target mispredict | `2'b01` | 退 control0，禁止 lane1 writeback/retire，并 redirect |
| new control0+simple1, control0 IAM | `2'b00` | faulting control0 与所有 younger side effect 均禁止；只发 exception |
| either orientation, external kill before resolution | `2'b00` | 不发 branch/BP/writeback/retire event |

实现必须增加断言：control0 mispredict 不得退休 lane1；control0 IAM 不得退休任一 lane 或同时 redirect；control1 IAM 仍只能退休 lane0；branch event/BP update 必须来自唯一 control resident；correct predicted-taken pair 必须保留非顺序 lane1 PC；所有 accepted pair 仍满足同 epoch、`age1=age0+1` 和一次原子 launch。

定向签核至少覆盖：

1. `tb_issue_bundle_fifo`：branch/JAL/JALR0+simple1 class 接受；JAL/JALR RAW、WAW 仍拒绝；control+control 与未开放类别仍 structural reject；原六类 class 不变。
2. `tb_a3_dual_backend`：control0 pair 可作为 complex candidate 直接建立 dual run；`legacy_idle`、`prefer_legacy`、active dual/legacy、lookahead 与 redirect 排斥保持原边界。
3. `tb_a6_simple_control`：control0 正确 not-taken、正确 taken 且非顺序 lane1 PC、direction/target mispredict 的 lane1 kill、JAL call link、JALR return、lane0 IAM `commit=00`、external kill，以及所有现有 lane1-control 用例。
4. 重新运行 `tb_if_sync_btb`、`tb_regfiles_4r2w` 和受影响 LSU/MULDIV 定向测试，随后 `run_all.bat all` 78/78、冻结九窗口直跑和 A7 profile A/B。

性能签核要求 A7.3 的 `instret=2279454`、branch=`396041`、branch mispredict=`19405`、sink=`0x9D3BF787` 和 exceptions=0 不变；`control0_simple_launches > 0`，九窗口 structural reject 必须低于 `145238`，目标 branch 窗口 aggregate cycles 必须低于 A7.3 的 `1533045`，overall cycles 必须低于 `2686213`。直跑与 wrapper 的 header、九条 report、overall 和 PASS 必须一致；每窗口满足扩展后的 class identity 与 `dual_launch=retire1+retire2`。最后复核 protected HEX、六项冻结 benchmark 软件/HEX 和 `test/tb_top.sv` 八项 SHA256。任一正确性门槛失败或整体周期不降即回退本实现，不以提高 pair counter 代替真实性能收益。

A7.4.1 按冻结边界实现：Issue 仅接受无 RAW/WAW 的 `control0+simple1`，Dispatch 将其纳入 current/next complex candidate；dual branch 数据路径按 control lane 选择 PC、instruction、operands 与预测元数据。control0 正确预测退休 `11`，mispredict 只退休更老 control0（`01`），IAM 与 external kill 均退休 `00`；JAL/JALR link 固定使用 control0 的 `pc0+4`。原 lane1-control、LSU、MULDIV、singleton 和 legacy 规则保持不变，simple RAW/WAW 与 bitman 均未开放。

完整回归第一次只暴露 `rv32mi-p-ma_fetch` 失败。一次性 trace 证明 MEM resident 已无效后，`mem_stage` 仍把旧 `legacy_exception_code=0x2b` 驱动到 frontend，造成 redirect 常驻；A7.3 只是被一个更年轻的 legacy resident 偶然覆盖该旧值。修复将 `exception_code/exception_mtval` 严格限定在 `ms_valid && !ms_flush` 时有效，并扩展 `tb_lsu_exception_age` 检查 empty MEM 不得重复旧异常。该修改只补足既有有效位语义，没有加入全局 stall、跨级旁路或放宽配对。

定向与完整回归：

```text
directed: tb_issue_bundle_fifo
          tb_a3_dual_backend
          tb_a6_simple_control
          tb_a6_lsu_pair
          tb_a6_muldiv_pair
          tb_if_sync_btb
          tb_regfiles_4r2w
          tb_lsu_exception_age
result:   8/8 passed; compile and simulations 0 errors / 0 warnings
logs:     F:\Tools\Temp\a74_final_<top>.log

run_all.bat all: 78 passed / 0 failed; compile 0 errors / 0 warnings
elapsed:          145.4 s
```

冻结九窗口 A/B：

| Window | A7.3 cycles | A7.4.1 cycles | Delta | A7.3 IPC x1000 | A7.4.1 IPC x1000 |
| --- | ---: | ---: | ---: | ---: | ---: |
| ALU | 180026 | 144030 | -35996 | 1199 | 1499 |
| MEXT | 186043 | 186042 | -1 | 290 | 290 |
| BRANCH_RANDOM | 270203 | 208114 | -62089 | 910 | 1181 |
| BRANCH_REGULAR | 117043 | 67540 | -49503 | 820 | 1421 |
| BRANCH_SHORT | 99043 | 78053 | -20990 | 939 | 1191 |
| BRANCH_CALL | 180240 | 117112 | -63128 | 799 | 1229 |
| BRANCH_CAPACITY | 74385 | 74384 | -1 | 929 | 929 |
| BRANCH_RETURN | 792131 | 792131 | 0 | 959 | 959 |
| MEMORY | 787099 | 787099 | 0 | 763 | 763 |
| **Overall** | **2686213** | **2454505** | **-231708** | **848** | **928** |

```text
result:       PERF_BENCHMARK_PASSED; nine reports; exceptions=0
overall:      cycles=2454505, instret=2279454, ipc_x1000=928
exact IPC:    0.928681750496
sink:         0x9D3BF787
branch:       396041
brmisp:       19405
compile:      0 errors / 0 warnings
compile log:  F:\Tools\Temp\a74_final_perf_compile.log
direct log:   F:\Tools\Temp\a74_final_perf_direct.log
profile log:  F:\Tools\Temp\a74_final_perf_profile.log
comparison:   direct and profile header, nine reports, overall and PASS are identical
protected HEX:C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

A7.3→A7.4.1 的真实退休数、branch、branch mispredict、sink 和 exceptions 不变。overall cycles 减少 `231708`（`-8.626%`），精确 IPC 提升 `9.440%`；六个 branch 窗口 aggregate cycles 从 `1533045` 降至 `1337334`，structural reject 从 `145238` 降至 `19971`，全部性能 rollback gate 通过。签核只采用重新以 `PERF_BENCH` 和 `DEBUG_EN` 干净编译得到的最终日志；诊断期遗漏宏、产生历史错误 sink `0x4A27AD51` 的运行不属于有效结果。

| Profile metric | A7.3 | A7.4.1 | Delta |
| --- | ---: | ---: | ---: |
| IMEM request | 1400329 | 1389068 | -11261 |
| Fetch packet | 1380924 | 1369663 | -11261 |
| Fetched uop | 2490691 | 2468251 | -22440 |
| Fetch empty cycles | 38810 | 38810 | 0 |
| Actual dual launch | 633512 | 682572 | +49060 |
| Simple pair | 293637 | 281638 | -11999 |
| Simple singleton | 197652 | 185581 | -12071 |
| Lane1-control pair | 120043 | 118667 | -1376 |
| Control0-simple pair | 0 | 74506 | +74506 |
| Control0 lane1 kill | 0 | 5308 | +5308 |
| Dual retire1 | 197652 | 190889 | -6763 |
| Dual retire2 | 435860 | 491683 | +55823 |
| Legacy pair fallback | 369447 | 378454 | +9007 |
| Non-prefer legacy fallback | 24746 | 9749 | -14997 |
| Legacy drain wait cycles | 824620 | 738378 | -86242 |
| Dual backend wait cycles | 118720 | 118720 | 0 |

每窗口与总计均满足扩展后的 class 守恒：`682572 = 281638 simple pair + 185581 singleton + 118667 lane1 control + 74506 control0 simple + 8180 LSU + 14000 MULDIV`；退休守恒也成立：`682572 = 190889 retire1 + 491683 retire2`。control0 pair 的九窗口总计为 `74506`，其中 `5308` 次 mispredict 精确取消 lane1；旧 lane1-control 事件口径和冻结 21-word report 未改变。

最终八项 SHA256：

```text
test/tb_top.sv
77F2DABDCA7F9E0A7B179A8EA0FA9FE7FD031BD2EFBCF68A0F6067C7E0E59701
riscv_sim_perf_bench/benchmark.c
B91D22759F82E3872A65796ED23BF935F0C12E6BE876A29AFB56081A8AA34D5F
riscv_sim_perf_bench/startup.S
9FFC7C4A74EB76CA7EC68EDB6C3255B415ABAB87B6E46234E57D8F0842A5E514
riscv_sim_perf_bench/linker.ld
42D11987DE1AC460D50AB2DD614305890EB354D3AD9C8D70C665A93B230A361A
riscv_sim_perf_bench/Makefile
D4651025676521709768C1BBA5EB7885EA5D9D7204104B1CC4896BCA16E3CCF3
riscv_sim_perf_bench/out/inst.hex
459D81149CDD2A8886AE58F32AD27F58976AEECB82844B9BF4B1174FE96F9C7C
riscv_sim_perf_bench/out/data.hex
DDB214EE5E790F797FD84456E23DB9CBFF3DCA8E37DF59DC7AD8EB3EB409364B
hex/riscv-tests/rv32-p-riscv.hex
C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

A7.4.1 已独立签核，A7 总阶段保持 `IN_PROGRESS`。根据高 IPC 分支对照，正式时序收敛顺延到 A7.6；A7.5 先消除已经具备完整执行语义的 singleton 所造成的空退役与 dual/legacy 域往返，不启动 simple RAW 旁路。

#### 17.10.5 A7.5 安全 singleton 驻留与域切换签核

```text
baseline:              72b2aee (A7.4.1 signed off, clean worktree)
implementation commit: ff35e70
status:                SIGNED_OFF
scope:                 control/MULDIV singleton dual residency + lane-valid assertions + measurement probe
out of scope:          LSU admission/resident redesign, simple RAW/WAW, BTB/RAS, timing constraints or synthesis edits
rollback gate:         any architectural mismatch, pair-event semantic change, exception/sink/hash change,
                       regression failure or no overall nine-window cycle reduction
next:                  A7.6 staged timing convergence
```

A7.4.1 的新增 probe 基线显示九窗口共有 `666734` 个零退役周期，其中 `515674` 个周期同时存在未弹出的 Bundle head；另有 `101156` 个 control singleton 进入 legacy，`42532` 次从非 dual mode 建立 dual run，以及 `27420` 次 dual→legacy 交接。A7.5 不尝试把不可消除的分支恢复、LSU 等待或共享单元运算周期伪装成空泡，只处理已有执行单元能够完整承接的两类 lane0 singleton：

1. lane0 control singleton 复用现有 branch unit、redirect、BTB update 与 IAM 精确异常路径，可作为 complex candidate 直接建立 dual run；仍服从 `legacy_idle`、`prefer_legacy` 和 active-resident 排斥。
2. lane0 MULDIV singleton 复用 A6.4 shared-unit resident，可直接建立 dual run并沿用 start-once、done、redirect kill 与 completion-edge release；沿用既有 MULDIV 对历史 cooldown 的例外，避免已支持类别永久回退 legacy。
3. singleton 的合法退休向量只能是 `01` 或异常下的 `00`；accepted-class 与 branch assertions 改为显式 lane-valid 语义，禁止制造 lane1 retirement。
4. `MULDIV_PAIR` 继续只在 lane1 有效时计数；control/MULDIV singleton 均不得产生任何 pair-class event。LSU singleton 与 isolated LSU pair 保持 A6.3 成本门限不变。
5. measurement wrapper 新增 control/MULDIV singleton launch、zero-retire、dispatch-zero、legacy singleton fallback 和双向域交接计数；冻结 benchmark、21-word report、CSR 地址和 RTL 外部接口均不变。

定向与完整回归：

```text
directed: tb_issue_bundle_fifo
          tb_a3_dual_backend
          tb_a6_simple_control
          tb_a6_lsu_pair
          tb_a6_muldiv_pair
          tb_if_sync_btb
          tb_regfiles_4r2w
          tb_lsu_exception_age
result:   8/8 passed; compile and simulations 0 errors / 0 warnings
logs:     F:\Tools\Temp\a75_domain_<top>.log

run_all.bat all: 78 passed / 0 failed; compile 0 errors / 0 warnings
elapsed:          144.7 s
run_all log:      F:\Tools\Temp\a75_domain_run_all.log
```

冻结九窗口 A/B：

| Window | A7.4.1 cycles | A7.5 cycles | Delta | A7.4.1 IPC x1000 | A7.5 IPC x1000 |
| --- | ---: | ---: | ---: | ---: | ---: |
| ALU | 144030 | 144030 | 0 | 1499 | 1499 |
| MEXT | 186042 | 166041 | -20001 | 290 | 325 |
| BRANCH_RANDOM | 208114 | 201056 | -7058 | 1181 | 1223 |
| BRANCH_REGULAR | 67540 | 57047 | -10493 | 1421 | 1683 |
| BRANCH_SHORT | 78053 | 66049 | -12004 | 1191 | 1408 |
| BRANCH_CALL | 117112 | 108405 | -8707 | 1229 | 1328 |
| BRANCH_CAPACITY | 74384 | 72216 | -2168 | 929 | 957 |
| BRANCH_RETURN | 792131 | 792133 | +2 | 959 | 959 |
| MEMORY | 787099 | 787099 | 0 | 763 | 763 |
| **Overall** | **2454505** | **2394076** | **-60429** | **928** | **952** |

```text
result:       PERF_BENCHMARK_PASSED; nine reports; exceptions=0
overall:      cycles=2394076, instret=2279454, ipc_x1000=952
exact IPC:    0.952122656089447
sink:         0x9D3BF787
branch:       396041
brmisp:       19405
compile:      0 errors / 0 warnings
compile log:  F:\Tools\Temp\a75_domain_perf_compile.log
direct log:   F:\Tools\Temp\a75_domain_perf_direct.log
profile log:  F:\Tools\Temp\a75_domain_perf_profile.log
comparison:   direct and profile header, nine reports, overall and PASS are identical
protected HEX:C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3
```

A7.4.1→A7.5 的真实退休数、branch、branch mispredict、sink、exceptions 和八项冻结 SHA256 均不变。overall cycles 减少 `60429`（`-2.462%`），精确 IPC 提升 `2.524%`。所有窗口均无实质性回退；BRANCH_RETURN 的 `+2` cycles 来自跨窗口相位变化，事件总数与架构结果保持一致。

| Profile metric | A7.4.1 | A7.5 | Delta |
| --- | ---: | ---: | ---: |
| Actual dual launch | 682572 | 785298 | +102726 |
| Simple pair | 281638 | 291202 | +9564 |
| Simple singleton | 185581 | 192404 | +6823 |
| Control singleton | 0 | 91163 | +91163 |
| MULDIV singleton | 0 | 2000 | +2000 |
| Dual retire1 | 190889 | 290872 | +99983 |
| Dual retire2 | 491683 | 494426 | +2743 |
| Zero-retire cycles | 666734 | 609048 | -57686 |
| Dispatch zero-retire cycles | 515674 | 483014 | -32660 |
| Legacy pair fallback | 378454 | 368888 | -9566 |
| Legacy→dual establishment | 42532 | 27379 | -15153 |
| Dual→legacy transition | 27420 | 8182 | -19238 |
| Legacy drain wait cycles | 738378 | 729507 | -8871 |
| Dual backend wait cycles | 118720 | 152720 | +34000 |

每窗口与总计满足扩展后的 class 守恒：`785298 = 291202 simple pair + 192404 simple singleton + 91163 control singleton + 2000 MULDIV singleton + 125490 lane1 control + 60859 control0 simple + 8180 LSU pair + 14000 MULDIV pair`；退休守恒为 `785298 = 290872 retire1 + 494426 retire2`。MULDIV singleton 使 shared-unit wait 计数增加 `34000`，但消除了 legacy 管线填充及其前后的域往返，MEXT 实际减少 `20001` cycles，因此该计数变化不构成退化。

剩余 `8182` 次 dual→legacy 交接集中在 BRANCH_RETURN 的 `8001` 次和 MEMORY 的 `180` 次，均对应当前冻结的 LSU admission/resident 边界；非 LSU 的安全 singleton 域往返已经关闭。A7.5 独立签核通过。根据后续 IPC 优先决策，先执行 A7.5.1 的固定四拍 LSU 安全后继驻留，再决定何时进入 A7.6。

#### 17.10.6 A7.5.1 固定四拍 LSU 安全后继驻留签核

```text
baseline:              56b0142 (A7.5 signed off, clean worktree)
implementation commit: 5b451e8
status:                SIGNED_OFF
scope:                 established-dual LSU dispatch gate + directed coverage + profile clear alignment
hard invariant:        lsu_exec_unit and the fixed four-beat memory cadence are unchanged
out of scope:          isolated/back-to-back LSU admission, LSU state/port/response redesign,
                       multiple outstanding memory operations, simple RAW, BTB/RAS, timing constraints or synthesis edits
rollback gate:         any four-beat/request/store/exception mismatch, sink/hash change,
                       regression failure or no overall nine-window cycle reduction
next:                  measurement-only classification of the remaining 8000 non-prefer domain exits
```

A7.5 的 LSU pair 只有在已经处于 dual mode 且下一包为 simple pair 时才保留在 dual resident。冻结 workload 中，该限制使大量“LSU 后接已签核的一拍 simple/control 包”仍回到 legacy，尤其集中在 MEMORY 和 BRANCH_RETURN。A7.5.1 只放宽这个成本门，不改变访存执行：

1. 当前包仍必须是已支持的 `simple + LSU` 或 `LSU + simple`，并且必须已经处于 dual mode；isolated LSU 仍走 legacy。
2. 下一包只允许 simple pair、simple singleton、control singleton，或已签核的 `simple + control` / `control + simple` pair；另一个 LSU 和长 MULDIV 明确不作为 continuation。
3. `lsu_exec_unit`、E0-E3 固定四拍、data-port arbitration、registered response、precise Store、misaligned exception 和 stale-response quarantine 均未修改。
4. continuation 只使用既有 next-bundle predecode 结果，在 Dispatch 增加浅层类别 OR；没有 DRAM response→Dispatch 组合反馈、跨流水线 ready 链或新的大扇出全局 stall。该变化预估主频风险低，但本阶段未代替用户执行时序综合。
5. profile wrapper 在软件写 `PERF_CTRL.clear` 时同步清除 testbench-only 分类计数，修复复位后首次窗口中“本地计数保留、架构计数已清零”的观测偏差；不改 RTL、CSR 或冻结 report。

定向与完整回归：

```text
directed: tb_a3_dual_backend
          tb_a6_lsu_pair
          tb_a6_simple_control
          tb_a6_muldiv_pair
          tb_lsu_four_beat_load
          tb_lsu_store_commit
          tb_lsu_store_load_order
          tb_lsu_exception_age
result:   8/8 passed; simulations 0 errors / 0 warnings
logs:     F:\Tools\Temp\a751_lsu_cont_<top>.log

run_all.bat all: 78 passed / 0 failed; compile 0 errors / 0 warnings
elapsed:          143.4 s
run_all log:      F:\Tools\Temp\a751_lsu_cont_run_all.log
protected HEX:    C38DEA691298129419760AC66F9AED5D54846B182B05E33A817C3B996D280AA3 before/after
```

冻结九窗口 A/B：

| Window | A7.5 cycles | A7.5.1 cycles | Delta | A7.5 IPC x1000 | A7.5.1 IPC x1000 |
| --- | ---: | ---: | ---: | ---: | ---: |
| ALU | 144030 | 144030 | 0 | 1499 | 1499 |
| MEXT | 166041 | 166041 | 0 | 325 | 325 |
| BRANCH_RANDOM | 201056 | 201056 | 0 | 1223 | 1223 |
| BRANCH_REGULAR | 57047 | 57047 | 0 | 1683 | 1683 |
| BRANCH_SHORT | 66049 | 66049 | 0 | 1408 | 1408 |
| BRANCH_CALL | 108405 | 108405 | 0 | 1328 | 1328 |
| BRANCH_CAPACITY | 72216 | 72216 | 0 | 957 | 957 |
| BRANCH_RETURN | 792133 | 776125 | -16008 | 959 | 979 |
| MEMORY | 787099 | 694225 | -92874 | 763 | 866 |
| **Overall** | **2394076** | **2285194** | **-108882** | **952** | **997** |

```text
result:       PERF_BENCHMARK_PASSED; nine reports; exceptions=0
overall:      cycles=2285194, instret=2279454, ipc_x1000=997
exact IPC:    0.9974881782465734
sink:         0x9D3BF787
branch:       396041
brmisp:       19405
compile:      0 errors / 0 warnings
compile log:  F:\Tools\Temp\a751_lsu_cont_perf_compile.log
direct log:   F:\Tools\Temp\a751_lsu_cont_perf_direct.log
profile log:  F:\Tools\Temp\a751_lsu_cont_perf_profile.log
comparison:   direct/profile header, all nine reports, overall and PASS have zero differences
frozen hashes:test/tb_top.sv, benchmark source/build files, inst/data HEX and protected ISA HEX all unchanged
```

A7.5→A7.5.1 的退休数、branch、branch mispredict、sink、exceptions 和八项冻结 SHA256 均不变。overall cycles 减少 `108882`（`-4.548%`），精确 IPC 提升 `4.765%`。BRANCH_RETURN 减少 `16008` cycles（`-2.021%`），MEMORY 减少 `92874` cycles（`-11.800%`），其余七个窗口逐周期指标不变。

| Profile metric | A7.5 | A7.5.1 | Delta |
| --- | ---: | ---: | ---: |
| Actual dual launch | 785298 | 1223311 | +438013 |
| Simple pair | 291202 | 345465 | +54263 |
| Simple singleton | 192404 | 421907 | +229503 |
| Control singleton | 91163 | 91346 | +183 |
| MULDIV singleton | 2000 | 2000 | 0 |
| Lane1-control pair | 125490 | 171570 | +46080 |
| Control0-simple pair | 60859 | 68859 | +8000 |
| LSU pair | 8180 | 108164 | +99984 |
| MULDIV pair | 14000 | 14000 | 0 |
| Dual retire1 | 290872 | 520559 | +229687 |
| Dual retire2 | 494426 | 702752 | +208326 |
| Zero-retire cycles | 609048 | 708492 | +99444 |
| Dispatch zero-retire cycles | 483014 | 582822 | +99808 |
| Legacy pair fallback | 368888 | 160556 | -208332 |
| Legacy prefer fallback | 360704 | 152554 | -208150 |
| Legacy non-prefer fallback | 8184 | 8002 | -182 |
| Legacy→dual establishment | 27379 | 27384 | +5 |
| Dual→legacy transition | 8182 | 8000 | -182 |
| Legacy drain wait cycles | 729507 | 328857 | -400650 |
| Dual backend wait cycles | 152720 | 444490 | +291770 |

每窗口与总计满足 class 守恒：`1223311 = 345465 simple pair + 421907 simple singleton + 91346 control singleton + 2000 MULDIV singleton + 171570 lane1 control + 68859 control0 simple + 108164 LSU pair + 14000 MULDIV pair`；退休守恒为 `1223311 = 520559 retire1 + 702752 retire2`。固定四拍 LSU 进入 dual resident 的次数增加后，zero-retire 和 dual-wait 会随 resident 等待增加，但双退休与单退休的有效密度提高，最终总周期仍净减 `108882`，因此签核以架构结果和 overall cycles 为准，不以单个 stall 计数替代性能结论。

剩余 `8000` 次 dual→legacy transition 全部集中在 BRANCH_RETURN，且九窗口仍有 `8002` 次 non-prefer legacy fallback。A7.5.1 不猜测其具体类别并贸然打开 back-to-back LSU；下一步先做 measurement-only 分类。若后续方案需要多个 outstanding、改变四拍状态机、引入 response→Dispatch/Issue 长组合路径或显著扩大 ready/stall 扇出，必须先交由用户决定。
