# RISC-V CPU Refactored

RV32 RISC-V CPU / SoC 源码开发与验证工程。当前核心为五级顺序流水线，包含寄存器化反压、级间 skid buffer、分支预测、栈值缓冲、整数乘除法和部分 Z 扩展；SoC 提供 UART、timer、PLIC 和 MMIO。

日常开发以 QuestaSim 和根目录 `run_all.bat` 内的指令回归为主。

2026-10-18 已完成 HelloZynq / XC7Z020 上的现有 SoC 裸机上板。交接从 [HANDOFF_20261018.md](doc/HANDOFF_20261018.md) 开始，参数与原始证据见 [CoreMark 实测报告](doc/HELLOZYNQ_COREMARK_RESULTS.md)。本轮 10 MHz 步进中，100 MHz 是最高同时满足所设时序约束并通过 CoreMark 的点；160 MHz 实板 CoreMark 为 343.752372，但 WNS 为 −2.449 ns，仅作超频实验；170 MHz 两次无启动输出。

开发分支为 `dev/linux-bringup`，目标是在 Zynq-7020 PL 中的自研 RISC-V 软核上运行带 Sv32 的最小 Linux，并执行 initramfs 中的 `/init`。ARM PS 可提供 DDR 初始化和镜像加载支持。具体设计顺序与验收条件见 [Linux 路线](doc/LINUX_ROADMAP.md)。

## 目录

| 路径 | 用途 |
| --- | --- |
| `rtl/cpu_top/` | CPU 流水线、执行单元、寄存器与 CSR |
| `rtl/my_cpu/` | SoC 集成和外设 |
| `rtl/board/`、`board/hellozynq/` | HelloZynq 时钟复位、硬件除法适配及引脚约束 |
| `ip/rv32m_mul_div/` | 可独立复用的 RV32M RTL IP 与接口说明 |
| `test/` | Questa 指令、流水线和外设测试台 |
| `hex/` | 测试镜像、索引和格式转换源码 |
| `sim/verilator/` | 单独保存的辅助 Verilator 仿真及专用板级参考 RTL |
| `board_tests/` | CoreMark 源码、平台启动代码及测试镜像 |
| `scripts/` | Windows 固件构建、Vivado 上板、隔离回归和实板采集入口 |
| `riscv_sim_perf_bench/` | 性能测试程序、构建规则和仿真镜像 |
| `doc/` | 开发设计说明、Linux 路线与验证记录 |
| `my_cpu_mmio.h` | 裸机软件 MMIO / CSR 接口参考，使用前核对当前 RTL |

不保留竞赛提交材料、展示资源、发布压缩包和旧工程的超频工具。构建库、临时日志、波形、ELF 与反汇编产物不进入版本控制；测试需要的 HEX/COE 镜像保留。`doc/board_evidence/` 是该次实测特意保留的原始报告、UART 字节及哈希摘要；可重建产物仍位于忽略的 `build/`。

## 主要仿真：Questa 回归

QuestaSim 的 `vlib`、`vlog`、`vsim` 需在 PATH 中。在仓库根目录执行：

```powershell
vlib work
.\run_all.bat all
```

已有 work 库时可省略 `vlib`。`run_all.bat` 支持 `base`、`z`、`zba`、`zbb`、`zbkb`、`zbs` 与 `all`；默认 77 个用例。脚本有结尾暂停，非交互调用可使用 `cmd /c 'echo.|run_all.bat all'`。

原脚本临时覆写 `hex/riscv-tests/rv32-p-riscv.hex`，运行前保存、结束后恢复该文件，避免把测试选择产生的变化提交。结果保存在 `results/`。定向用例与专用除法测试的编译方式见 [验证基线](doc/LINUX_BASELINE.md)。

`run_if_sync_btb.ps1` 使用 Icarus Verilog 跑取指定向测试；`run_perf_bench.ps1` 需要 Questa、WSL 和 RISC-V 裸机工具链，默认工具链目录需按本机安装调整。Verilator 作为辅助仿真单独放在 `sim/verilator/`，不纳入日常 Questa 回归，入口和依赖见其 [README](sim/verilator/README.md)。

## 当前验证与设计边界

QuestaSim 2024.1 的基线为 77 项指令回归和 8 项定向测试通过，详情见 [验证记录](doc/LINUX_BASELINE.md)。测试镜像目录还包含尚未实现扩展的用例，不能用文件数量宣称支持完整 ISA。

2026-10-18 的 SoC 存储器/bridge 修改后已重新运行同样 77+8 项，全部通过，并补充了硬件除法、同步 BRAM/MMIO 链路和真实固件整核仿真。HelloZynq 固件可使用本机 Windows 原生 xPack GCC 15.2.0，无需 WSL；建立独立板级工程的入口是 `scripts/run_board.ps1`，操作前读交接文档。

当前为无 cache 的 M 模式基础核；FPU 是占位实现，退休计数仍需改进。尚不具备已验证的 A 扩展、M/S/U 特权体系与 Sv32。DEBUG_EN 仿真路径通过不等于厂商 IP、FPGA 时序或 Zynq 板级验证通过。

## 后续开发顺序

1. 精确异常、合法性与权限检查、真实退休计数和回归。
2. 支持等待、错误返回及统一地址空间的内存接口。
3. RV32IMA、Zicsr、Zifencei 与内存顺序。
4. M/S/U 特权级、委托、PMP 和 SBI。
5. Sv32、页表遍历、TLB 和页故障。
6. cache、MMIO 属性、指令与页表可见性。
7. Zynq-7020 AXI / PS DDR、时钟与复位适配。
8. 设备树、最小内核、initramfs 和用户态 `/init`。

双发、乱序和 FPU 在 Linux 稳定运行后作为独立性能实验开展。各阶段的具体设计与验收见 [LINUX_ROADMAP.md](doc/LINUX_ROADMAP.md)。
