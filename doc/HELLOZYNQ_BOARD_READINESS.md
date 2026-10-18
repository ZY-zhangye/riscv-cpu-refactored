# HelloZynq / XC7Z020：现有 RV32 SoC 上板资料核对

核对日期：2026-10-18（Asia/Singapore）。范围仅为现有五级流水 RV32 SoC 的首次裸机上板；不增加 ISA、Linux、DDR 或 RISC-V 调试模块。本轮只增加本文档，未修改 RTL/C、未综合实现、未下载配置或复位板卡。

## 1. 资料完整性结论

首版采用 **PL 软核、板载 50 MHz、片内 ROM/BRAM、现有 UART/Timer/PLIC、两颗 LED、JTAG 配置**，所需原理图、引脚、电平、工具和可恢复基线资料已具备。首版不依赖 PS 初始化、DDR、SD 或 QSPI。

两个实物身份字段仍未确认：**完整速度档/温度等级、PCB 修订版本**。用户于本轮回复暂时无法确认；不再将这两项重复列为需立即提供的前置条件。现有公共接口已通过实际 UART 测试，可继续做源码适配准备；不能据此声明实物为 `-2/I` 或某一 PCB 版本。

原厂工程与上一轮基线采用 `xc7z020clg484-2`。用户于 2026-10-18 补充，配套教程也是这个型号，因此将其列为教程支持的候选目标型号；用户表述为“可能”，尚不视为实物速度档已确认。后续可先使用 `xc7z020clg484-1` 进行较保守的时序评估，并显式保留实物等级未知；这不是对实物料号、工作温度范围或最终时序签核的确认。

## 2. 已确认的板级接口

方向均从 FPGA 顶层看；球位不是扩展排针序号。

| 功能 | 球位 | 电平/约定 | 证据范围 |
| --- | --- | --- | --- |
| PL 输入时钟 | M19 | 50 MHz，20 ns，LVCMOS33 | 原理图、干净 XDC、纯 PL UART 实测 |
| PL 复位按键 | J20 | 低有效，上拉，按下接地，LVCMOS33 | 原理图/XDC；按键中途复位仍待验收 |
| UART TX | L17 | 输出，空闲高，LVCMOS33 | FPGA → CH340E RX，板上收发通过 |
| UART RX | M17 | 输入，空闲高，LVCMOS33 | CH340E TX → FPGA，板上收发通过 |
| LED[0] | P20 | 高电平点亮，LVCMOS33 | 原理图/XDC；肉眼状态仍待验收 |
| LED[1] | P21 | 高电平点亮，LVCMOS33 | 同上 |
| 备用按键 | K21 | 低有效，首版不使用 | 原理图确认 |

这些接口属于 PL Bank34；不能因原理图网名为 `PS_UART_TX/RX` 就误接到 PS MIO。板上的 PS RST/SW4 接 PS POR，不能替代 J20 的 PL 复位。

**新增核对的厂商勘误**：`F:/BaiduNetdiskDownload/zynq/05_文档教程/10_硬件原理图/readme.md` 明确说明 V1.0 的 KEY1/KEY2 丝印交换，且两排扩展排针丝印方向/位置有误，V2.0 修正。应按 J20 球位选择复位；PCB 版本未确认前，不按扩展排针丝印直接增加接线。原文件给出了 V1.0 补充丝印图。

复位封装需要配置后可靠拉住 CPU，再同步释放；UART RX 现有 RTL 已有同步链。新 SoC 应按自己的同步器和时钟域建立约束，不整套复制 UART 基线的 false-path。

## 3. 板卡交接第 5 节：本工程已经明确的信息

| 字段 | 已确认内容 | 实施时需落实 |
| --- | --- | --- |
| 逻辑顶层 | `rtl/my_cpu/my_cpu.sv` 的 `my_cpu`，包含 `cpu_top`、bridge、IO、PLIC | 新建独立 HelloZynq 板级 wrapper 和构建入口 |
| ISA / ABI | RV32，小端，ILP32；首个自检用 `rv32i_zicsr`，M 扩展验证用 `rv32im_zicsr` | 不使用 A/C/F/D 或未完整实现的位操作扩展 |
| 编译器 | Windows 原生 xPack GCC 15.2.0-1，`F:/Tools/Apps/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe` | 编译、链接均显式传 `-march`、`-mabi`；不依赖工具默认 ISA |
| 复位入口 | 正常 `PC_START=0x80000000`；`PERF_BENCH` 才是 0 | 首版采用正常入口，不直接使用链接在 0 的仿真性能镜像 |
| 指令区 | `board_tests/platform/linker.ld`：`0x80000000`，16 KiB | 同步一拍 ROM/BRAM，指令镜像实际进入 bitstream |
| 数据区/栈 | `0x80100000..0x8013FFFF`，256 KiB；栈顶 `0x80140000` | RAM 实际容量必须和 linker 一致 |
| CPU 访存 | 分离取指/数据，自定义 SRAM 风格接口；MEM 无等待/错误响应 | 保持现有固定一拍响应，不为本次上板引入总线功能扩展 |
| MMIO | UART=`0x80010000`，Timer=`0x80020000`，LED=`0x80030000`；PLIC 寄存器页位于 `0x80300000..0x80305FFF` | 使用 `board_tests/platform/my_cpu_mmio.h`，不套 PS 地址或旧虚拟面板地址 |
| 中断 | Timer/UART RX/UART TX 的 PLIC ID 为 1/2/3 | 首次程序轮询、外部 IRQ 绑零；随后验证已有中断链路 |
| UART | 8N1、115200、无流控；FIFO 与寄存器位按当前 `UART.sv` | 内部分频模式 CTRL=`0x14`；50 MHz 时 BAUD=`433` |
| 固件格式 | 每项一个 32 位小端组合字；独立指令和数据 HEX/COE | 保留节之间地址空洞、补齐尾字节、检查深度，包含需要的 `.trap` |
| 启动代码 | `board_tests/platform/start.S` 设置 sp、清 BSS、调用 main | `.data/.rodata` 必须预初始化；显式处理 gp/链接松弛；不用 WFI 证明休眠 |
| 观测/调试 | `DEBUG_EN` 是仿真/观测配置；未找到 RISC-V DM/DTM | 首版用 LED/UART；ARM XSCT ELF 下载不能替代 RISC-V 固件装载 |

UART 的 **434 个周期/位** 与本 SoC 的 **BAUD 寄存器=433** 是同一个设置：当前计数器比较 `>= uart_baud`，从 0 数到 BAUD，周期为 `BAUD+1`。不能直接把交接报告中的分频周期 434 写入后宣称完全相同配置。

Windows 工具链已经实际完成两种 ISA 的 C/汇编编译、按本工程 linker 链接、64 位除法 libgcc 链接、ELF32/入口/未解析符号检查，以及 HEX/COE 导出。这仅证明主机编译链可用，未运行该程序验证 SoC。

## 4. 需要修改的实现，而非缺失的板卡资料

1. **RAM 与初始化**：`my_cpu.sv` 的非 DEBUG RAM 分支为空，DEBUG 数据 RAM 是组合读；当前测试台向层次数组加载镜像，上板不会自动加载。需落实可综合、可初始化的同步 BRAM，并与 bridge 联动，不能简单增加一个读寄存级。XC7Z020 数据库有 140 个 36 Kb BRAM；16 KiB + 256 KiB 按 1024×32 配置约需 68 个，最终以综合映射和全设计资源报告为准。
2. **MMIO 读响应**：`bridge.sv` 请求沿采集外设返回值，而 UART/Timer/PLIC 在同沿才寄存本次响应，导致采到旧值。需要对齐返回选择；UART RX FIFO 和 PLIC claim 带读副作用，不能用重复空读规避。须验收 CPU→bridge→外设完整链路。
3. **硬件除法**：`divider.sv` 用组合 `/`、`%`，十拍计数只是 valid 延迟；硬件实现/时序尚未落实。保留现有 RV32M 能力，但应确定可收敛的除法实现，并匹配商/余数顺序、握手及 flush 排空行为。
4. **板级壳/约束**：50 MHz 单时钟、J20 复位同步、两个 LED、现有 UART 接到实际 PL 引脚；独立构建目录，不覆盖上一会话已测工程。50 MHz 是计划输入，不能引用 UART 基线余量作为 SoC 时序结论。
5. **首个 C 程序**：补短自检，包含早期 LED 阶段码、初值/BSS、RAM 字/字节/半字、栈与函数调用、有限等待的 UART 启动输出。随后分步验收接收/回显、Timer、PLIC 与乘除法，均为已有功能的测试。

首个程序可复用 platform 启动/linker，采用 `-march=rv32i_zicsr -mabi=ilp32 -mcmodel=medany -mstrict-align -ffreestanding -fno-builtin -msmall-data-limit=0 -mno-relax -nostdlib`，链接 `--no-relax --gc-sections`，需要时在对象之后加 `-lgcc`。CoreMark 的 175 MHz / UART 1519 常量需改为最终时钟参数；首次不以其性能输出作启动判据。

## 5. 实际证据复核

- 原始交接：板卡测试工作目录下的 `RISCV_SOC_BOARD_HANDOFF.md`。
- 引脚约束：板卡测试工作目录下的 `fpga/constraints/hellozynq_uart.xdc`；实际 RTL 与报告接口一致。
- 串口报告：板卡测试工作目录下的 `reports/board-uart-2026-10-18.md`；PL 10,111 + PS 1,111 = 11,222 次交换。原始流独立复核一致；该结论只覆盖对应 UART 测试设计，不覆盖本 RISC-V SoC。
- 基线镜像实算 SHA-256 与交接一致：PL bit=`911BDD7FDC5BA4C8A03DF65EEA30E96D31B70019E0C844E27FFD9E033EF6023C`；PS bit=`70E272697E65884C298F6CE6581A22EF5821BF340D4948C9B0B95152CC8F6674`；ARM ELF=`67295AF79634759A9A2C6D2387456A4D05B210A441D96D1A39B670D5B0C17B54`。
- 只枚举串口时仍见 COM6 / CH340 / VID:PID `1A86:7523`，未打开串口。
- 本轮 Vivado 2023.2 批处理只读发现同一目标 `localhost:3121/xilinx_tcf/Digilent/<序列号>`，器件 `arm_dap_0`、`xc7z020_1`；未编程、未复位。`-1`、`-2` 两个 part 数据库均已安装。JTAG 结果不能确认速度档或 PCB 版本。
- Vivado 在仅创建内存工程、未打开设计时的 package-pin 查询未返回对象；本轮引脚结论来自原理图、现存 XDC/实现证据和已测接口，不将空查询算成器件数据库引脚确认。
- 本轮工具原始记录：`F:/Tools/_codex_tmp/riscv-board-readiness-20261018/readiness.log`；工具链验证：`F:/Tools/_codex_tmp/riscv-windows-validation-20261018/validation-results.json`。

板卡测试工作目录下现有打包文件 `artifacts/zynq7020-uart-boardtested-20261018.zip` 的基线镜像/报告与磁盘当前版本一致，但不含最后的 `RISCV_SOC_BOARD_HANDOFF.md`。本机使用不受影响；单独交付 ZIP 时需同时携带交接 Markdown 和本核对文档。本轮保留原包，不覆盖历史证据。

工具入口为 `W:/APP/Xilinx/Vivado/2023.2/bin/vivado.bat`。旧 `VIVADO_BIN` 可能失效；Vivado 子进程使用临时最小 PATH 可避开本机无效 npm 联接。原测试构建脚本固定 UART top/源码清单，只参考环境处理，不直接套为 SoC 构建入口。

## 6. 待补字段与首次验收

| 项目 | 当前处理 |
| --- | --- |
| 实物完整型号、速度档、温度等级 | 候选为 `xc7z020clg484-2`，依据用户补充的配套教程、原厂工程及上一轮基线；实物速度档/温度等级仍待完整丝印或可靠采购料号核实 |
| 实物 PCB 版本 | 未知；首版限已确认公共接口，新增排针/其他外设前再确认 |
| J20 按下后的真实复位、LED 肉眼状态 | 已有引脚资料，属于首次上板验收，不是资料缺失 |
| 冷启动、重配置、持续运行 | 需在新 SoC 上独立验收，不能继承 UART 基线通过结论 |
| DDR、SD/QSPI、HDMI/网口、其他 GPIO | 本次范围不需要，未验证状态保留 |

资料阶段已满足开始首版源码适配的条件；当前尚未声称 RISC-V 程序在 FPGA 上运行。后续实现应保留现有五级核和 SoC 功能范围，逐项处理第 4 节并建立自己的镜像、时序、资源、DRC/CDC 和串口证据。
