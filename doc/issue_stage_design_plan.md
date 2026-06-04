# Issue Stage Design Plan

本文档用于推演并规划当前 `rtl/cpu_top/issue_stage.sv` 的可实行改造路径。目标是在现有双 lane 后端框架基础上，把当前组合直通的 issue stage 改造成能支持顺序双发射、相关性检查、结构冲突规避和精确 flush 的前端调度单元。

## 1. 当前结构判断

当前 RTL 已经具备双发射改造的骨架，但 issue 本身还没有真正承担调度职责：

- `issue_stage.sv` 目前只是组合直通：
  - `is_to_ds_valid = fs_to_is_valid`
  - `is_allowin = ds_allowin`
  - lane1 同样直通，但上游当前没有真实接入。
- `cpu_top.sv` 中 `if_stage` 的第二取指端口未接出：
  - `.pc_out1()`
  - `.inst_ren1()`
  - `.inst_in1()`
  - `.ds_allowin1(1'b0)`
- `if_stage.sv` 已经有 lane1 端口和 `pc_out1 = next_pc + 4` 的雏形，但 SoC 指令 RAM 顶层没有把第二端口连到 CPU。
- `id_exe_stage.sv` 已经实例化两套 `id_stage + exe_stage`，并向 `mem_stage/wb_stage/regfiles` 提供双路接口。
- `regfiles.sv` 已支持双写、四读，并有 WB 到 ID 的前递。
- `mem_stage.sv`、`wb_stage.sv` 已支持双路流水寄存和双写回。
- lane1 当前不完整：
  - lane1 的 FPU 读口在 `id_exe_stage.sv` 中绑空/绑零。
  - lane1 的 CSR 读口绑空/绑零。
  - `id_exe_stage` 对 DMEM、branch、exception 采用 lane0 优先仲裁。

用户确认后的方向是：两条执行线路按完整 lane 建设，issue stage 不把 lane1 做成简化执行线，而是在发射时判断 lane1 本拍是否安全；若不安全，则裁掉本拍 lane1 发射，并保持程序顺序。

第一版 issue 采用最小状态实现：只保留 1 个 hold 槽。该槽保存“本拍 lane1 候选不能发射但不能丢”的年轻指令，下一拍作为 lane0 继续发射。

## 2. Issue Stage 的职责边界

推荐让 issue stage 做轻量预译码和调度，不把 `id_stage` 的完整译码复制进来。

Issue stage 应承担：

1. 接收 IF 的 1 条或 2 条顺序指令。
2. 缓冲取指结果，避免下游单 lane 阻塞时丢失第二条指令。
3. 对候选双发射指令做轻量预译码：
   - opcode/funct3/funct7
   - rs1/rs2/rd
   - 是否需要 rs1/rs2
   - 是否写 GPR/FPR/CSR
   - 指令类别：ALU、bitman、load/store、branch/jump、CSR/system、FPU、mul/div、fence、unknown
4. 判断两条指令能否同周期发射。
5. 输出 lane0/lane1 的 valid 和 bus。
6. 在分支重定向、异常、issue 自身取消发射时产生精确 flush。

Issue stage 不建议承担：

- 完整控制包生成，这仍放在 `id_stage`。
- 操作数读取，这仍由 `id_stage` 和 `regfiles` 完成。
- EX/MEM/WB 的跨周期冒险检测，这当前已经在 `id_stage` 中做 load-use 和前递选择。

## 3. 推荐微架构

### 3.1 输入缓冲

在 `issue_stage` 内增加一个 2 到 4 项的小 FIFO，保存 `FS_DS_WIDTH` 包。

推荐第一版不做完整 FIFO，而使用 1 项 hold 槽：

```text
IF lane0/lane1 -> issue hold slot + pair selector -> ID lane0/lane1
```

原因：

- 状态最少，便于先验证双发射顺序语义。
- lane1 被裁时不会跳过该指令，而是进入 hold 槽。
- 后续若 IF 双取指返回和下游阻塞更复杂，再扩展为 2 到 4 项 FIFO。

hold 行为：

- `hold_valid=0`：
  - lane0 候选来自 IF lane0。
  - lane1 候选来自 IF lane1。
  - 若 lane1 不能发射，则 IF lane1 写入 hold。
- `hold_valid=1`：
  - lane0 候选来自 hold。
  - lane1 候选来自 IF lane0。
  - 本拍不接收 IF lane1，避免超过 1 项 hold 能力。

### 3.2 配对选择

每周期查看 FIFO 头两条：

```text
inst0 = fifo[head]
inst1 = fifo[head + 1]
```

默认规则：

- lane0 优先发射 `inst0`。
- 只有 `inst0` 和 `inst1` 都 valid，且 `can_pair(inst0, inst1)` 为 1，才发射 lane1。
- 如果不能配对：
  - lane0 发射 `inst0`
  - lane1 发射 NOP/valid=0
  - `inst1` 留在 FIFO 中等待下一拍作为新的 lane0

### 3.3 Lane 分工

两条 lane 按完整执行线规划。issue 不通过“lane1 只支持某类指令”来定义架构能力，而是通过配对规则裁掉不安全的 lane1 发射。

第一版最小配对策略仍应保守：

- lane0 始终是较老指令。
- lane1 只有在不破坏顺序、不触发同周期相关性、不冲突共享资源时发射。
- 若 lane1 被裁，该指令进入 hold 槽，下一拍作为 lane0 发射。

## 4. 轻量预译码字段

建议在 `issue_stage.sv` 内定义预译码结构。若工具链对 packed struct 支持稳定，可以用 `typedef struct packed`；否则用离散 logic 信号。

推荐字段：

```systemverilog
typedef struct packed {
    logic        valid;
    logic [31:0] inst;
    logic [31:0] pc;
    logic        bp_pred_taken;
    logic [31:0] bp_pred_target;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic        need_rs1;
    logic        need_rs2;
    logic        write_gpr;
    logic        write_fpr;
    logic        write_csr;
    logic        is_load;
    logic        is_store;
    logic        is_branch;
    logic        is_jump;
    logic        is_csr;
    logic        is_system;
    logic        is_fpu;
    logic        is_muldiv;
    logic        is_multicycle;
    logic        is_fence;
    logic        is_simple_int;
    logic        is_serial;
} issue_info_t;
```

`is_serial` 第一版建议包含：

- branch/jump
- CSR/system/ecall/ebreak/mret
- fence
- load/store
- FPU
- mul/div
- unknown/illegal

第一版 `can_pair` 建议：

```text
inst0 和 inst1 均 valid
inst0 不能是 serial
inst1 不能是 serial
两条之间没有同周期 RAW/WAW/特殊资源冲突
```

## 5. 同周期配对规则

### 5.1 顺序约束

双发射必须保持程序顺序：

- FIFO 中较老指令永远进 lane0。
- 较新指令只可进 lane1。
- lane1 不能越过 lane0。

### 5.2 RAW 规则

若 inst1 读取 inst0 写回的 GPR，则第一版不配对：

```text
raw01 =
  inst0.write_gpr && inst0.rd != x0 &&
  ((inst1.need_rs1 && inst1.rs1 == inst0.rd) ||
   (inst1.need_rs2 && inst1.rs2 == inst0.rd))
```

第一版推荐直接禁止 `raw01`。后续可加入 lane0 EXE 到 lane1 EXE 的同周期旁路，但会明显增加复杂度。

### 5.3 WAW 规则

若 inst0 和 inst1 同时写同一 GPR，第一版不配对：

```text
waw01 =
  inst0.write_gpr && inst1.write_gpr &&
  inst0.rd != x0 && inst0.rd == inst1.rd
```

虽然当前 `regfiles.sv` 双写端口后写可能覆盖前写，但为了保持顺序和调试简单，第一版建议禁止。

### 5.4 WAR 规则

顺序五级流水、寄存器读在 ID，写在 WB，且两条同周期进入 ID。第一版无需特别处理 WAR。

### 5.5 结构冲突规则

第一版裁掉以下组合的 lane1：

- 任意一条是 load/store，避免单 DMEM 接口冲突。
- 任意一条是 branch/jump，避免预测和 flush 精确性复杂化。
- 任意一条是 CSR/system/fence，避免 CSR 顺序副作用冲突。
- 任意一条是 FPU/muldiv，先避开多周期/共享资源组合复杂度。

保守的 `can_pair`：

```text
can_pair =
  valid0 && valid1 &&
  !info0.is_serial &&
  !info1.is_serial &&
  !raw01 &&
  !waw01
```

### 5.6 分支预测边界

第一版建议：

- 若 inst0 是 branch/jump，不发 lane1。
- 若 inst1 是 branch/jump，不发 lane1。
- IF 可以继续预测取指，但 issue 对分支指令串行化。

这样能保证错误预测时只有较年轻指令在 FIFO/ID 被清掉，精确性容易验证。

## 6. Flush 与异常

`flush` 的语义：该标志不是普通 stall，也不是 issue 内部“不能配对”的代名词；它表示对应指令已经走上错误路径或因异常/重定向应当被后级丢弃。

`issue_stage` 需要处理三类情况：

1. `br_taken` 或 `exception_flag` 来自后端：
   - 清空 hold 槽。
   - `is_flush/is_flush1` 拉高一拍给下游。
2. issue 自身因为配对失败：
   - 不属于 flush，只是不发 lane1。
   - lane1 valid 为 0，该 lane1 候选进入 hold 槽。
3. lane0 发分支/serial 指令：
   - lane1 不发射，不需要 flush，候选进入 hold 槽。

建议实现：

```systemverilog
logic global_flush;
assign global_flush = br_taken || exception_flag;

assign is_flush  = global_flush;
assign is_flush1 = global_flush;
```

同时在 hold 时序逻辑中：

```text
if (!rst_n || global_flush) clear hold
else update push/pop
```

额外 debug 约束：

- 被 flush 的指令到 WB 时，其 PC 必须被改写为固定值，推荐 `32'b0`。
- 这样可以避免错误路径上的 `0x8000_0044` 到达 debug WB PC，误触发现有 testbench 的结束条件。

## 7. 握手协议建议

### 7.1 下游 allow

只有当对应 ID lane 可以接收，issue 才能对该 lane 发射：

- 单发射需要 `ds_allowin == 1`
- 双发射需要 `ds_allowin == 1 && ds_allowin1 == 1`

如果 lane0 不 allow：

- 不 pop FIFO。
- `is_to_ds_valid/is_to_ds_valid1` 保持 0 或保持当前 pending 输出，第一版建议用 FIFO 输出组合 valid，依赖不 pop 保持数据。

### 7.2 上游 allow

推荐由 FIFO 空间决定：

```text
free_slots = FIFO_DEPTH - fifo_count
is_allowin  = free_slots >= 1
is_allowin1 = free_slots >= 2
```

若暂时未接真实双取指，`is_allowin1` 可先保持对外正确，但 `cpu_top` 仍可传入 `fs_to_is_valid1=0`。

## 8. 顶层和 IF 配套改造

Issue 真正发挥作用需要逐步接通前端 lane1。

### 8.1 第一阶段：只改 issue，不接双取指

目标：

- `issue_stage` 内部具备 FIFO 和配对逻辑。
- 当前 `cpu_top` 仍只给 lane0 输入。
- 所有既有单发射测试必须保持通过。

价值：

- 先验证 issue 不破坏原行为。
- 为后续双取指接入提供稳定接口。

### 8.2 第二阶段：接通 IF lane1 到 cpu_top

需要修改：

- `cpu_top.sv`
  - 增加 `imem_addr1/imem_en1/imem_rdata1`，或在 SoC 内部使用双端口 instruction RAM。
- `my_cpu.sv`
  - 接通 `soc_inst_ram` 的第二读端口。
- `if_stage.sv`
  - 修正 lane1 bus 中 PC 使用，应保持与真实返回的 `inst_in1` 对齐。
  - 现有 `fs_to_ds_bus1 = {inst_in1, next_pc + 4, ...}` 可能不够严谨，因为 lane0 使用的是 `fs_pc`，lane1 应使用同一取指批次的 `fs_pc + 4`。

建议新增：

```systemverilog
logic [31:0] fs_pc1;
assign fs_pc1 = fs_pc + 32'd4;
assign fs_to_ds_bus1 = {inst_in1, fs_pc1, 1'b0, 32'b0};
```

### 8.3 第三阶段：放宽 lane1 能力

在 simple integer lane 稳定后再逐步打开：

1. lane1 branch，但要求 lane0 不是 branch 且 lane0 不产生 redirect。
2. lane1 load/store，需要 DMEM 仲裁和 load-use 验证加强。
3. lane1 CSR，需要 CSR 双读或 issue 串行化继续保持。
4. lane1 FPU，需要接通 FPU 寄存器更多读端口或限制 FPU 单发。
5. lane1 mul/div，需要处理多周期单元结构冲突和 `ms_allowin` 阻塞传播。

## 9. 推荐实施步骤

### Step 0: 建立保护测试

先跑现有回归，记录基线：

```bat
run_all.bat base
```

若可用，再跑：

```bat
run_all.bat z
```

### Step 1: 重写 issue_stage 为 hold + 单发射兼容

修改 `rtl/cpu_top/issue_stage.sv`：

- 增加 1 项 hold 槽。
- 增加 `global_flush`。
- 当前即使只有 lane0 输入，也通过 issue 输出到 lane0。
- lane1 被裁时进入 hold，下一拍作为 lane0。

验收：

- 当前未接双取指时行为应等价单发射。
- base 回归通过。

### Step 2: 增加轻量预译码

在 `issue_stage.sv` 内实现 `decode_issue_info` function。

第一版最少识别：

- `is_simple_int`
- `is_load`
- `is_store`
- `is_branch`
- `is_jump`
- `is_csr/system`
- `is_fpu`
- `is_muldiv`
- `write_gpr`
- `need_rs1/need_rs2`

验收：

- 随机或手写指令序列中，只有 safe pair 会双发。
- 不 safe pair 自动退化单发。

### Step 3: 接通 cpu_top 的第二取指信号

需要选择顶层接口策略：

方案 A：扩展 `cpu_top` 外部接口：

```systemverilog
output logic [31:0] imem_addr1,
output logic        imem_en1,
input  logic [31:0] imem_rdata1
```

方案 B：保持 `cpu_top` 外部接口不变，在 `my_cpu` 包装内单独处理双端口 RAM。

推荐方案 A，因为职责清晰，后续接指令 cache 或 AXI 时也更自然。

验收：

- 单指令流仍可运行。
- 两条顺序 ALU 指令可进入 lane0/lane1。

### Step 4: 修正 IF lane1 PC/valid 语义

修正 `if_stage.sv`：

- lane0/lane1 的 PC 必须来自同一个 fetch packet。
- 当预测跳转或 redirect 时，lane1 必须无效或变 NOP。
- 若当前取指地址不是 8 字节对齐，第一版仍可发 `pc` 和 `pc+4`，不要求 8 字节对齐，但要保持程序顺序。

验收：

- 双发射 debug PC 顺序正确。
- redirect 后 FIFO/ID 不保留错误路径指令。

### Step 5: 完善验证

新增或扩展 testbench/hex：

1. 单发射兼容：
   - 原 RV32I 基础测试全部通过。
2. 双 ALU：
   - `addi x1, x0, 1`
   - `addi x2, x0, 2`
   - 期望同周期进入两个 lane，最终写回正确。
3. 同周期 RAW 禁止配对：
   - `addi x1, x0, 1`
   - `addi x2, x1, 2`
4. WAW 禁止配对：
   - `addi x1, x0, 1`
   - `addi x1, x0, 2`
5. branch 串行：
   - branch 后一条不得进入 lane1。
6. load/store 串行：
   - load/store 与后一条不配对。
7. CSR/system 串行：
   - `csrrw/ecall/mret` 不与后一条配对。
8. flush 精确性：
   - branch redirect 后 FIFO 清空。
   - exception 后 FIFO 清空。

## 10. 需要确认的设计问题

以下问题会影响最终实现范围：

1. 是否确认第一版 issue 只用 1 项 hold，而不是完整 FIFO？
   - 当前按已确认方向实现最小状态 hold。
2. 是否愿意扩展 `cpu_top` 顶层指令存储器接口为双端口？
   - 推荐扩展。否则双取指只能在 SoC 包装里绕，后续维护更麻烦。
3. 同周期 lane0 写、lane1 读是否要做旁路？
   - 推荐第一版不做，遇到 RAW 直接单发。
4. load/store 是否允许和普通 ALU 同拍发射？
   - 推荐第一版不允许。等基础双发射稳定后再开放。
5. branch 是否允许出现在 lane1？
   - 推荐第一版不允许。这样 flush 和预测更新都保持简单。
6. lane1 是否最终需要完整支持 FPU/CSR/muldiv？
   - 当前架构方向是完整支持；第一版 issue 先保守裁掉相关组合，后续逐步放开。

## 11. 推荐第一版验收标准

第一版完成后应满足：

- 未接双取指时，所有原有单发射回归通过。
- 接双取指后，安全的连续整数指令可双发。
- 不安全组合自动退化为单发，不产生错误写回。
- branch/exception 后错误路径指令不会进入 WB。
- lane0/lane1 写回顺序和结果符合程序语义。
- 不修改对外数据存储器接口，不引入 cache，不改变现有 SoC 外设地址映射。

## 12. 最小可执行任务清单

建议按以下 commit 粒度推进：

1. `issue: add fifo shell while preserving single issue`
   - 重写 `issue_stage` 为 FIFO 结构。
   - 保持当前单发射行为。
2. `issue: add lightweight predecode and pair checks`
   - 加入 simple/int/serial 分类。
   - 加入 RAW/WAW 配对禁止。
3. `fetch: expose second instruction port`
   - 扩展 `cpu_top` IF 接口。
   - 接通 `my_cpu` 的 `soc_inst_ram` 第二端口。
4. `fetch: fix lane1 pc and flush semantics`
   - 修正 IF lane1 PC 和 valid。
   - redirect/exception 时清空 issue FIFO。
5. `test: add dual issue smoke tests`
   - 添加双 ALU、RAW、WAW、branch flush、load 串行测试。
