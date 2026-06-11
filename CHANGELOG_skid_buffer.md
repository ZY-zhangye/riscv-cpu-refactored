# Skid Buffer 架构改造说明

## 1. 改造动机
在原有的五级流水线架构中，级间握手信号（特别是反向传播的 `allowin` 信号）形成了贯穿全流水线的长组合逻辑路径。例如：`wb_allowin` 影响 `ms_allowin`，`ms_allowin` 进而影响 `es_allowin`，最终一直传递到 `id_allowin`。这种超长的组合逻辑极大地限制了 CPU 的工作频率。

本次改造的核心目标是在每一级的流水线寄存器中额外引入一级寄存器（Skid Buffer），通过将反向传播的握手信号（`ready_in`/`allowin`）进行打拍缓冲，从根本上截断这条长组合逻辑路径。

## 2. 核心模块引入 (skid_buffer.sv)
在 `rtl/cpu_top/` 下引入了参数化的 `skid_buffer.sv` 模块。
该模块包含一个主寄存器和一个后备寄存器（Skid Register），具有三种工作状态：
- `0`: 空状态 (Empty)
- `1`: 正常数据状态 (Half-Full)
- `2`: 数据挤压状态 (Full/Skid)

Skid Buffer 完美地解耦了上游的 `valid_in` 和下游的 `ready_in`，使得本级可以提前向上游发出 `ready_out` 信号，而无需等待下游的反馈，成功实现了时序上的隔离。

## 3. 流水线级间改造
对流水线的四处级间总线接口进行了替换：
- **IF -> ID (`fs_to_ds_bus`)**: 在 `id_stage.sv` 中，移除了原先的 `fs_to_ds_bus_r` 和相关判断逻辑，实例化 `id_skid_buf`，将 `ds_flush` 作为清空信号接入。
- **ID -> EXE (`ds_to_es_bus`)**: 在 `exe_stage.sv` 中，用 `es_skid_buf` 替换 `ds_to_es_bus_r`，由原本的 `exception_flag` 和内部刷新逻辑作为清空信号。
- **EXE -> MEM (`es_to_ms_bus`)**: 在 `mem_stage.sv` 中，引入 `ms_skid_buf`，移除了原有的跨级打拍冲刷信号 `es_flush_r`。
- **MEM -> WB (`ms_to_ws_bus`)**: 在 `wb_stage.sv` 中，引入 `ws_skid_buf` 替换了原本直接挂载的接口。

## 4. JALR 指令缺陷修复
在全面替换 Skid Buffer 之后，运行 Base 测试时发现 `rv32ui-p-jalr` 指令失败。
深度调试后确认：
- 在原有的耦合流水线架构中，由于 `mem_stage.sv` 通过跨级打拍维护了一个延迟的 `ms_flush` 信号，从而能自行过滤掉流水线刷新时传来的无效指令。
- 改造为纯数据驱动的 Skid Buffer 后，`mem_stage` 转而使用数据包的 `valid` 来驱动执行 (`ms_flush = !ms_valid`)，但这暴露了原有代码中 `exe_stage.sv` 向下打包 `es_to_ms_bus` 时的隐蔽缺陷。
- `exe_stage.sv` 在向 `mem_stage` 传递寄存器写使能信号时，错误地打包了原始的 `regfile_wen`，而非经过 flush 信号掩码的 `exe_regfile_wen`。这导致本应因分支预测错误被废弃的指令，进入 `mem_stage` 后依然非法写入了寄存器，破坏了程序状态。
- **修复方法**：将 `exe_stage.sv` 中的总线打包代码更正为 `exe_regfile_wen` 和 `exe_reg_fpu_wen`，确保传输到下游的数据已完全反映了冲刷状态。

## 5. 测试与验证
修复后，再次运行了所有的 RISC-V 基础回归测试：
- `rv32ui-p-*` (含所有的基础算术、逻辑、分支跳转等，共约 40 个用例)
- `rv32mi-p-*` (CSR 和异常/中断相关)
- `rv32um-p-*` (乘法与除法器相关)
所有测试均返回 `[PASSED]`，全线通过。重构后的架构既满足了功能正确性，也达成了时序优化（组合逻辑打断）的目标。
