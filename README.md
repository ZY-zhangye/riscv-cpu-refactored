# RISC-V CPU Refactored — Linux RTL 分支

本分支 `dev/linux-rtl` 只做 RTL 设计与仿真验证，目标是让五级顺序 RV32 核及其 SoC 具备运行带 Sv32 的最小 Linux 所需的硬件能力。当前核心包含寄存器化反压、级间 skid buffer、分支预测、栈值缓冲、整数乘除法和部分 Z 扩展；SoC 提供 UART、timer、PLIC 和 MMIO。

上板工程、板级约束、裸机 C 程序、CoreMark、性能基准和实板证据不在本分支，保留在 `dev/linux-bringup`（2026-10-18 HelloZynq / XC7Z020 上板及 CoreMark 结果均以该分支为准）。设计顺序与验收条件见 [Linux 路线](doc/LINUX_ROADMAP.md)；当前 Questa 纯 RTL 阶段的分阶段执行手册（测试清单、完成标志、边界）见 [RTL_QUESTA_PLAN.md](doc/RTL_QUESTA_PLAN.md)。

## 目录

| 路径 | 用途 |
| --- | --- |
| `rtl/cpu_top/` | CPU 流水线、执行单元、寄存器与 CSR |
| `rtl/cpu_top/synth/` | 可综合实现的替换模块；`rv32_divider_hw.sv` 是 32 步迭代除法器，模块名同为 `divider`，与 `rtl/cpu_top/divider.sv` 行为模型二选一编译 |
| `rtl/my_cpu/` | SoC 集成和外设 |
| `ip/rv32m_mul_div/` | 可独立复用的 RV32M RTL IP 与接口说明 |
| `test/` | Questa / Icarus 指令、流水线、总线和外设测试台 |
| `hex/riscv-tests/` | riscv-tests 测试镜像与索引 |
| `scripts/run_board_regression.py` | 隔离工作目录的 Questa 回归（77 项指令 + 定向测试），不改动共享 HEX |
| `doc/` | Linux 路线、验证基线与设计说明 |

构建库、临时日志和波形不进入版本控制；测试需要的 HEX 镜像保留。

## 仿真与回归

QuestaSim 的 `vlib`、`vlog`、`vsim` 需在 PATH 中。推荐使用隔离回归：

```powershell
python scripts/run_board_regression.py --build-dir build/regression
```

也可使用原脚本，在仓库根目录执行：

```powershell
vlib work
.\run_all.bat all
```

`run_all.bat` 支持 `base`、`z`、`zba`、`zbb`、`zbkb`、`zbs` 与 `all`；默认 77 个用例。脚本有结尾暂停，非交互调用可使用 `cmd /c 'echo.|run_all.bat all'`。它会临时覆写 `hex/riscv-tests/rv32-p-riscv.hex`，运行前保存、结束后恢复该文件，避免把测试选择产生的变化提交。

`run_if_sync_btb.ps1` 使用 Icarus Verilog 跑取指定向测试；`run_board_divider.ps1` 使用 Icarus 验证 `rtl/cpu_top/synth/rv32_divider_hw.sv` 及其与乘除单元的集成。定向用例的编译方式见 [验证基线](doc/LINUX_BASELINE.md)。

## 当前验证与设计边界

QuestaSim 2024.1 的基线为 77 项指令回归和 8 项定向测试通过，详情见 [验证记录](doc/LINUX_BASELINE.md)。`hex/riscv-tests/` 还包含尚未实现功能的用例（rv32mi 其余用例、rv32si、rv32ua 及 `-v` 虚拟内存环境），它们是后续阶段的验收目标，不能用文件数量宣称支持完整 ISA。

当前为无 cache 的 M 模式基础核；FPU 是占位实现，退休计数仍是估算。尚不具备非法指令陷入、A 扩展、M/S/U 特权体系与 Sv32。DEBUG_EN 仿真路径通过不等于厂商 IP 或 FPGA 时序通过。

## 后续开发顺序

1. 精确异常、合法性与权限检查、真实退休计数和回归。
2. 支持等待、错误返回及统一地址空间的内存接口。
3. RV32IMA、Zicsr、Zifencei 与内存顺序。
4. M/S/U 特权级、委托、PMP、CLINT 与 SBI 所需平台设备。
5. Sv32、页表遍历、TLB 和页故障。
6. cache、MMIO 属性、指令与页表可见性。
7. AXI 主接口与 Zynq-7020 PS DDR 适配。
8. 设备树、最小内核、initramfs 和用户态 `/init`。

双发、乱序和 FPU 在其他分支独立开展。各阶段的具体设计与验收见 [LINUX_ROADMAP.md](doc/LINUX_ROADMAP.md)。
