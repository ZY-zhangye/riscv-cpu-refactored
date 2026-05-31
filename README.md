# RISC-V CPU Refactored

这是一个基于 SystemVerilog 的 RV32 单发射顺序流水 CPU 工程。当前核心位于 `rtl/cpu_top`，外层 `rtl/my_cpu` 提供片上 RAM、桥接、UART、PLIC 和简化外设包装，主要用于 QuestaSim/ModelSim 仿真和后续 FPGA 工程迁移。

## 主要特性

- RV32I 基础整数指令。
- M 扩展乘除法指令，乘法支持多周期配置，除法为多周期实现。
- 机器模式 CSR、异常、`ecall`、`ebreak`、`mret`。
- 简单分支预测和 EXE 阶段重定向。
- 部分单精度 FPU 数据通路。
- 已实现 Z-bitman 子集：Zba、Zbb 子集、Zbkb、Zbs。
- Icache：阻塞式指令 Cache，命中时保持“本周期发地址、下周期收数据并发下一地址”的取指节奏。
- Dcache：4KB 直接映射数据 Cache，16B cache line，load hit 一拍返回，miss refill 后再返回，store 采用 write-through，MMIO/PLIC 走 bypass。

## 目录结构

```text
.
|-- rtl/
|   |-- cpu_top/        # CPU 核心流水线、Cache、寄存器堆、CSR、运算单元
|   `-- my_cpu/         # SoC 包装、bridge、UART、PLIC、timer 等外设
|-- test/               # 仿真 testbench
|-- hex/riscv-tests/    # RISC-V 指令测试 hex
|-- doc/                # 设计说明和扩展指令资料
|-- riscv_sim_perf_bench/
|-- run_all.bat         # 一键回归脚本
|-- clean.bat           # 清理 QuestaSim 中间文件
`-- README.md
```

## 核心模块

`rtl/cpu_top/cpu_top.sv` 是 CPU 核心顶层，主要实例化：

- `if_stage.sv`：PC、取指、分支预测、异常重定向。
- `icache.sv`：指令 Cache。
- `id_stage.sv`：译码、立即数、寄存器读、前递选择、冒险检测。
- `exe_stage.sv`：ALU、乘除法、FPU、Z-bitman、访存地址、分支判断。
- `mem_stage.sv`：Dcache 请求/响应、load 数据对齐、异常检查、CSR 写入口。
- `dcache.sv`：数据 Cache。
- `wb_stage.sv`：写回。
- `regfiles.sv`、`reg_fpu.sv`、`regfile_csr.sv`：寄存器与 CSR。

`rtl/my_cpu/my_cpu.sv` 是仿真和板级包装顶层，包含指令 RAM、数据 RAM、bridge、IO、PLIC 等模块。

## Cache 时序

### Icache

Icache 的目标是把 CPU 前端和较大的 IROM 隔离开，降低长布线压力。命中时序为：

```text
Cycle N    IF 发出 PC
Cycle N+1  Icache 返回指令，同时 IF 可发出下一条 PC
```

miss 不做同周期返回，必须 refill 后再向 IF 返回。

### Dcache

Dcache 当前参数：

```systemverilog
`define DCACHE_SIZE      4096
`define DCACHE_LINE_SIZE 16
```

组织方式：

- 直接映射。
- 4KB / 16B = 256 行。
- 每行 4 个 32-bit word。
- valid + tag + data。
- load miss 时连续读取 4 个 word refill。
- store 为 write-through，命中时同步更新 cache，同时写后端。
- store miss 采用 no-write-allocate。
- MMIO/PLIC 地址不进入 cache，走注册化 bypass。

## 已验证指令范围

基础整数测试：

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

机器模式和 CSR 测试：

```text
csr scall sbreak ma_fetch
```

M 扩展测试：

```text
mul mulh mulhu mulhsu
div divu rem remu
```

Z-bitman 已实现回归子集：

```text
Zba:  sh1add sh2add sh3add
Zbb:  andn orn xnor min max minu maxu sext_b sext_h zext_h orc_b rev8
Zbkb: brev8 pack packh zip unzip
Zbs:  bclr bclri bext bexti binv binvi bset bseti
```

## 仿真环境

工程当前使用 QuestaSim/ModelSim 命令行工具：

- `vlog`
- `vsim`

Windows 下可直接使用仓库根目录的 batch 脚本。

单独编译：

```bat
vlog -sv +incdir+rtl/cpu_top +incdir+rtl/my_cpu rtl/cpu_top/*.sv rtl/cpu_top/*.svh rtl/my_cpu/*.svh rtl/my_cpu/*.sv test/*.sv
```

全量回归：

```bat
run_all.bat all
```

只跑基础指令、M 扩展和机器模式测试：

```bat
run_all.bat base
```

只跑 Z 扩展子集：

```bat
run_all.bat z
```

只跑某个 Z 子集：

```bat
run_all.bat zba
run_all.bat zbb
run_all.bat zbkb
run_all.bat zbs
```

回归结果会写入 `results/`。`run_all.bat` 会把对应测试 hex 复制到 `hex/riscv-tests/rv32-p-riscv.hex` 后再启动仿真。

## 清理中间文件

```bat
clean.bat
```

该脚本会清理 QuestaSim 生成的 `work/`、`transcript`、`vsim.wlf`、`results/*.txt` 等文件。

## 常用开发流程

1. 修改 RTL。
2. 运行 `vlog` 做语法编译。
3. 先跑相关单项测试。
4. 跑 `run_all.bat all` 做完整回归。
5. 确认通过后运行 `clean.bat` 清理中间文件。
6. 提交 RTL 或文档改动。

## 注意事项

- 修改 `defines.svh` 中任意流水线总线宽度后，必须同步检查对应 stage 的打包和解包顺序。
- `id_stage.sv`、`exe_stage.sv`、`mem_stage.sv` 之间的前递和 ready/valid 时序关系比较紧，新增访存类功能时要优先验证 load-use 场景。
- Icache 和 Dcache 都刻意避免 miss 同周期返回，用于隔离后端存储器路径。
- MMIO/PLIC 不应进入 Dcache，否则可能破坏外设访问顺序和副作用语义。
- `run_all.bat` 会覆盖 `hex/riscv-tests/rv32-p-riscv.hex`，提交前需要确认该文件是否为预期内容。

## 当前验证状态

最近一次完整回归结果：

```text
run_all.bat all
ALL TESTS PASSED!
```
