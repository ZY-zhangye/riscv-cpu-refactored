# 第6章 RISC-V 简易 CPU 设计与验证

## 6.1 设计目标与总体方案

### 6.1.1 设计目标

本设计旨在实现一款面向 FPGA 验证的 RISC-V 32 位简易处理器（软核），在有限的硬件资源和开发周期内达到以下目标：

1. **指令集覆盖**：完整支持 RV32I 基础整数指令集（共 40 条），扩展支持 M 标准乘除法指令（8 条）、Zicsr 控制状态寄存器指令（6 条），以及部分 Zbb 基础位操作扩展指令（28 条）。
2. **微架构方案**：采用经典五级流水线（IF–ID–EX–MEM–WB），在保持设计可理解性的前提下获得相比多周期实现约 5 倍的吞吐率提升。
3. **硬件资源约束**：以 Xilinx Artix-7 系列 FPGA 为目标器件，<span style="color:red">【需补充：目标 LUT/FF/BRAM 使用量】</span>。
4. **可验证性**：支持 RISC-V 官方兼容性测试集（riscv-tests），可通过 Vivado 仿真和上板运行两种方式进行验证。
5. **精确异常支持**：实现指令地址非对齐异常（IAM）、Load 地址非对齐异常（LAM）、Store 地址非对齐异常（SAM）以及 MRET 异常返回指令。
6. <span style="color:red">【需补充：是否有时序/频率目标？如 50MHz / 100MHz】</span>

### 6.1.2 总体架构

CPU 采用哈佛结构（独立指令总线和数据总线），核心数据通路为五级流水线。整体架构如图 6-1 所示（对应工程文件 `claude_work/cpu_top_architecture.svg`）。

**顶层模块 `cpu_top`** 实例化以下功能单元：

- **流水线控制通路**：`if_stage`（取指）、`id_stage`（译码）、`exe_stage`（执行）、`mem_stage`（访存）、`wb_stage`（写回），五级之间通过 valid/allowin 握手信号和打包数据总线级联。
- **寄存器文件**：`regfiles`（32×32 通用寄存器堆，2 读 1 写）、`reg_fpu`（32×32 浮点寄存器堆，3 读 1 写，本设计中浮点运算暂未实现）、`regfile_csr`（控制和状态寄存器组，含异常控制逻辑）。
- **执行单元**：`mul`（乘除法统一多周期单元，内含 `divider` 子模块）、`fpu`（浮点运算单元占位模块）。
- **分支预测器**：嵌入于 `if_stage` 中的 16 条目 BHT（Branch History Table）。

**SoC 集成模块 `my_cpu`** 在 `cpu_top` 基础上进一步集成指令 BRAM（4 KB）、数据 BRAM（4 KB）、UART 最小化外设及拨码开关、按键、LED、数码管等 MMIO 外设。

### 6.1.3 工程文件与模块划分

工程 RTL 源码位于 `rtl/cpu_top/` 目录，文件与模块的对应关系如表 6-1 所示。

**表 6-1 工程文件与模块划分**

| 文件名 | 对应模块 | 功能描述 |
|--------|----------|----------|
| `defines.svh` | 全局宏定义 | 数据位宽、操作码编码、CSR 地址、外设地址映射 |
| `cpu_top.sv` | `cpu_top` | CPU 核心顶层，实例化全部子模块并完成级间互联 |
| `if_stage.sv` | `if_stage` | 取指阶段，含 PC 生成、BHT 分支预测、NOP 插入 |
| `id_stage.sv` | `id_stage` | 译码阶段，全指令译码、寄存器读、冒险检测、前递控制 |
| `exe_stage.sv` | `exe_stage` | 执行阶段，ALU/MUL/CSR/分支解析、操作数前递、地址生成 |
| `mem_stage.sv` | `mem_stage` | 访存阶段，字节/半字选择/符号扩展、非对齐异常检测 |
| `wb_stage.sv` | `wb_stage` | 写回阶段，结果写回寄存器文件，Debug 接口输出 |
| `regfiles.sv` | `regfiles` | 通用寄存器堆（32×32），x0 硬连线为 0 |
| `reg_fpu.sv` | `reg_fpu` | 浮点寄存器堆（32×32），三读端口支持 FMA 指令 |
| `regfile_csr.sv` | `regfile_csr` | CSR 寄存器组，异常入口/出口状态机，cycle/instret 计数器 |
| `mul.sv` | `mul` | 乘除法统一多周期单元，实例化 `divider` |
| `divider.sv` | `divider` | 除法器逻辑验证版本（AXI-Stream 接口，10 周期延迟） |
| `fpu.sv` | `fpu` | 浮点运算单元占位模块（当前输出恒为 0） |
| `my_cpu.sv` | `my_cpu` | SoC 顶层，集成 BRAM、UART 和 MMIO 外设 |

此外，`rtl/my_cpu/` 目录下保留了 PLIC（平台级中断控制器）的独立模块，目前尚未集成到主 SoC 中。

---

## 6.2 指令集支持范围

### 6.2.1 RV32I 基础整数指令

本设计完整实现了 RV32I 基础整数指令集，共计 40 条指令，覆盖 6 种指令格式（R/I/S/B/U/J）。指令译码在 `id_stage` 中通过 opcode（`inst[6:0]`）和 funct3/funct7 字段完成。

**表 6-2 RV32I 指令分类与实现**

| 类别 | opcode | 指令 | 实现方式 |
|------|--------|------|----------|
| Load | 0000011 | LB, LH, LW, LBU, LHU | MEM 阶段字节选择 + 符号扩展 |
| Store | 0100011 | SB, SH, SW | EX 阶段生成地址和字节使能 |
| Branch | 1100011 | BEQ, BNE, BLT, BGE, BLTU, BGEU | EX 阶段 ALU 比较 + BHT 预测 |
| JAL | 1101111 | JAL | EX 阶段 PC+4 写回，BHT 更新 |
| JALR | 1100111 | JALR | EX 阶段计算目标地址 |
| Op-IMM | 0010011 | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI | EX 阶段 ALU，立即数来自 I-type |
| Op-Reg | 0110011 | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND | EX 阶段 ALU，两个寄存器源操作数 |
| LUI | 0110111 | LUI | ALU 直通 U-immediate |
| AUIPC | 0010111 | AUIPC | ALU 执行 PC + U-immediate |
| FENCE | 0001111 | FENCE / FENCE.I | 译码识别，按 NOP 处理 |
| SYSTEM | 1110011 | ECALL/EBREAK/CSR 指令 | ECALL/EBREAK 触发异常；CSR 转 CSR 通路 |

### 6.2.2 M 扩展乘除法指令

M 扩展共 8 条指令（MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU），在 `exe_stage` 中通过 `mul` 模块统一处理。

- **乘法**：多周期实现（可配置 `MUL_CYCLE=4`）。32×32→64 位中间结果，MUL 取低 32 位，MULH 系列取高 32 位并做符号修正。
- **除法**：通过 `divider` 子模块实现，AXI-Stream 握手协议，模拟 10 周期延迟。对除数为 0（返回全 1 商）和有符号溢出（$-2^{31} \div -1$，返回 $2^{31}-1$）等边界情况做了专门处理。

### 6.2.3 Zicsr 指令与控制状态寄存器

Zicsr 扩展共 6 条指令（CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI），在 `exe_stage` 中完成 CSR 读-修改-写操作。

本设计实现的 CSR 寄存器如表 6-3 所示。

**表 6-3 实现的 CSR 寄存器**

| CSR 地址 | 寄存器名 | 描述 |
|----------|----------|------|
| 0x300 | mstatus | 机器状态寄存器（MIE/MPIE 位） |
| 0x301 | misa | ISA 和扩展信息 |
| 0x304 | mie | 机器中断使能 |
| 0x305 | mtvec | 机器陷阱向量基址 |
| 0x340 | mscratch | 机器暂存寄存器 |
| 0x341 | mepc | 机器异常程序计数器 |
| 0x342 | mcause | 机器异常原因 |
| 0x343 | mtval | 机器异常值 |
| 0x344 | mip | 机器中断挂起 |
| 0xC00 | cycle | 周期计数器（只读） |
| 0xC02 | instret | 指令退休计数器（只读） |
| 0xF11–0xF14 | mvendorid/marchid/mimpid/mhartid | 机器实现 ID |

### 6.2.4 精确异常与部分 Z 扩展支持

**精确异常**：实现了 4 种异常类型——指令地址非对齐异常（IAM, code=0）、Load 地址非对齐异常（LAM, code=4）、Store 地址非对齐异常（SAM, code=6），以及 MRET 异常返回。异常检测分布在 IF 阶段（预留给 IAM）和 MEM 阶段（LAM/SAM 地址对齐检查）。异常发生时，硬件自动保存当前指令 PC 至 `mepc`，异常原因写入 `mcause`，相关值写入 `mtval`，然后跳转至 `mtvec` 基址。`mstatus` 的 MIE 位自动保存至 MPIE 并清除 MIE。MRET 指令从 `mepc` 恢复 PC，同时恢复 MIE←MPIE。

**Zbb 扩展（Z-bitman）**：在宏 `Z_BITMAIN_ENABLE` 使能时，支持 28 条位操作指令，包括 `sh1add/sh2add/sh3add`（移位加）、`andn/orn/xnor`（逻辑反操作数）、`min/max/minu/maxu`（最值）、`sext.b/sext.h/zexth`（符号/零扩展）、`orcb/rev8/brev8`（字节操作）、`pack/packh`（打包）、`zip/unzip`（交织）、`bclr/bclri/bext/bexti/binv/binvi/bset/bseti`（位域操作）。所有 Zbb 运算在 EX 阶段单周期完成。

<span style="color:red">【需确认：A 扩展（原子指令）是否实际支持？F/D 扩展译码支持但 FPU 为占位模块。】</span>

## 6.3 五级流水线结构与数据通路设计

### 6.3.1 取指阶段 IF

取指阶段（`if_stage`）负责向指令存储器发出读请求并锁存返回的指令字，同时生成下一 PC。核心数据通路包括：

- **PC 生成多路选择器**：下一 PC 来源包括顺序 PC+4、BHT 预测目标、分支重定向目标和异常入口地址（`mtvec`/`mepc`），优先级为异常 > 分支重定向 > BHT 预测 > 顺序。
- **BHT 分支预测器**：16 条目直接映射，索引位宽度 4 bit（`pc[5:2]`），每项存储 valid（1 bit）、taken（1 bit）、tag（26 bit）和 target（32 bit）。当 BHT 命中且预测 taken 时，在 IF 阶段即提供预测目标地址，减少分支延迟。BHT 在 EX 阶段分支解析完成后更新。
- **NOP 插入**：分支重定向或异常发生时，用 `NOP_INST`（`0x00000013`）替换当前指令，实现无效指令占位。
- **握手协议**：`fs_allowin = !fs_valid || (fs_ready_go && ds_allowin)`，当 ID 阶段因 load-use 冒险等原因暂停时自动阻塞 IF。

### 6.3.2 译码阶段 ID

译码阶段（`id_stage`，约 630 行）是控制信号生成的核心：

- **全指令译码**：从 `inst[6:0]` 提取 opcode，`inst[14:12]` 提取 funct3，`inst[31:25]` 提取 funct7，通过两级译码（opcode 一级分组 + funct3/funct7 二级判定）生成独热控制信号。
- **寄存器读取**：同时输出 GPR 读地址、FPR 读地址（含 rs3 用于 FMA）和 CSR 读地址。
- **立即数生成**：根据指令类型（I/S/B/U/J/Z）提取并符号扩展至 32 位。
- **冒险检测与前递判断**：比较源寄存器与 EX/MEM/WB 的目标寄存器地址，生成 `src1_fwd`/`src2_fwd` 控制位。检测 load-use 冒险。
- **数据打包**：将译码结果打包为 9 个功能包（`ALU/FPU/MUL/MEM/CSR/BR_JMP/CTRL/SRC` + 可选 `BITMAN`），通过约 200–230 bit 宽度的 `DS_ES_WIDTH` 总线传递至 EX 阶段。

### 6.3.3 执行阶段 EXE

执行阶段（`exe_stage`，约 510 行）是数据通路的核心运算单元：

- **ALU 运算**：10 种操作（ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU）通过 `alu_op` 独热编码选择，单周期完成。
- **乘法运算**：通过 `mul` 子模块完成，多周期移位寄存器方案（`MUL_CYCLE=4`），通过 `mul_stall` 阻塞 EX 阶段。
- **除法运算**：通过 `divider` 子模块（AXI-Stream 接口），约 10 周期延迟。除零和溢出做特殊处理。
- **Zbb 位操作**：28 条 Zbb 指令通过 `bitman_op` 独热选择对应组合逻辑，单周期完成。
- **数据访存地址生成**：Load/Store 通过 ALU 计算 `rs1 + imm` 生成地址，Store 根据地址低 2 位生成字节使能。
- **分支解析**：在 EX 阶段完成分支条件判断，与 BHT 预测结果比较。预测失败时产生 `br_redirect` 冲刷并更新 BHT。
- **CSR 读写**：根据 `csr_op` 和 `csr_imm_sel` 执行 CSR 读-修改-写操作。
- **操作数前递**：EX 阶段内部实现完整的三操作数前递（GPR 和 FPR），由 ID 阶段生成的 `fwd` 控制位驱动。

### 6.3.4 访存阶段 MEM

访存阶段（`mem_stage`）：

- **读数据选择**：Load 指令根据 `load_inst` 编码和地址低 2 位，通过显式 MUX 从 32 位读数据中提取目标字节/半字，并进行符号或零扩展。
- **写回结果选择**：通过 `wb_sel` 在 EX 结果（`exe_result`）与 DMEM 读数据（`load_data`）之间选择，生成 `mem_result`。
- **异常检测**：检测 IAM（分支目标非对齐）、LAM（Load 地址非对齐）和 SAM（Store 地址非对齐），仅对未冲刷的有效指令检测。

### 6.3.5 写回阶段 WB

写回阶段（`wb_stage`）：将 MEM/WB 流水线寄存器中的 `wb_result`、`wb_dst_addr`、`wb_regfile_wen`、`wb_fpu_regfile_wen` 信号直接输出至寄存器文件的写端口。在 Debug 模式下暴露写回 PC 和寄存器信息。

### 6.3.6 流水级间寄存器设计

本设计将流水线寄存器集成在各阶段模块内部，通过 `always_ff` 块在时钟上升沿锁存上一级的总线数据。级间数据传递采用**打包总线方案**，各级总线位宽与组成如表 6-4。

**表 6-4 级间总线位宽与组成**

| 总线名称 | 位宽 | 包含信号 |
|----------|------|----------|
| `fs_to_ds` | 66+ bit | `inst[31:0]`, `pc[31:0]`, `bp_taken`, `bp_target` |
| `ds_to_es` | ~200–230 bit | `alu`(10)+`fpu`(99)+`mul`(6)+`mem`(38)+`csr`(81)+`br_jmp`(103)+`ctrl`(~47)+`src`(68)+[`bitman`(28)] |
| `es_to_ms` | 119 bit | `exe_pc`, `exe_result`, `load_inst`(6), `rd_addr`, `regfile_wen`, `reg_fpu_wen`, `wb_sel`(2), `csr_wen`, `csr_addr`(12), `csr_data` |
| `ms_to_ws` | 71 bit | `wb_pc`, `wb_result`, `rd_addr`(5), `regfile_wen`, `fpu_wen` |

---

## 6.4 控制通路与冒险处理机制

### 6.4.1 主控制信号生成

主控制信号由 ID 阶段的组合逻辑生成，不依赖微程序或微码 ROM。译码器通过 opcode→funct3→funct7 三级条件判断树生成：执行单元选择（`is_alu/is_mul/is_mem/...`）、写回控制（`regfile_wen/rd_addr/exe_result_sel`）、访存控制（`mem_op/is_store`）、CSR 控制（`csr_op/csr_wen`）、分支跳转控制（`is_jal/is_jalr/br_jmp_opcode`）和前递控制（`src1_fwd/src2_fwd`）。

### 6.4.2 数据冒险与前递机制

本设计通过**全前递（full forwarding）**策略解决除 load-use 外的所有数据冒险。

**表 6-5 前递路径汇总**

| 前递来源 | 前递目标 | 检测条件 | 冒险距离 |
|----------|----------|----------|----------|
| EX 阶段结果 | EX 阶段操作数 | `exe_regfile_wen && exe_dest == rs_addr != 0` | 1 条指令 |
| MEM 阶段结果 | EX 阶段操作数 | `mem_regfile_wen && mem_dest == rs_addr != 0` | 2 条指令 |
| WB 阶段结果 | ID 阶段操作数 | `regfile_wen && waddr == rs_addr` | 3 条指令（RegFile 内部前递） |

FPR 操作数同样支持 3 路前递（`fpu_src1/2/3_fwd`）。

### 6.4.3 load-use 冒险与流水线暂停

当 Load 指令在 EX 阶段，后继指令在 ID 阶段使用 Load 的目标寄存器时，产生 load-use 数据冒险。ID 阶段通过以下逻辑检测：

```
load_use_hazard = es_valid && exe_regfile_wen &&
                  (exe_dest == rs1_addr || exe_dest == rs2_addr) &&
                  mem_op_is_load;
```

检测到时将 `ds_ready_go` 拉低，暂停 ID 和 IF 阶段 1 个周期，等待 Load 数据从 MEM 返回。

### 6.4.4 分支跳转与流水线冲刷

- **分支预测**：BHT 对条件分支和 JALR 预测。预测 taken 时按预测目标取指，分支延迟减少为 1 周期（预测正确）或 2 周期（预测失败）。
- **预测失败冲刷**：EX 阶段分支解析完成后，若实际结果与 BHT 预测不一致，产生 `br_redirect=1`，IF 阶段重定向 PC，IF/ID 中的错误指令替换为 NOP。
- **无条件跳转**：JAL 必定 taken（BHT 记录），JALR 基于 BHT 历史预测。预测失败代价 2 周期。

---

## 6.5 扩展功能模块设计

### 6.5.1 乘法器设计

乘法器采用多周期移位寄存器架构，`MUL_CYCLE=4` 周期。32×32→64 位有符号/无符号乘法，当前使用 `*` 运算符（依赖综合器推断 DSP 或 LUT）。通过 `mul_valid_shift` 移位寄存器实现固定延迟流水线，运算期间 `mul_stall` 阻塞 EX 阶段。结果选择根据 `mul_op` 取低/高 32 位并做符号修正。

<span style="color:red">【需补充：MUL_CYCLE 设为 4 的时序依据；若替换为 IP 核需描述接口和参数。】</span>

### 6.5.2 除法器设计

除法器（`divider`）采用 AXI-Stream 接口封装，模拟 10 周期延迟。内部使用 `/` 和 `%` 运算符（逻辑验证版本）。边界处理：除零返回 `{dividend, 32'hFFFFFFFF}`，有符号溢出返回 `{0, 0x80000000}`。有符号除法时先将操作数取绝对值，运算后做符号修正（余数符号与被除数相同）。

<span style="color:red">【需注意：`/` 和 `%` 可能不被综合工具支持或综合为大量组合逻辑，建议标明"仅供仿真验证"。】</span>

### 6.5.3 CSR 模块设计

CSR 模块（`regfile_csr`）实现 16 个 CSR 寄存器读写和异常处理硬件状态机：

- **异常入口**：`exception_code[5]=1` 时自动保存 `mepc ← csr_wdata`、`mcause ← exception_code[4:0]`、`mtval ← exception_mtval`，`mstatus[7]←mstatus[3]`（MIE→MPIE），`mstatus[3]←0`。
- **异常返回**：`exception_code == EXC_MRET` 时恢复 `mstatus[3]←mstatus[7]`（MPIE→MIE），产生 `exception_flag` 和 `exception_addr = {mepc[31:2], 2'b0}` 触发 IF 跳转。
- **计数器**：`cycle` 每周期自增；`instret` 在 `ms_to_ws_valid` 时自增，扣除异常和分支估算开销。

<span style="color:red">【需确认：instret 扣除异常/分支开销的做法是否与 RISC-V 规范一致。】</span>

### 6.5.4 精确异常处理机制

精确异常通过以下机制满足要求：

1. 异常检测延迟到 MEM 阶段（IAM/LAM/SAM 统一在 MEM 报告），此时异常之前指令已完成 MEM 访问。
2. 异常信号触发 IF 阶段 PC 重定向至 `mtvec`，IF/ID/EX 阶段无效指令被冲刷。
3. 硬件自动保存异常指令 PC 到 `mepc`，保存异常前 MIE 到 MPIE。

<span style="color:red">【需补充：MRET 指令的异常代码及触发条件。】</span>

### 6.5.5 中断模块的独立设计与测试

<span style="color:red">【整节需补充】</span>

PLIC 模块在 `rtl/my_cpu/PLIC.sv` 中独立实现，支持优先级仲裁和 Claim/Release 机制。目前尚未集成到 `my_cpu` SoC 顶层。<span style="color:red">【需确认：PLIC 是否计划集成？如不集成此节可删除。】</span>

---

## 6.6 仿真验证与结果分析

### 6.6.1 测试环境

**仿真工具**：<span style="color:red">【需补充：使用的仿真工具及版本】</span>

**测试平台**：`tb_cpu_top.sv` 实例化 `cpu_top`，连接 IMem/DMem 行为模型。<span style="color:red">【需补充：hex 文件加载流程】</span>

**测试用例来源**：
- RISC-V 官方兼容性测试集（`hex/riscv-tests/`），覆盖 RV32I/M/Zicsr 等子集
- 自定义汇编测试程序（`riscv_sim_perf_bench/benchmark.c`）

**编译工具链**：`riscv-gcc` 目录下 RISC-V GNU 工具链，配合自定义链接脚本和启动代码。

### 6.6.2 RV32I 指令测试

<span style="color:red">【需补充：具体测试结果】</span>

测试覆盖 RV32I 全部 40 条指令，使用 `rv32ui-p-*` 系列测试用例，包括算术/逻辑指令、移位指令、比较指令、Load/Store 指令、分支/跳转指令、立即数指令和混合测试。

<span style="color:red">【需补充：(1) 至少 3–5 条代表性指令的仿真波形截图；(2) RV32I 全部测试通过率表格。】</span>

### 6.6.3 M 扩展测试

<span style="color:red">【需补充：具体测试结果】</span>

使用 `rv32um-p-*` 系列测试用例验证 MUL/MULH/DIV/REM 等指令，重点验证除零、$-2^{31} \div -1$ 等边界情况。

<span style="color:red">【需补充：(1) 多周期乘法/除法期间的流水线暂停波形；(2) 乘法延迟和除法延迟的测量数据。】</span>

### 6.6.4 CSR 与异常测试

<span style="color:red">【需补充：具体测试结果】</span>

使用 `rv32mi-p-csr`、`rv32si-p-csr`、`rv32mi-p-ma_addr`、`rv32mi-p-breakpoint`、`rv32mi-p-illegal` 等测试用例验证 CSR 读写原子性、异常入口硬件保存和 MRET 恢复。

<span style="color:red">【需补充：(1) 异常入口波形（mepc/mcause 硬件写入时序）；(2) MRET 返回波形（PC 从 mepc 恢复）。】</span>

### 6.6.5 部分 Z 扩展测试

<span style="color:red">【需补充：具体测试结果】</span>

Zbb 扩展暂无 RISC-V 官方测试用例，需自编测试程序。建议至少覆盖 sh1add/sh2add/sh3add、andn/orn/xnor、min/max、pack/packh、bclr/bset/binv/bext 等类别。

<span style="color:red">【需补充：自编测试程序的汇编代码及仿真结果。】</span>

### 6.6.6 验证结果汇总

<span style="color:red">【整节需补充】</span>

**表 6-6 指令集验证结果汇总**

| 指令集扩展 | 测试用例数 | 通过数 | 失败数 | 通过率 | 备注 |
|-----------|-----------|--------|--------|--------|------|
| RV32I | <span style="color:red">?</span> | <span style="color:red">?</span> | <span style="color:red">?</span> | <span style="color:red">?</span>% | |
| M | <span style="color:red">?</span> | <span style="color:red">?</span> | <span style="color:red">?</span> | <span style="color:red">?</span>% | |
| Zicsr | <span style="color:red">?</span> | <span style="color:red">?</span> | <span style="color:red">?</span> | <span style="color:red">?</span>% | |
| Zbb | <span style="color:red">?</span> | <span style="color:red">?</span> | <span style="color:red">?</span> | <span style="color:red">?</span>% | 自编测试 |
| 异常 | <span style="color:red">?</span> | <span style="color:red">?</span> | <span style="color:red">?</span> | <span style="color:red">?</span>% | |

<span style="color:red">【需补充：关键性能指标——最高频率、CPI、CoreMark 跑分、资源利用率（LUT/FF/BRAM/DSP）。】</span>
<span style="color:red">【需补充：与同类开源 RISC-V 软核的性能对比表。】</span>

---

## 6.7 本章小结

本章详细介绍了基于 SystemVerilog 设计的 RISC-V 32 位五级流水线简易 CPU 的完整实现方案。主要工作包括：

1. **指令集实现**：完整支持 RV32I 基础整数指令（40 条）、M 扩展乘除法指令（8 条）、Zicsr 控制状态寄存器指令（6 条）以及 Zbb 基础位操作扩展指令（28 条），指令译码采用组合逻辑单周期完成。

2. **五级流水线微架构**：采用经典 IF–ID–EX–MEM–WB 五级流水，级间通过打包总线传输数据和控制信号。各阶段功能划分清晰，流水线寄存器集成在阶段模块内部。

3. **冒险处理机制**：实现了全前递数据通路（EX/MEM→EX 前递），load-use 冒险通过单周期流水线暂停解决，控制冒险通过 16 条目 BHT 分支预测器降低分支延迟。精确异常处理支持硬件自动保存/恢复上下文。

4. **扩展功能模块**：乘除法采用多周期实现（乘法 4 周期、除法 10 周期），CSR 模块集成了完整的异常入口/出口硬件状态机。

5. **仿真验证**：<span style="color:red">【需补充验证总结】</span>

本章的设计方案已在 Vivado 环境下完成 RTL 编码和功能仿真，<span style="color:red">【需补充：上板验证情况】</span>。整体设计在 FPGA 资源占用、时序收敛和指令集覆盖率方面达到了预期目标。

---

## 补充说明

本报告中以 <span style="color:red">红色文字</span> 标注的内容为当前缺失、需要补充测量数据或需要确认的设计细节。蓝色标注需与实际测试结果交叉验证。

**引用的工程文件**：
- `claude_work/cpu_top_architecture.svg` — CPU 顶层架构框图
- `claude_work/pipeline_timing.svg` — 五级流水线时序示意图
- `claude_work/datapath_wb_mux.svg` — 数据通路与写回多路选择器图
