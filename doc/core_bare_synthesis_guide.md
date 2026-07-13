# Core 裸核移植与 A7.6 时序综合指南

## 1. 基线与目标

本指南对应分支 `codex/dual-issue-rebuild-v1`，入口基线为 A7.5.5 文档提交 `294fc2a`。当前冻结性能为：

```text
cycles:       2077216
instret:      2279454
exact IPC:    1.0973601204689354
sink:         0x9D3BF787
exceptions:   0
regression:   78/78
```

A7.6 首轮目标器件与时钟沿用历史实现口径：

```text
part:         xc7k325tffg900-2
clock target: 200 MHz
period:       5.000 ns
```

分模块快速综合只用于筛查明显的逻辑深度、扇出、IP 或推导问题。最终结论必须来自 `cpu_top` 整体综合，随后再看布局布线；不能把 OOC synthesis 的正 slack 当作最终 200 MHz 签核。

## 2. 裸核文件集与顶层

裸核顶层是：

```text
top:          cpu_top
RTL:          rtl/cpu_top/*.sv
include path: rtl/cpu_top
header:       rtl/cpu_top/defines.svh
```

裸核综合不要加入：

```text
test/*
rtl/my_cpu/*
rtl/my_cpu/defines.svh
soc_inst_ram / soc_data_ram
```

`my_cpu` 是当前仿真/SoC 示例封装，不是可直接签核的裸核顶层。它在 `DEBUG_EN` 关闭时没有真实 IROM/DRAM 实现，两个 RAM module 只是空占位；真实 SoC 必须实例化自己的存储 IP 和 bridge/adapter。

`rtl/cpu_top/defines.svh` 与 `rtl/my_cpu/defines.svh` 当前内容重复，并共享同一个 include guard `__DEFINES_SVH__`。全 SoC 工程中先被编译/包含的副本可能遮蔽另一份。裸核工程只保留 `rtl/cpu_top` include path；全 SoC 工程在进入正式综合前应消除双副本配置漂移。

## 3. 综合宏配置

### 3.1 推荐矩阵

| 配置 | Questa 功能/性能回归 | 裸核时序综合 | 说明 |
| --- | --- | --- | --- |
| `DEBUG_EN` | On | Off | 仿真层次观察与 debug ports；还会改变 multiplier 实现 |
| `PERF_BENCH` | 性能测试 On | Off | On 时 reset PC=`0x00000000`；Off 时 reset PC=`0x80000000` |
| `SYNTHESIS` | Off | On | 关闭 `$fatal`/assertion-only block；不改变签核数据通路 |
| `Z_BITMAIN_ENABLE` | On | On | 当前冻结 ISA/回归的一部分，不得为时序方便擅自关闭 |
| `MUL_MULTICYCLE_ENABLE` | `1` | `1` | 保持冻结执行语义 |
| `MULTICYCLE_ENABLE` | `1` | `1` | 保持冻结执行语义 |
| `MUL_CYCLE` | `4` | `4` | 必须与 multiplier IP latency/valid 对齐 |

### 3.2 `DEBUG_EN` 的当前陷阱

`DEBUG_EN` 目前在以下两个源码 header 中直接定义，不是单纯由 `+define+DEBUG_EN` 或 Vivado `verilog_define` 控制：

```text
rtl/cpu_top/defines.svh
rtl/my_cpu/defines.svh
```

因此，综合工程即使没有在命令行添加 `DEBUG_EN`，它仍然是开启状态。正式时序综合前应做一个独立、可回退的配置提交：移除两处源码硬定义，仅在仿真 file set 中定义 `DEBUG_EN`。不要依赖工程侧“未添加宏”来假定它已经关闭。

`DEBUG_EN` 开启会产生三个影响：

1. `cpu_top`、`my_cpu`、`wb_stage` 和 `regfiles` 增加 debug ports/readout，部分内部状态因此不能被综合器裁剪。
2. `my_cpu` 使用行为级仿真 RAM；这不是生产 SoC memory implementation。
3. `mul` 使用 `assign product = src1_r * src2_r`；关闭后则实例化 `multiplier` IP。两种配置的资源、流水级和时序不能直接比较。

Questa 的冻结回归继续使用 `DEBUG_EN=On`。关闭后应另建 no-debug elaboration/synthesis smoke test；现有 testbench 依赖 debug ports 和 RAM hierarchy，不能拿它直接证明 no-debug file set 可编译。

### 3.3 Multiplier IP

仓库当前没有 `multiplier.xci`、综合网表或 module stub。`DEBUG_EN=Off` 时，`mul.sv` 需要外部提供：

```text
module: multiplier
ports:  CLK, CE, A[32:0], B[32:0], P[65:0]
latency contract: 与 MUL_CYCLE=4 对齐
```

综合 `mul`、`exe_stage`、`dual_alu_pipeline` 或 `cpu_top` 时必须加入真实 IP/XCI/DCP。允许 black box 只能用于检查非乘法逻辑是否能 elaborate，不能用于 WNS 或资源签核。用 `DEBUG_EN=On` 推导的乘法器结果也只能标记为 diagnostic，不是生产基线。

### 3.4 其他不能悄悄变化的配置

- `PERF_BENCH` 只应用于冻结 benchmark。真实 SoC 应关闭；若 reset vector 不是 `0x80000000`，应单独参数化 reset vector，而不是借用 `PERF_BENCH`。
- 性能 CSR `0x7C0-0x7D6` 当前没有 synthesis-disable 宏，会进入裸核。首轮整体综合必须保留它们以匹配签核 RTL。若后续要裁剪，应作为独立面积/时序变体并重新回归。
- `SYNTHESIS` 下删除的仅是 assertion block。应检查综合日志中没有 `$fatal`，同时不能误删功能 RTL。

## 4. 裸核外部接口契约

### 4.1 时钟、复位和中断

`cpu_top` 只有一个 `clk`。IROM、data adapter 和 `plic_irq` 都应与该时钟域同步；若来自其他时钟域，SoC 必须在 core 边界外完成 CDC。

core 内同时存在同步低有效 reset 和异步低有效 reset 寄存器。SoC 侧要求：

- `rst_n` 低电平保持至少若干个 core clock；
- 可以异步拉低，但必须同步释放；
- 推荐两级 reset synchronizer，所有 core-facing reset 使用同一个同步释放结果；
- 不要让 `plic_irq` 异步直接进入 core。

### 4.2 指令存储接口

```text
request:  imem_en, imem_addr, imem_addr1
response: imem_rdata, imem_rdata1
```

契约是固定一拍、双读口同步 IROM：

1. `imem_en=1` 的周期内，两个地址均有效；`imem_addr1=imem_addr+4`。
2. SoC 在该周期末的上升沿接受请求。
3. 两个 instruction word 必须在紧接的下一周期同时有效。
4. 接口没有 `imem_ready` 或 `imem_rvalid`，不能插 wait state，也不能晚一拍返回。
5. redirect 后旧请求的固定响应仍可到达，但 core 会用内部 epoch/valid 丢弃；SoC 不得改变响应顺序。

推荐用真双口 32-bit IROM，或能覆盖任意 `PC`/`PC+4` 组合的等价结构。若使用 64-bit line，必须正确处理跨 64-bit 边界，不能假定两个地址永远落在同一 line。不要在 IROM 前再无条件增加 address register，否则会把固定一拍接口变为两拍。

### 4.3 数据存储接口

```text
request/commit: dmem_en, dmem_addr, dmem_wen[3:0], dmem_wdata
load response:  dmem_rvalid, dmem_rdata
```

编码规则：

- `dmem_en=1 && dmem_wen==0`：一次 Load request；只脉冲一拍，SoC 必须无条件接受。
- `dmem_en=1 && dmem_wen!=0`：一次已经到达精确提交点的 Store；SoC 必须在该次脉冲只写一次，不返回 `dmem_rvalid`。
- `dmem_wen` 是 byte enable；`dmem_wdata` 已按 byte/half store 复制和对齐。
- Load 必须返回包含目标 byte/half 的 32-bit aligned word；符号扩展、byte/half 选择由 core 根据锁存地址完成，SoC 不要再次移位。
- 接口没有 request-ready、response tag 或 bus-error。固定四拍条件下，SoC 不得反压 request；未映射读也必须按时返回确定值（当前约定可为零），不能永久不响应。

### 4.4 固定四拍 Load 时序

以发出 request 的周期为 E0：

| Beat | Core | SoC / memory requirement |
| --- | --- | --- |
| E0 | `dmem_en=1`, address/request valid | 在周期末接受并锁存 request target/address |
| E1 | LSU resident hold | registered address 驱动 memory；同步 RAM 完成 read stage |
| E2 | LSU resident hold | `dmem_rvalid=1` 且 `dmem_rdata` 整拍稳定 |
| E3 | core 锁存 response，metadata/data 一起 release | `dmem_rvalid` 回到 0；不得重复响应 |

功能上 LSU 会一直等待 `dmem_rvalid`，所以晚响应可能仍能运行，但这会把固定四拍变成更多拍，违反当前性能与时序边界。早响应会缩短 resident，也不属于签核配置。SoC 集成验收必须检查每次 Load 都严格 E0-E3。

地址寄存和返回数据寄存需要由“CPU 边界 + memory IP + SoC adapter”共同实现，但同一个边界不能重复打拍：

- CPU 在 E0 内计算并锁存 address/metadata，但 request 端口在 E0 使用 live address；SoC 应在 E0 末锁存 target/address，切断 core address-adder 到 memory/decode 的后续长路径。
- 对同步 BRAM，BRAM 自带的 registered output 可以直接算作 response data register；此时不要再加一级 `rdata_r`，否则会变成五拍。
- 对异步 RAM/LUTRAM，E0 锁存 address 后，可在 E1 读取并在 E1 末锁存 selected data，使其在 E2 与 `dmem_rvalid` 一起返回。
- RAM、IO、PLIC 等所有读 target 必须统一对齐到 E2；target tag 和 valid 必须与数据经过相同数量的寄存级。

当前 `rtl/my_cpu/bridge.sv` 的 `read_target/read_valid` 是两级，但 `ram_rdata_r` 在原始 `cpu_read` 拍就采样，配合的是 DEBUG 异步 RAM。若替换成同步 BRAM，不能原样复用该 data capture enable；必须让 BRAM output 或 E1 capture 与 stage2 valid 对齐。

### 4.5 单 outstanding 与外部总线适配

core 同时最多有一个 Load outstanding，不带 ID。SoC 必须满足：

- 每个 accepted Load 恰好产生一次 response；
- response 严格有序，不重复、不合并到下一请求；
- redirect/kill 后旧 response 仍可返回，core 会 quarantine，但 SoC 不能把它当成新请求的 response；
- Store commit pulse和 Load request不能在 adapter 内重放。

AXI/AHB/外部 DRAM若不能保证固定两周期 response，不能直接接到这个接口并仍声称四拍 LSU。应使用确定延迟的本地 BRAM/scratchpad，或在 SoC 中加入能够保证 E2 hit 的 cache/adapter；否则必须重新定义 CPU memory handshake 和性能边界。

## 5. 分模块快速综合方法

### 5.1 统一约束

所有 OOC 结果至少满足：

```tcl
create_clock -name core_clk -period 5.000 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks core_clk]
```

纯组合 module 没有 `clk`，直接设为 top 时 WNS通常没有意义。二选一：

1. 用统一 OOC wrapper 在输入和输出各放一层寄存器，并保持 wrapper registers；这是推荐方法。
2. 建 virtual clock，并对所有 data input/output 设置一致的 `set_input_delay` / `set_output_delay`。

不能让 input/output path unconstrained，也不能因常量端口或未使用 output 被优化掉。每次报告同时保存：

```text
check_timing
report_timing_summary -delay_type max -max_paths 20
report_utilization
report_high_fanout_nets
report_clock_utilization
black-box/unresolved reference list
```

建议 OOC 使用同一 part、同一 wrapper、同一 flatten 策略；否则模块间 slack 不可横向比较。

### 5.2 推荐顺序

第一组，先筛最可能存在深组合路径的 leaf：

1. `divider`：`/`、`%` 在 start edge 直接进入 `pending_result`。`LATENCY=1` 只改变 busy/done，不是 pipeline；若差，不能靠调大/调小计数器修时序。A7.5.4 的“低增量 Fmax 风险”只表示 counter 缩短没有新增组合深度，不表示原有组合除法本身已经满足 5 ns；若 OOC 失败，必须改 divider 数据实现并重新评估 latency/IPC。
2. `simple_alu_exec_unit` / `alu_exec_unit`：ALU decode、adder、shift/compare。
3. `branch_exec_unit`：compare、target、mispredict/redirect。
4. `lsu_exec_unit`：base+immediate、alignment、store byte-enable 到 request register 边界。
5. `dual_scoreboard`：4 consumer source x 6 producer compare/priority network。
6. `issue_stage`、`bundle_dispatch`、`pair_predecode`：配对、RAW/WAW、lookahead 和 dispatch control。

第二组，检查状态阵列和前后端 cluster：

1. `regfiles`：2W、legacy 2R、dual synchronous 4R 及同拍 write bypass；关注 register-file 推导和 reset fanout。
2. `regfile_csr`：CSR mux、性能 counter increment/fanout。
3. `if_stage`：双份 128-entry BTB、RAS、response bypass、request PC；必须观察 RAM/LUTRAM 推导结果。
4. `id_stage`、`exe_stage`、`mem_stage`：legacy backend 的跨模块控制与结果 mux。
5. `dual_alu_pipeline`：scoreboard、shared LSU/MULDIV、branch、commit mux；必须带真实 multiplier IP。

第三组：

1. `cpu_top` 纯裸核整体综合，外部 imem/dmem 端口按接口 delay 约束。
2. 加 SoC memory adapter 后整体综合，重点比较 RF/LSU address、IROM/BTB、DRAM response 和 redirect/control 路径。
3. 最后才进入 place/route 与 phys-opt；synth slack 不能替代 routed WNS/TNS。

### 5.3 快速决策门

在统一 5 ns wrapper/约束下，可用以下粗粒度门限筛查，不作为最终签核：

- WNS `<= -0.5 ns`、存在明显超预算逻辑级数、黑盒或异常高扇出：先修该 module。
- WNS `>= +0.5 ns` 且无 unconstrained path/black box：暂不局部优化，进入上一级 cluster。
- `-0.5 ns < WNS < +0.5 ns`：记录为 integration-sensitive，先看上一级和整体路径，避免过早重构。

每次修改仍必须遵守：

- 不缩短或延长固定四拍 LSU；
- 不改变 single-outstanding、Store commit-only 和精确异常；
- 不以修改 `MUL_CYCLE` 或 divider busy counter 掩盖真实数据路径；
- 不开启同拍 RAW bypass；
- 可能显著影响 IPC、ISA、SoC protocol 或 Fmax 的结构改动先交由用户决定。

## 6. A7.6 阶段签核记录模板

每个 module/cluster 记录：

```text
commit / dirty state:
part / speed grade:
top / file set / include paths:
defines: DEBUG_EN, PERF_BENCH, SYNTHESIS, Z_BITMAIN_ENABLE:
IP/XCI/DCP versions:
clock / uncertainty / IO budgets:
unconstrained paths:
black boxes:
WNS / TNS / failing endpoints:
logic levels / route estimate:
top critical path startpoint -> endpoint:
high-fanout nets:
LUT / FF / BRAM / DSP:
decision: FIX / HOLD / PROMOTE_TO_CLUSTER:
```

整体 `cpu_top` timing fix 后至少重跑：

```text
affected directed tests
run_all.bat all (78/78)
frozen nine-window benchmark
sink / exceptions / instret / cycles / exact IPC
inst.hex and data.hex SHA256
```

只有 routed design 在目标 period 下 setup/hold 通过，且 no-debug、真实 multiplier IP、真实 SoC memory adapter 与冻结 RTL 行为一致，A7.6 才能最终 `SIGNED_OFF`。
