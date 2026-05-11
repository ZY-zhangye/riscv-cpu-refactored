# RISC-V CPU Design Porting Summary

本文档用于把当前 `riscv-cpu-refactored` 工程中的 CPU 设计迁移到其它工作区时快速恢复上下文。内容基于 2026-05-08 当前工作区状态整理。

## 1. 工程定位

当前设计是一个 RV32 单发射顺序五级流水 CPU，核心流水位于 `rtl/cpu_top`，外层 `my_cpu.sv` 提供片上 RAM、UART 和板级 MMIO 包装。

主要特性：

- RV32I 基础整数指令。
- M 扩展乘除法指令，乘法可配置多周期，除法为多周期。
- 部分 F 单精度浮点相关数据通路和测试支持。
- 机器模式 CSR、异常、`ecall/ebreak/mret`。
- 简单分支预测 BTB，预测在 IF 阶段，更新在 EXE 阶段。
- 已加入一批 Z-bitman 指令子集：Zba、Zbb 子集、Zbkb、Zbs。
- 指令和数据存储器采用类 Harvard 接口：取指接口和数据访存接口分离。

## 2. 推荐迁移文件清单

迁移核心设计时建议带走以下文件：

```text
rtl/cpu_top/defines.svh
rtl/cpu_top/cpu_top.sv
rtl/cpu_top/if_stage.sv
rtl/cpu_top/id_stage.sv
rtl/cpu_top/exe_stage.sv
rtl/cpu_top/mem_stage.sv
rtl/cpu_top/wb_stage.sv
rtl/cpu_top/regfiles.sv
rtl/cpu_top/regfile_csr.sv
rtl/cpu_top/reg_fpu.sv
rtl/cpu_top/mul.sv
rtl/cpu_top/divider.sv
rtl/cpu_top/fpu.sv
```

如果目标工程需要复用当前仿真/板级外设包装，也带走：

```text
rtl/cpu_top/my_cpu.sv
test/tb_cpu_top.sv
test/tb_top.sv
hex/
run_all.bat
```

`my_cpu.sv` 内部还定义了 `simple_inst_ram`、`simple_data_ram`、`uart_minimal`，如果目标工程已有自己的 RAM/UART，可以只复用 `cpu_top.sv` 及流水内部文件。

## 3. 顶层接口

### 3.1 `cpu_top`

`cpu_top.sv` 是纯 CPU 核心顶层，接口如下：

```systemverilog
module cpu_top (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] imem_rdata,
    output logic [31:0] imem_addr,
    output logic        imem_en,

    input  logic [31:0] dmem_rdata,
    output logic [31:0] dmem_addr,
    output logic [3:0]  dmem_wen,
    output logic        dmem_en,
    output logic [31:0] dmem_wdata
);
```

取指 RAM 的读数据时序按当前 `if_stage` 处理：IF 阶段内部保留了一拍寄存，这是为时序收敛做的，不建议删除或前移。

数据访存接口：

- `dmem_en` 表示本拍有数据访问。
- `dmem_wen == 4'b0000` 表示读。
- `dmem_wen != 0` 表示写，按字节使能。
- `dmem_addr` 为字节地址。
- `dmem_wdata` 已在 EXE 阶段对 `sb/sh/sw` 做好字节复制。

### 3.2 `my_cpu`

`my_cpu.sv` 是板级包装顶层：

```systemverilog
module my_cpu (
    input  logic        clk,
    input  logic        clk_cnt,
    input  logic        rst_n,
    output logic [31:0] led,
    input  logic [7:0]  key,
    input  logic [63:0] sw,
    output logic [39:0] seg
);
```

内部实例化：

- `cpu_top`
- `simple_inst_ram`
- `simple_data_ram`
- `uart_minimal`
- LED、数码管、拨码开关、按键、计数器 MMIO

`clk_cnt` 当前仅保留作板级兼容，不参与逻辑。

## 4. 地址映射

关键地址宏在 `defines.svh`。

```text
PC_START:
  PERF_BENCH 定义时为 0x0000_0000
  默认          为 0x8000_0000

UART:
  UART_BASE_ADDR   0x8001_0000
  UART_DATA_ADDR   0x8001_0000
  UART_STATUS_ADDR 0x8001_0004
  UART_CTRL_ADDR   0x8001_0008
  UART_BAUD_ADDR   0x8001_000C

Board MMIO:
  SW_LOW_ADDR  0x8020_0000
  SW_HIGH_ADDR 0x8020_0004
  KEY_ADDR     0x8020_0010
  SEG_ADDR     0x8020_0020
  LED_ADDR     0x8020_0040
  CNT_ADDR     0x8020_0050

Data RAM select in my_cpu:
  benchmark data area: dmem_addr[31:28] == 4'h6
  official DRAM area: 0x8010_0000 ~ 0x8013_FFFF
```

官方 DRAM 区域选择逻辑已经加入 `my_cpu.sv`。如果目标工程使用真正的外部 RAM 或 AXI/BRAM 控制器，需要把 `ram_sel`、`ram_we`、`cpu_dmem_rdata` 这部分替换成对应接口。

## 5. 流水线结构

### 5.1 IF stage

文件：`rtl/cpu_top/if_stage.sv`

职责：

- 维护 PC。
- 发起取指。
- 处理异常重定向。
- 处理分支预测命中时的预测跳转。
- 打包 `fs_to_ds_bus` 送 ID。

分支预测：

- 16 项简单 BTB。
- 索引宽度 `BP_INDEX_WIDTH = 4`。
- 记录 valid、taken、tag、target。
- JALR 不进入预测表更新。
- EXE 阶段发现预测错误后通过 `br_redirect/br_redirect_target` 冲刷流水。

注意：

- IF 阶段中已有为了时序而保留的一拍寄存逻辑，不要随意删除。

### 5.2 ID stage

文件：`rtl/cpu_top/id_stage.sv`

职责：

- 指令译码。
- 立即数生成。
- 通用寄存器、FPU 寄存器、CSR 读地址输出。
- 写回阶段数据旁路到 ID。
- EXE/MEM 前递选择编码。
- load-use 冒险检测。
- 打包 `ds_to_es_bus`。

主要包：

- `ALU_PACKET`
- `FPU_PACKET`
- `MUL_PACKET`
- `MEM_PACKET`
- `CSR_PACKET`
- `BR_JMP_PACKET`
- `CTRL_PACKET`
- `SRC_PACKET`
- `BITMAN_PACKET`，在 `Z_BITMAIN_ENABLE` 打开时存在

load-use 冒险：

- 用 `prev_load` 记录上一条进入 EXE 的 load/flw。
- 当前指令需要 `rs1/rs2` 且命中 EXE 目的寄存器时暂停 ID。

CSR 写使能语义：

- `csrrw/csrrwi` 恒写 CSR。
- `csrrs/csrrc` 仅当 `rs1 != x0` 写 CSR。
- `csrrsi/csrrci` 仅当 `uimm != 0` 写 CSR。

### 5.3 EXE stage

文件：`rtl/cpu_top/exe_stage.sv`

职责：

- 操作数前递选择。
- ALU 运算。
- M 扩展乘除运算。
- FPU 运算模块调用。
- Z-bitman 运算。
- store 写数据生成。
- 分支条件判断和跳转目标计算。
- 分支预测更新。
- CSR 写数据生成。
- 打包 `es_to_ms_bus`。

分支路径：

- BEQ/BNE/BLT/BGE/BLTU/BGEU 在 EXE 判断。
- JAL/JALR 也在 EXE 统一产生 redirect。
- JALR 目标地址最低位清零。

结果选择优先级：

```text
bitman -> alu -> fpu -> mem address -> mul -> csr -> pc + 4
```

### 5.4 MEM stage

文件：`rtl/cpu_top/mem_stage.sv`

职责：

- load 数据对齐和符号扩展。
- MEM/WB 流水寄存。
- CSR 最终写口输出。
- 地址非对齐异常检测。
- 异常 flush 生成。

异常：

- IAM：跳转目标地址非对齐。
- LAM：load 地址非对齐。
- SAM：store 地址非对齐。
- 异常发生时通过 CSR 模块产生 `exception_flag` 和 `exception_addr`。

### 5.5 WB stage

文件：`rtl/cpu_top/wb_stage.sv`

职责：

- 接收 `ms_to_ws_bus`。
- 根据 `exe_result_sel` 选择 EXE 结果或 MEM load 结果。
- 写回通用寄存器或 FPU 寄存器。
- 输出 debug 写回信息。

## 6. 寄存器和 CSR

### 6.1 通用寄存器

文件：`rtl/cpu_top/regfiles.sv`

- 32 个 32 位整数寄存器。
- `x0` 恒为 0。
- 单写双读。

### 6.2 FPU 寄存器

文件：`rtl/cpu_top/reg_fpu.sv`

- 32 个 32 位 FPU 寄存器。
- 支持第三读端口，供 FMADD/FMSUB/FNMADD/FNMSUB 使用。

### 6.3 CSR

文件：`rtl/cpu_top/regfile_csr.sv`

支持的 CSR：

```text
mstatus  0x300
misa     0x301
mtvec    0x305
mepc     0x341
mcause   0x342
mhartid  0xF14
mie      0x304
mip      0x344
mtval    0x343
mvendorid 0xF11
marchid   0xF12
mimpid    0xF13
mscratch  0x340
cycle     0xC00
instret   0xC02
```

trap entry 行为：

- 写 `mepc`、`mcause`、`mtval`。
- `mstatus.MPIE <= mstatus.MIE`。
- `mstatus.MIE <= 0`。

`mret` 行为：

- `mstatus.MIE <= mstatus.MPIE`。
- `mstatus.MPIE <= 1`。
- 跳转到 `mepc`。

## 7. 已实现指令范围

### 7.1 RV32I

当前基础测试覆盖的 RV32I 指令：

```text
lh lhu sh sb lb lbu sw lw
add addi sub
and andi or ori xor xori
sll srl sra slli srli srai
slt slti sltu sltiu
beq bne blt bge bltu bgeu
jal jalr
lui auipc
```

### 7.2 机器模式/CSR

当前测试覆盖：

```text
csr scall sbreak ma_fetch
```

### 7.3 M 扩展

当前测试覆盖：

```text
mul mulh mulhu mulhsu
div divu rem remu
```

乘法周期由 `MUL_MULTICYCLE_ENABLE` 和 `MUL_CYCLE` 控制。除法使用 `divider.sv`。

### 7.4 Z-bitman 当前实现子集

宏开关：

```systemverilog
`define Z_BITMAIN_ENABLE 1'b1
```

注意：宏名沿用当前工程写法 `Z_BITMAIN_ENABLE`，不是 `Z_BITMAN_ENABLE`。迁移时若要改名，需要同步修改 `defines.svh`、`id_stage.sv`、`exe_stage.sv`。

已实现并加入回归列表：

```text
Zba:
  sh1add sh2add sh3add

Zbb implemented subset:
  andn orn xnor
  min max minu maxu
  sext_b sext_h zext_h
  orc_b rev8

Zbkb:
  brev8 pack packh zip unzip

Zbs:
  bclr bclri bext bexti
  binv binvi bset bseti
```

未实现但 hex 中可能存在的 Z 指令：

```text
Zbb:
  clz ctz cpop rol ror rori

Zbc:
  clmul clmulh clmulr

Zbkx:
  xperm4 xperm8

其它:
  Zfh、A 扩展、C 扩展等并非当前本轮目标
```

## 8. 关键总线位宽

位宽定义集中在 `defines.svh`：

```text
FS_DS_WIDTH  = 32 + 32 + BP_PACKET_WIDTH
DS_ES_WIDTH  = ALU + FPU + MUL + MEM + CSR + CTRL + BR_JMP + SRC + BITMAN
ES_MS_WIDTH  = 32 + 32 + 6 + 5 + 1 + 1 + 2 + 1 + 12 + 32
MS_WS_WIDTH  = 32 + 32 + 5 + 1 + 1
```

`DS_ES_WIDTH` 在启用 Z-bitman 时增加：

```text
BITMAN_OP_WIDTH     = 28
BITMAN_PACKET_WIDTH = 28
CTRL_PACKET_WIDTH   = 32 + 2 + 7 + 5 + 3
```

`CTRL_PACKET` 中新增的 `is_bitman` 位位于 `exe_result_sel` 之后、`is_alu` 之前。ID 打包和 EXE 解包必须保持完全同序。

## 9. 测试和回归

### 9.1 编译

```bat
vlog -sv rtl/cpu_top/*.sv rtl/cpu_top/*.svh test/*.sv
```

### 9.2 全量回归

```bat
run_all.bat
```

当前 `run_all.bat` 默认执行：

- UI
- MI
- UM
- 已实现 Z 子集

### 9.3 只跑基础回归

```bat
run_all.bat base
```

### 9.4 只跑当前 Z 子集

```bat
run_all.bat z
```

### 9.5 只跑某个 Z 子集

```bat
run_all.bat zba
run_all.bat zbb
run_all.bat zbkb
run_all.bat zbs
```

测试结果输出到：

```text
results/ui_*.txt
results/mi_*.txt
results/um_*.txt
results/zba_*.txt
results/zbb_*.txt
results/zbkb_*.txt
results/zbs_*.txt
```

当前已验证状态：

```text
run_all.bat
ALL TESTS PASSED
```

## 10. 迁移注意事项

1. 不要随意删除 IF 阶段的一拍寄存逻辑。该处是为修时序保留的。
2. 如果修改 `DS_ES_WIDTH` 或任何 packet 内容，必须同步修改 ID 打包和 EXE 解包。
3. 如果移除 Z-bitman，需要关闭 `Z_BITMAIN_ENABLE`，同时确认 `CTRL_PACKET_WIDTH` 回到未扩展格式。
4. 若目标工程不用 `my_cpu.sv`，需要自己提供同步取指 RAM 返回时序和数据 RAM 返回时序。
5. 当前 `simple_data_ram` 是组合读、同步写；`my_cpu` 又对 `cpu_dmem_rdata` 打一拍返回给核心。
6. 当前异常主要覆盖 ecall/ebreak/mret、跳转地址非对齐、load/store 地址非对齐。
7. `counter` 外设在仿真包装中是简化实现，Vivado 工程中可替换为正式实现。
8. `run_all.bat` 是 Windows batch，保持 CRLF 换行，避免 `cmd.exe` 解析异常。

## 11. 后续扩展建议

如果在新工作区继续扩展，推荐顺序：

1. 先保持 `cpu_top` 接口不变，完成目标指令的 ID/EXE/MEM/WB 内部实现。
2. 若新增的是单周期 ALU 类指令，可参考 Z-bitman 的接法：ID 译码、增加 packet、EXE 组合计算、写回选择。
3. 若新增的是访存类或原子类指令，需要优先改造数据存储器接口和 MEM 阶段握手机制。
4. 若新增的是多周期运算，参考 `mul.sv`、`divider.sv` 和 `is_multicycle`/stall 机制。
5. 每次新增 packet 位后先跑 `vlog`，再跑 `run_all.bat base`，最后跑对应扩展测试。
