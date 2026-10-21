# Questa 纯 RTL 阶段开发规划（`dev/linux-rtl`）

本文是 `dev/linux-rtl` 分支在 **QuestaSim 纯 RTL 仿真阶段**的执行手册。目标读者是刚接手、还不熟悉本工程的开发者：照着本文的阶段顺序、测试清单、完成标志和边界去做，就不会做偏。

上层路线见 [LINUX_ROADMAP.md](LINUX_ROADMAP.md)；本文只覆盖其中“能在 Questa 里用 riscv-tests 验证”的部分，并把它细化到每个阶段做什么、用哪些测试文件、做到什么程度算完、哪些事情不许做。

---

## 0. 先读这一节

### 0.1 本阶段做什么、不做什么

**做：** 把现有 RV32 五级顺序核改造成具备 Linux 所需硬件能力的核，全部在 QuestaSim 中用 riscv-tests 及少量自编汇编定向测试验证。终点是：RV32IMA + Zicsr + Zifencei、M/S/U 特权级、Sv32 MMU、阻塞式 cache、以及 Linux 平台所需的 CLINT / PLIC / UART 外设，全部回归通过。

**不做（本阶段一律不碰）：**

- 上板、Vivado 实现、时序收敛、板级约束、AXI、PS DDR。
- C 程序、CoreMark、OpenSBI、Linux 内核、设备树、Verilator 长程序仿真。
- FPU（F/D/Zfh）、压缩指令（C）、Zbc、Zbkx、乱序或多发射、性能优化。
- 为了“跑分好看”调整流水线结构。

这些内容在本阶段结束后另行规划；它们的测试不进入本阶段回归。

### 0.2 铁律

违反任何一条的提交都不能合并。

1. **测试是裁判，不能改裁判。** 不许为了通过而手改 HEX / dump、修改 riscv-tests 源码、在测试台里按测试名或 PC 特判、调长超时掩盖死循环。测试镜像只能由生成脚本产生。
2. **棘轮原则。** `test/isa_manifest.csv` 中标为 `PASS` 的测试永远不许失败。任何改动只能让测试从 `XFAIL` 晋级为 `PASS`，不能反向。如果确实需要把一个 `PASS` 降为 `XFAIL`，必须先停下来找负责人确认，并在 `doc/decisions.md` 里写明原因。
3. **先有会失败的测试，再改 RTL。** 每个新功能都要先找到或写出一个当前会 FAIL 的测试，改完后亲眼看到它变成 PASS。
4. **不跨阶段。** 每个阶段都有“边界”清单。S1 不许顺手加 S 模式，S2 不许顺手加 cache。超出边界的想法记到 `doc/decisions.md` 的“待办”里。
5. **规范优先于测试。** 遇到规范疑问，查规范原文（版本见第 3 节），把结论写进 `doc/decisions.md`。不许“看测试怎么测就怎么做”而违背规范。
6. **以退出码判定，不靠肉眼。** 回归脚本的退出码是唯一的通过判据，不要靠在日志里找字符串来判断“好像过了”。
7. **保持可综合。** 虽然本阶段不上板，RTL 仍须可综合：不写 `#延时`、不在 RTL 中用 `/`、`%` 做运算、不用 `initial` 初始化寄存器（仿真存储模型除外），每个阶段结束跑一次综合检查（S0 提供脚本）。
8. **文档与代码同步。** 修改 CSR 集合、地址图或总线协议时，同一个提交里必须更新附录对应的表格和 `doc/arch/` 下的说明，否则视为未完成。
9. **小步提交。** 每个提交只做一件事，提交信息写明晋级了哪些测试，例如 `S1: trap illegal opcodes (rv32mi-p-shamt PASS)`。

### 0.3 分支与合并流程

- 每个阶段开工时，先在 `dev/linux-rtl` 当前提交上打标签 `sN-start`，用于阶段结束时比较改动范围。
- 每个阶段从 `dev/linux-rtl` 切出 `stage/sN-<主题>`，例如 `stage/s1-precise-trap`。
- 阶段内可以有多个小分支，但都合回该阶段分支。
- 阶段完成标志全部满足后，通过 PR 合回 `dev/linux-rtl`。PR 描述里贴回归汇总、晋级测试列表、综合检查结果。
- 合并后在 `dev/linux-rtl` 上打标签 `sN-done`。

### 0.4 什么时候必须停下来问

- 想把 `PASS` 改成 `XFAIL`，或者想在 manifest 里删掉一个测试。
- 规范允许多种实现、而选择会影响后续阶段（例如 A/D 位的更新方式、PMP 项数、地址图）。第 3 节已拍板的不用问。
- 一个测试按设计决策就不可能通过，例如它要求硬件支持不对齐访问。
- 需要修改 `cpu_top` 对外端口或 SoC 总线协议，超出本阶段说明的范围。
- 连续两天卡在同一个失败上。

---

## 1. 现状基线（2026-10-21 实测）

用当前 `dev/linux-rtl`（提交 `00c277f`）的 RTL 和**现有** HEX 镜像，以原测试台 `tb_my_cpu`（1000 周期超时）逐个运行 `hex/riscv-tests/` 下全部 284 个镜像。完整结果见 [baseline/riscv_tests_sweep_20261021.csv](baseline/riscv_tests_sweep_20261021.csv)。

| 套件 | PASS | FAIL | TIMEOUT | 说明 |
| --- | ---: | ---: | ---: | --- |
| rv32ui-p | 39 | 2 | 1 | FAIL：`fence_i`、`ma_data`；TIMEOUT：`ld_st`（1000 周期不够，非 RTL 问题） |
| rv32um-p | 8 | 0 | 0 | |
| rv32mi-p | 11 | 5 | 0 | FAIL：`breakpoint`、`illegal`、`ma_addr`、`mcsr`、`shamt` |
| rv32si-p | 2 | 4 | 0 | `scall`、`wfi` 的 PASS **疑似空过**（核里根本没有 S 模式） |
| rv32ua-p | 0 | 9 | 1 | 没有 A 扩展 |
| rv32uzba-p | 3 | 0 | 0 | |
| rv32uzbb-p | 13 | 5 | 0 | FAIL：`clz`、`ctz`、`rol`、`ror`、`rori` |
| rv32uzbkb-p | 5 | 0 | 0 | |
| rv32uzbs-p | 7 | 1 | 0 | FAIL：`bseti` |
| rv32uzbc-p / uzbkx-p | 0 | 5 | 0 | 不在本阶段范围 |
| rv32uf / ud / uzfh / uc（-p） | 0 | 33 | 0 | 不在本阶段范围 |
| 所有 `-v` 套件 | 0 | 全部 | 0 | **镜像本身已损坏**（见 2.2），结果没有参考意义 |

需要特别警惕的“PASS”，S0 用新测试台重跑后要逐个复核：

- `rv32si-p-scall`、`rv32si-p-wfi`：没有 S 模式却通过，很可能是测试里的检查被跳过了。
- `rv32mi-p-instret_overflow`、`rv32mi-p-zicntr`、`rv32mi-p-pmpaddr`：核里没有 `minstret`、`cycleh` 等 CSR，未知 CSR 读出 0 且写入被丢弃，测试可能“碰巧”通过。
- `rv32mi-p-{lh,lw,sh,sw}-misaligned`：通过，但已知不对齐的 store 会先把错误数据写上总线再陷入（第 5 节 S1 修复），测试没有覆盖这个副作用。

从同一批数据还能读出几处已知的 RTL 缺陷，S1 会逐条处理：

- 不认识的指令一律被当成 NOP 执行，不产生非法指令陷入。
- `misa` 读出 0。
- `mret` 只有之前发生过陷入才会跳转。
- `clz`、`ctz` 被译成了 `cpop`，`rol`、`ror`、`rori`、`bseti` 没有实现。
- FLW 被当成 store 执行，会写内存。
- `instret` 是估算值。
- 访存请求在 EX 阶段就发出，而对齐检查要到 MEM 阶段才做。

---

## 2. 测试资产与调试方法

### 2.1 现有 HEX 的格式与测试台机制

- `hex/riscv-tests/*.hex`：每行一个 32 位小端字，从 `0x80000000` 开始连续存放，**没有 `@地址` 标记**。`index.csv` 记录每个镜像的起止地址和字节数。
- `tb_my_cpu` 把同一个 HEX 同时加载进指令 ROM（16 KiB，按 `addr[13:2]` 镜像）和数据 RAM。数据端口的 `0x8000_xxxx` 区间是数据 RAM 前 64 KiB 的别名。
- 判定方式：写回 PC 等于 `0x80000044`，并且 `x3`（`gp`）等于 1。这依赖 riscv-tests `-p` 环境 `write_tohost` 的固定布局，换了环境就失效。
- 超时 10000 ns，即 1000 个周期。

### 2.2 现有镜像的已知缺陷（必须在 S0 解决）

1. **生成时丢掉了地址空洞。** 例如 `rv32ua-p-*` 的 `index.csv` 地址跨度到 `0x80002008`，但 HEX 只有 4168 字节（到 `0x80001048` 为止），`0x80002000` 处的 `amo_operand` 不在镜像里。这个测试恰好先写后读，所以没出问题。
2. **`-v` 镜像全部不可用。** 例如 `rv32ui-v-add` 的代码引用了 `0x8000307c` 处的字符串、`0x80004000` / `0x80005000` 处的页表，栈在 `0x8000af70`，但 HEX 只有 12040 字节（到 `0x80002F08`）。段被首尾相接拼在了一起，加载后地址全部错位。
3. **没有 ELF、没有带符号的反汇编，来源和编译参数不明。** 2026-10-21 用官方源码重新构建后对照确认：旧 `-p` 镜像与上游按 `rv32g` 编出的指令逐字一致，只是来自较早的上游版本（AMO 不带 `aq`/`rl`），问题出在转 HEX 的那一步。重新构建的结果见 2.3。

### 2.3 测试源码、带符号反汇编与镜像的来源

官方 riscv-tests 已克隆到工作区外的独立目录 `W:\riscv-test`（说明见该目录的 `README.md`），并用本机 xPack GCC 构建完成。

- 构建命令：`python W:\riscv-test\build_riscv_tests.py`。
- 产物在 `W:\riscv-test\out\`：每个测试的 `.elf`、带符号的 `.dump`、补零的连续 `.hex`，以及含 `tohost` 地址的 `index.csv`。共 210 个测试：本阶段范围内套件的 `-p` 与 `-v`。
- 2026-10-21 已验证：新 `-p` 镜像在当时的 RTL 上逐项结果与旧基线完全一致。106 个与旧镜像逐字相同；10 个 `rv32ua-p` 不同，原因是新版上游 AMO 带 `aq`/`rl` 位，以及旧镜像丢了数据段。

**查看某个测试的反汇编，直接打开 `W:\riscv-test\out\<测试名>.dump`。**

下面这种从旧 HEX 反汇编的方法已不再需要，仅作留档（没有符号，`-v` 镜像的地址是错的）：

```powershell
# hex -> bin（每行一个小端 32 位字）
python -c "import struct,sys; ws=[int(l,16) for l in open(sys.argv[1]) if l.strip()]; open(sys.argv[2],'wb').write(b''.join(struct.pack('<I',w) for w in ws))" hex\riscv-tests\rv32mi-p-mcsr.hex build\mcsr.bin
```

```powershell
F:\Tools\Apps\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-objdump.exe -D -b binary -m riscv:rv32 --adjust-vma=0x80000000 build\mcsr.bin
```

`-v` 镜像用这种方法反汇编出来的地址是错的（原因见 2.2），不要用。

### 2.4 怎么读一个 riscv-tests 测试

- 每个子测试开头都有 `li gp, N`，这个 N 就是 `TESTNUM`。失败时程序把 `gp` 设成 `(N << 1) | 1` 写入 `tohost`。因此**失败值右移一位就是失败的子测试编号**，在 dump 里搜 `li gp,N` 就能找到出错的那段指令。
- 全部通过时写入 `tohost` 的值是 1。
- 如果失败值的低位是 `0x539`（例如 `0x539`、`0x53b`），说明发生了**测试没预料到的陷入**：环境的陷入入口执行了 `ori gp, gp, 1337`。这时要看 `mcause`、`mepc` 是什么，而不是去看子测试本身。
- `-p` 环境：机器模式，无虚拟内存。`rv32si-p` 测试会通过 `mret` 进入 S 模式执行。
- `-v` 环境：环境本身带一个小的 S 模式内核，建立 Sv32 页表，测试代码运行在 U 模式的虚拟地址上，缺页时按需分配物理页。它要求 `0x80000000` 起有足够大的 RAM：现有镜像的栈约在 `0x8000b000`，页表在 `0x80004000` 一带，按需分配的物理页取自镜像之后的 RAM。具体范围以 S0 引入的 `env/v/vm.c` 和生成的 dump 为准，本规划按 1 MiB 统一 RAM 留足余量。失败时它还会通过 `tohost` 逐字符打印信息。
- 测试源码在 `W:\riscv-test\riscv-tests\isa\`。注意 `rv32ui/*.S` 大多只是 `#include` 了 `rv64ui/` 下的同名文件，要去 `rv64*` 目录读真正的测试代码。用到的宏（`TEST_RR_OP` 等）在 `isa\macros\scalar\test_macros.h`，环境代码在 `env\p\`、`env\v\`。看不懂某段测试时先读宏定义。

### 2.5 标准调试流程（新人照做）

1. 运行 `python scripts/regress.py isa --test <测试名> --trace`（S0 提供），拿到结果和失败编号 N。
2. 打开 `build/regress/<测试名>/<测试名>.dump`，搜 `li gp,N`，读这一小段测试在做什么，以及期望值是多少。
3. 打开同目录的 `retire.log`（每条退休指令一行：周期、PC、指令、写回寄存器和值；陷入单独一行），找到这段代码，逐行对照 dump 和期望值。
4. 定位到第一条结果不对的指令，再用 `--wave` 生成波形，观察它在流水线各级的信号。
5. 修 RTL，先单测这个测试，再跑一遍已晋级集合确认没有回退。

---

## 3. 全局技术决策（已拍板，照做即可）

| 项目 | 决定 |
| --- | --- |
| 规范版本 | Unprivileged ISA 20191213；Privileged ISA 20211203（v1.12）。全部以这两份为准 |
| 目标 ISA | RV32IMA_Zicsr_Zifencei_Zicntr，外加 Zba、Zbb、Zbkb、Zbs（已有实现，S1 补全缺的指令） |
| 不实现的扩展 | F、D、Zfh、C、Zbc、Zbkx：这些编码一律产生**非法指令陷入**，`misa` 中对应位为 0 |
| 不对齐访存 | 不做硬件支持，一律陷入（地址不对齐异常，`mtval` = 访问地址）。`rv32ui-p-ma_data`、`rv32ui-v-ma_data` 永久 `XFAIL`（以后由 M 模式软件模拟） |
| 页表 A/D 位 | 软件管理：访问 A=0 的页，或向 D=0 的页写入，产生对应的页故障，硬件不写回页表 |
| PMP | 首版 0 个表项：`pmpcfg*` / `pmpaddr*` 存在、只读 0（规范允许）。以后需要时再加 |
| 调试触发器 | 不实现触发器：`tselect` 可读写、读回 0；`tdata1` / `tdata2` / `tdata3` 读 0，写入忽略；`tinfo` 读 0 |
| `mtvec` | 只支持 Direct 模式；`MODE` 字段写入非 0 时保持为 0（WARL） |
| 复位 PC | `0x8000_0000`，保留为参数 |
| 统一 RAM | S2 起 `0x8000_0000` 起 1 MiB（参数化，可调大），仿真存储模型上电清零，不得出现 X |
| 地址图 | S2 起按附录 C；未映射地址产生访问错误异常 |
| 栈值缓冲 | S2 起默认关闭（参数 `STACK_BUF_EN=0`），它是数据 RAM 的非一致影子副本，与统一内存、MMU、cache 都不兼容。保留单元测试，不再进 SoC |
| `LW_LIVE_BYPASS_ENABLE` | 保持默认关闭，不使用 |
| 中断 | S4 起 MTIP / MSIP 来自 CLINT，MEIP / SEIP 来自 PLIC；`time` / `timeh` CSR 读 CLINT 的 `mtime` |

---

## 4. 阶段总览

| 阶段 | 主题 | 主要验收测试 | 工作量 |
| --- | --- | --- | --- |
| S0 | 测试基础设施（不改功能） | 现有通过集在新镜像 + 新测试台上全部复现 | 中 |
| S1 | M 模式合规与精确异常 | rv32mi-p 除 `illegal` 外全部；Zb 补全；S1 定向测试 | 中 |
| S2 | 可等待的访存接口 + 统一内存 + 新地址图 | `rv32ui-p-fence_i`；全部已晋级测试在随机延迟下通过 | 大 |
| S3 | A 扩展与内存顺序 | rv32ua-p 全部 | 中小 |
| S4 | M/S/U 特权级 + CLINT + 中断 | rv32si-p（`dirty` 除外）、`rv32mi-p-illegal`；中断定向测试 | 大 |
| S5 | Sv32 MMU | 所有 `-v` 套件、`rv32si-p-dirty`；MMU 定向测试 | 大 |
| S6 | 阻塞式 I/D cache | 全部测试在 cache 开 / 关 × 多个延迟种子下通过 | 中大 |
| S7 | Linux 平台外设对齐（PLIC / UART） | 外设单元测试 + 定向汇编测试 | 中 |

阶段之间严格串行：S2 依赖 S1 的精确异常；S5 依赖 S4 的特权级；S6 依赖 S2 的握手接口。只有 S7 的外设单元测试部分可以在 S4 之后与 S5、S6 并行。

---

## 5. 各阶段详细说明

### S0 测试基础设施（不改任何功能逻辑）

**目标：** 建立一套可信、可复现的测试流程：测试镜像可再生成、每个测试都有带符号的反汇编、测试台能统一判定 `-p` 和 `-v` 环境、回归有棘轮。这个阶段结束时，RTL 的行为必须与 S0 开始时完全一致。

**必做内容：**

1. **riscv-tests 源码与构建：已完成（2026-10-21）。**
   - 源码放在工作区外的 `W:\riscv-test\riscv-tests`，**不作为 submodule，也不拷进工作区**。
   - 构建脚本是 `W:\riscv-test\build_riscv_tests.py`，第 2 条的要求它都已满足。
   - S0 只需要：
     - 在 `test/README.md` 里记录外部目录位置和 `out/build_info.json` 中的两个提交哈希；
     - 把本阶段要用的 `.hex`、`.dump` 和 `index.csv` 拷进工作区 `hex/riscv-tests-gen/`（这是测试的输入，需要进版本控制，保证回归可复现）；
     - 删除旧的 `hex/riscv-tests/`。
   - 以后升级 riscv-tests 版本，在外部目录更新源码、重新构建，再整体替换 `hex/riscv-tests-gen/`。替换要单独提交，提交信息写明新旧提交哈希，并附上全回归结果。
2. **生成脚本的要求**（`W:\riscv-test\build_riscv_tests.py` 已按此实现，修改它时不得违反）。本机没有 `make`，所以由 Python 直接调用 gcc。
   - **工具链：** 固定使用 `F:\Tools\Apps\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-*`，路径可用参数或环境变量覆盖。每次编译都显式传 `-march` 和 `-mabi=ilp32`，不依赖它默认的 `rv32imac`。
   - **编译参数：** 照抄上游 `isa/Makefile`：`-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles`。
     - `-p` 环境：`-I env/p -I isa/macros/scalar -T env/p/link.ld`。
     - `-v` 环境：额外编译 `env/v/entry.S` 和 `env/v/*.c`，加 `-std=gnu99 -O2 -DENTROPY=0x<测试名 md5 的前 7 位>`，与上游一致。
     - `-march` 按上游各套件的设置（如 `rv32g` 系列，GCC 15 下写成 `rv32g_zicsr_zifencei` 或拆开写）；Zb 套件按上游加对应扩展。
   - **每个测试产出：**
     - `.elf`（不提交）。
     - `.dump`：`objdump -D`，带符号，提交。
     - `.hex`：从 `0x80000000` 连续填到 `_end`（含 `.bss`），4 字节对齐，空洞和 `.bss` 一律填 0，每行一个小端 32 位字，提交。
   - **索引文件 `index.csv`：** 每个测试一行，包括测试名、套件、`-march`、起始地址、`_end`、`tohost` 地址（从 ELF 符号表读取）、字数、HEX 的 SHA-256。
   - **ISA 自检：** 生成后扫描 dump，非 F/D 套件中出现浮点指令就报错，防止工具链默认参数把未实现的指令混进来。`-march` 用的是上游的 `rv32g`，本身不含 C，因此不会出现压缩指令。已知的两处合法例外写在 `W:\riscv-test\README.md`：`csr` 测试有运行时 `misa.F` 判断；`-v` 环境 `handle_trap` 里有一条不执行的 `fssr`。
   - **构建范围：** 只构建本阶段范围内的套件：`rv32ui`、`rv32um`、`rv32ua`、`rv32mi`、`rv32si`、`rv32uzba`、`rv32uzbb`、`rv32uzbkb`、`rv32uzbs` 的 `-p` 和 `-v`（`mi` / `si` 只有 `-p`）。
   - **符号链接：** 上游 `env` 里的 `link.ld` 是符号链接，Windows 上会检出成文本，脚本会自动解析，不需要特殊权限。
3. **新测试台 `test/tb_isa.sv`。** 旧 `tb_my_cpu` 在 S0 结束时删除。
   - **参数：** 用 plusargs 传入 `+HEX=<路径>`、`+TOHOST=<十六进制地址>`、`+MAX_CYCLES=<n>`，以及可选的 `+TRACE`、`+SEED=<n>`。不再拷贝到固定文件名。
   - **判定：** 监视 SoC 数据端口对 `tohost` 和 `tohost+4` 的写入，以**写入高字 `tohost+4`** 作为触发点，组合出 64 位值：
     - 高 32 位为 `0x0101_0000`：这是字符输出请求，把低 8 位追加打印到日志，并把内存中的 `tohost` 清零，模拟主机已处理。
     - 高 32 位为 0、值为 1：`TEST PASS`，正常结束。
     - 高 32 位为 0、值是其他奇数：`TEST FAIL testnum=<值>>1>`，非零退出。
     - 超过 `MAX_CYCLES`：`TEST TIMEOUT`，打印最后的 PC，非零退出。
     - S0 必须用 `-v` 环境的 dump 核对：GCC 编译出的 64 位 `tohost` 写入确实是先写低字、后写高字。如果不是，调整触发规则，并把结论写进 `doc/decisions.md`。
   - **退休日志：** 打开 `+TRACE` 时输出 `retire.log`，每行格式为 `<周期> <PC> <指令字> [x<rd>=<值>] [mem <地址> <w/r> <数据>]`，陷入和 `xRET` 各单独记一行，写明原因、`tval` 和目标 PC。
   - **默认安静：** 不再每周期刷屏。
4. **允许的 RTL 改动（仅此一类）。** 为退休日志在 `ifdef DEBUG_EN` 下增加观测端口，例如 WB 级的指令字、退休有效脉冲、陷入原因和 `tval`。不得改变任何功能信号。
5. **回归脚本 `scripts/regress.py`。**
   - **子命令：** `isa`（按 manifest 跑）、`directed`（原有 8 个定向测试，加上第 6 节的自编测试）、`all`。
   - **运行方式：** 每次在全新的 `build/regress/<时间戳>/` 下编译和运行，不改动仓库里的任何文件。
   - **退出码：** 任何预期为 `PASS` 的测试没有通过 → 退出码非 0；任何 `XFAIL` 意外通过（`XPASS`）→ 同样非 0，并提示去 manifest 里把它晋级。这样每次晋级都是有意识的操作。
   - **结果文件：** 同时输出 JSON 汇总和一张人能读的表。
6. **测试清单 `test/isa_manifest.csv`。**
   - **列：** `test`、`suite`、`env`（p/v）、`expect`（`PASS` / `XFAIL` / `SKIP`）、`stage`（预计在哪个阶段晋级）、`max_cycles`、`note`。
   - **初始内容：** 以新镜像、新测试台的实测结果为准。2026-10-21 基线里疑似空过的测试，在 note 里写“需在 S1/S4 复核”。
   - **超时默认值：** `-p` 为 200 000 周期，`-v` 为 5 000 000 周期。
7. **综合检查脚本 `scripts/synth_check.tcl`（附带 PowerShell 入口）。**
   - 对 `my_cpu` 做 Vivado out-of-context 综合；把 `rtl/cpu_top/divider.sv` 替换为 `rtl/cpu_top/synth/rv32_divider_hw.sv`；关闭 `DEBUG_EN`。
   - 只检查语法可综合、无锁存器、无多驱动，**不检查时序**。
   - 把当前 RTL 的警告数量记为基线，后续阶段不得新增锁存器或多驱动警告。

**边界（S0 不许做）：** 不修任何 RTL bug（即使已经看到了），不改 CSR，不改地址图，不重写流水线。看到的问题全部记进 manifest 的 note 或 `doc/decisions.md` 的待办。

**用到的测试：** 全部本阶段范围内的套件；原 8 个定向测试（`tb_mul_pipeline`、`tb_stack_value_buffer`、`tb_if_sync_btb_single`、`tb_lw_live_bypass`、`tb_PLIC`、`tb_timer`、`tb_UART`、`tb_div_kill_drain`），外加 `run_board_divider.ps1` 的硬件除法器测试。

**完成标志：**

- [ ] `hex/riscv-tests-gen/` 中的镜像与外部 `W:\riscv-test\out\index.csv` 记录的 SHA-256 一致；在外部目录重复构建，产物的 SHA-256 不变；ISA 自检通过。
- [ ] 新流程下，旧回归的 77 个指令测试全部 PASS，结果与旧流程一致；8 个定向测试和硬件除法器测试 PASS。
- [ ] `rv32ui-p-ld_st` 在新的超时设置下有确定结论（PASS，或有明确原因的 XFAIL）。
- [ ] 对任意一个 `-p` 测试和任意一个 `-v` 测试，人为让它失败（例如在测试台里临时把某条指令的结果翻转一位，验证完删掉），确认测试台报出 `FAIL testnum=N`，并且 `retire.log` 能定位到出错指令。
- [ ] `git diff s0-start -- rtl/` 只包含 `DEBUG_EN` 观测端口。
- [ ] `run_all.bat`、`scripts/run_board_regression.py`、`test/tb_my_cpu.sv` 已删除，README 改为新入口。
- [ ] 综合检查脚本能运行，基线警告已记录。

### S1 M 模式合规与精确异常

**目标：** 在只有 M 模式的前提下，让核的异常、CSR 和计数器完全符合规范，并且所有陷入都是精确的。这是后面所有阶段的地基。

**必做内容：**

1. **非法指令陷入（mcause=2，`mtval` = 指令字）。** 以下情况都要陷入：
   - 未知 opcode，以及合法 opcode 下的非法 funct3 / funct7 组合。
   - RV32 下 shamt 第 5 位为 1 的 `slli` / `srli` / `srai`。
   - 全 0 和全 1 的指令字。
   - 所有 F/D/Zfh/C/Zbc/Zbkx 编码，包括目前会执行出错的 FLW / FSW。可以直接删掉 `fpu.sv`、`reg_fpu.sv` 的译码与通路，这是本阶段允许的删除。
   - 访问不存在的 CSR；写只读 CSR（CSR 地址 `[11:10]==2'b11`，但 rs1=x0 或 zimm=0 的 `csrrs` / `csrrc` 不算写）。
   - 特权级不够的 CSR 访问，在 S4 引入低特权级后自然生效；S1 先把检查逻辑做成按特权级比较的形式。
2. **CSR 集合按附录 B 的 S1 列实现。**
   - `misa = 0x4000_1100`（RV32，I、M）。
   - `mvendorid`、`marchid`、`mimpid`、`mhartid` 只读 0。
   - `mstatus` 只保留 S1 列出的字段，其余位读 0。
   - `mtvec` 按第 3 节的 WARL 规则。
   - `mepc[1:0]` 恒为 0。
   - `mcause` 只能写入合法值。
3. **计数器：** `mcycle` / `mcycleh` / `minstret` / `minstreth` 都是 64 位且可写；`cycle` / `cycleh` / `instret` / `instreth` 是它们的只读影子；`mcountinhibit` 的 CY、IR 位可写。
   - `minstret` 必须由**真实退休事件**递增：被冲刷的指令、产生异常的指令不计入。删除现有“退休数减去 3×异常数、3×分支数”的估算公式。
   - CSR 指令写 `minstret` 的那一拍，该指令自身是否计数，按规范处理并写进 `doc/decisions.md`。
4. **`mret` 无条件跳转到 `mepc`。** 删除 `prev_exception_flag` 的条件。`mstatus` 按规范恢复：`MIE←MPIE`，`MPIE←1`，`MPP←最低支持特权级`。
5. **`wfi`：** 在 S1 实现为“立即退休、继续执行”，规范允许这样做。
6. **`fence`：** 实现为排空在途访存后再继续（在 S1 的接口下就是普通 NOP 的时序）；`fence.i` 留到 S2。
7. **精确异常：**
   - 不对齐检查从 MEM 提前到**发出访存请求之前**。不对齐的 load / store 不得出现在数据总线上，`dmem_en` 和写使能都不得拉高。
   - 中断响应不得重复已经产生副作用的指令。必须保证：一条已经把 store 请求发上总线的指令，不会再以“被中断、`mepc` 指向自己”的方式重新执行。具体做法可以是在请求发出前的流水级响应中断，或把已发出请求的指令标记为不可中断。选定的方案写进 `doc/arch/trap.md`。
   - 被冲刷的指令不得写寄存器、CSR 或内存。
8. **调试触发器 CSR：** 按第 3 节实现“无触发器”。
9. **Zb 补全或报错：** 实现 `clz`、`ctz`、`rol`、`ror`、`rori`、`bseti`，并修正现在把 `clz`/`ctz` 误译为 `cpop` 的问题。其余 Zb* 编码必须走非法指令。

**边界：** 不加 S/U 模式，不实现 `sret`；不改访存接口的握手方式（仍是固定一拍）；不改地址图；不加 A 扩展；不碰分支预测和流水线结构，除非是精确异常必需的改动，并且要在 PR 里说明。

**用到的测试：**

- 晋级为 PASS：
  - `rv32mi-p-mcsr`、`rv32mi-p-shamt`、`rv32mi-p-ma_addr`、`rv32mi-p-breakpoint`。
  - `rv32uzbb-p-{clz,ctz,rol,ror,rori}`、`rv32uzbs-p-bseti`。
- 必须真正通过（不再是疑似空过）：`rv32mi-p-instret_overflow`、`rv32mi-p-zicntr`、`rv32mi-p-{lh,lw,sh,sw}-misaligned`、`rv32mi-p-csr`、`rv32mi-p-scall`、`rv32mi-p-sbreak`、`rv32mi-p-ma_fetch`、`rv32mi-p-pmpaddr`。
- `rv32mi-p-illegal`：保持 XFAIL，但失败编号必须**向后推进**（越过开头的非法指令子测试），停在第一个需要 S 模式的子测试上。把这个编号记进 manifest 的 note。
- 定向测试：第 6 节 S1 部分全部通过。

**完成标志：**

- [ ] 上面列出的测试全部 PASS，manifest 已更新；回归退出码为 0。
- [ ] 第 6 节 S1 定向测试全部 PASS。
- [ ] 附录 B 的 S1 列与 RTL 逐项核对一致（PR 里附核对表）。
- [ ] 综合检查不新增锁存器或多驱动警告。
- [ ] `doc/arch/trap.md` 写明陷入在哪一级提交、中断在哪一级响应、如何保证 store 不重复。

### S2 可等待的访存接口 + 统一内存 + 新地址图

**目标：** 把“固定一拍返回、指令和数据分离”的存储结构，换成能等待任意周期、能返回错误、取指和数据看到同一份内存的结构。这是后面 MMU、cache 以及将来接 AXI / DDR 的前提，也是改动最大的一个阶段。

**必做内容：**

1. **定义总线协议，写进 `doc/arch/mem_protocol.md`。**
   - 请求通道：`valid` / `ready` 握手，携带地址、写数据、字节使能、读 / 写、访问类型（取指 / 数据）。
   - 响应通道：`valid`（S2 中 CPU 必须始终能接收响应），携带读数据和错误标志。
   - 每个端口最多一个未完成请求，这对第一版足够。
   - 冲刷时必须区分两种情况：请求还没被接受，可以直接撤销；请求已被接受，必须等它的响应回来并丢弃，不得把旧响应错配给新请求。
2. **改造流水线：** IF 和 MEM 都能因为请求未被接受或响应未到而停顿。WB 不再假设 MEM 总是就绪。
3. **统一内存模型 `test/models/` 下的双口 RAM。** 取指端口和数据端口访问同一块 1 MiB 存储，上电清零。
   - 带**延迟注入器**：由 `+SEED` 控制，`ready` 和响应延迟在 0 到 N 周期间随机。N 也由参数设置。
   - 能在指定地址区间返回错误响应，用于测试访问错误。
   - 这是仿真模型，不要求可综合；SoC 里可综合的 BRAM 版本留到以后。
4. **新地址图（附录 C）。** UART、旧 timer、LED、PLIC 搬到 `0x8000_0000` 以下；未映射地址返回错误。
5. **访问错误异常：** 取指错误 → mcause 1，load → 5，store → 7，`mtval` = 访问地址。
6. **`fence.i`：** 冲刷取指流水线，并保证它之前的 store 已经写入内存后才重新取指。
7. **栈值缓冲默认关闭**（第 3 节）。

**边界：** 不加 cache；不加 MMU；协议只支持单个未完成请求（多个在途请求是以后的优化）；不实现 AXI；不改 CSR 集合（访问错误相关的除外）。

**用到的测试：**

- 晋级为 PASS：`rv32ui-p-fence_i`。
- 全部已晋级测试在**延迟种子 0（无延迟）、1、2、3 和最大延迟 8 周期**下都 PASS。`regress.py` 增加 `--seeds` 参数，合并前要求跑 `--seeds 0-3`。
- 定向测试：第 6 节 S2 部分。

**完成标志：**

- [ ] 所有已晋级测试 × 4 个种子全部 PASS。
- [ ] S2 定向测试全部 PASS，其中“MMIO 每次访问只生效一次”由测试台统计外设实际收到的写次数来判定。
- [ ] 在测试台里人为制造“冲刷时有在途请求、而响应延迟很长”的场景（定向测试 `s2_flush_outstanding`），不错配、不丢失、不卡死。
- [ ] `doc/arch/mem_protocol.md` 和附录 C 已更新；协议文档带时序图，包括正常、等待、错误、冲刷四种情况。
- [ ] 综合检查通过（存储模型不在综合范围内）。

### S3 A 扩展与内存顺序

**目标：** 实现 LR.W / SC.W 和全部 AMO*.W，使原子操作真正不可分割；明确 `fence` 的顺序语义。

**必做内容：**

1. **译码：** opcode `0x2F`，funct3=010（W）。其他宽度和保留编码一律非法。
2. **AMO 的执行方式：** 作为一次“读—运算—写”的不可分割事务。在单核、单个未完成请求的接口下，可以由 MEM 级保守地串行完成：先读，再写，期间不接受其他数据请求。总线协议中增加 AMO 操作类型，或者用加锁标志表达，写进协议文档。
3. **reservation（保留集）：**
   - 粒度：对齐的 4 字节。
   - 建立：LR 成功读出时建立。
   - 失效：本核对同一地址的任何 store / AMO / SC；任何陷入或 `xRET`；另一条 LR。
   - SC 规则：成功时写入并返回 0，失败时不写并返回 1；SC 无论成功与否都清除 reservation。
   - 以上规则写进 `doc/decisions.md`。
4. **`aq` / `rl` 位：** 第一版对所有 AMO / LR / SC 一律按 `aq=rl=1` 的最强顺序处理（等前面的访存完成，后面的访存等它完成），这是规范允许的保守实现。
5. **非 RAM 区域上的原子操作：** 对 MMIO 区域执行 AMO / LR / SC 产生 store/AMO 访问错误（mcause 7）。地址不对齐产生 mcause 6。
6. **`misa` 置上 A 位。**

**边界：** 不考虑多核和其他总线主机（这是平台契约，记进 `doc/decisions.md`）；不做 AMO 的性能优化。

**用到的测试：**

- 晋级为 PASS：`rv32ua-p-{amoadd_w,amoand_w,amomax_w,amomaxu_w,amomin_w,amominu_w,amoor_w,amoswap_w,amoxor_w,lrsc}`，在 4 个延迟种子下。
- 定向测试：第 6 节 S3 部分。

**完成标志：**

- [ ] rv32ua-p 全部 PASS（× 4 个种子），其余回归无回退。
- [ ] S3 定向测试全部 PASS。
- [ ] reservation 规则和 MMIO 原子操作策略已写入文档。

### S4 M/S/U 特权级 + CLINT + 中断

**目标：** 实现完整的三级特权体系、异常和中断委托，以及 Linux 需要的定时器和软件中断。这一阶段结束后，核在功能上就能跑 SBI 固件了，只是还没有 MMU。

**必做内容：**

1. **当前特权级寄存器（M=3，S=1，U=0）。** 所有 CSR 访问按地址 `[9:8]` 检查特权级。
2. **`mstatus`、`sstatus` 完整字段：** MIE、SIE、MPIE、SPIE、MPP、SPP、MPRV、SUM、MXR、TVM、TW、TSR。`sstatus` 是 `mstatus` 的受限视图，不是另一个寄存器。RV32 还需要 `mstatush`（只读 0，因为只支持小端）。
3. **S 模式 CSR：** `sstatus`、`sie`、`stvec`、`scounteren`、`sscratch`、`sepc`、`scause`、`stval`、`sip`、`satp`。`satp` 在 S4 中只存储不生效，S5 才生效；`satp` 写入的 MODE 只允许 Bare 或 Sv32。
4. **委托：** `medeleg` 和 `mideleg`。不可委托的位（例如 M 模式 ecall 和 M 模式中断）按规范保持只读 0。
5. **陷入、返回与特殊指令：**
   - 陷入时按委托选择进入 M 还是 S。
   - `sret`、`mret` 按规范恢复特权级和中断使能。
   - `ecall` 的原因码按当前特权级区分：U 为 8，S 为 9，M 为 11。
   - `TSR`：S 模式下执行 `sret` 产生非法指令。
   - `TVM`：S 模式下访问 `satp` 或执行 `sfence.vma` 产生非法指令。
   - `TW`：非 M 模式下执行 `wfi` 产生非法指令。S1 的“立即退休”实现保留，规范允许。
6. **计数器访问控制：** `mcounteren` 和 `scounteren` 控制低特权级能否读 `cycle`、`time`、`instret`。
7. **CLINT（地址见附录 C，按 SiFive CLINT 布局）：**
   - `msip`：写 1 置位 `mip.MSIP`。
   - `mtimecmp` 和 `mtimecmph`：当 `mtime >= mtimecmp` 时 `mip.MTIP` 置位。
   - `mtime` 和 `mtimeh`：64 位，按参数分频递增。
   - `time` / `timeh` CSR 读 `mtime`。
8. **中断判定：** `mip` 和 `mie` 完整实现（MSIP、MTIP、MEIP、SSIP、STIP、SEIP）。全局使能和优先级按规范：M 级中断在低于 M 的特权级下始终可以抢占。`mip.STIP`、`SSIP`、`SEIP` 可以由 M 模式软件写。PLIC 先只接 MEIP（S 上下文在 S7）。
9. **PMP：** 按第 3 节实现 0 个表项。
10. **`misa` 置上 S、U 位。**

**边界：** 不实现 MMU 地址翻译（`satp` 只存储）；不改 PLIC 的寄存器布局（S7 做）；不做 H 扩展、Smstateen、Sstc、Svnapot 等可选扩展。

**用到的测试：**

- 晋级为 PASS：
  - `rv32si-p-csr`、`rv32si-p-ma_fetch`、`rv32si-p-sbreak`、`rv32si-p-scall`、`rv32si-p-wfi`（后两个必须真正通过：用 `retire.log` 确认确实进入了 S 模式）。
  - `rv32mi-p-illegal`（完整通过）。
- 全部已晋级测试 × 4 个种子无回退。
- 定向测试：第 6 节 S4 部分，这是本阶段的重点。riscv-tests 对中断覆盖很少。

**完成标志：**

- [ ] 上述测试全部 PASS。
- [ ] S4 定向测试全部 PASS，其中定时器中断测试必须连续触发至少 10 次，且每次进入正确的特权级处理程序。
- [ ] 附录 B 的 S4 列与 RTL 逐项一致。
- [ ] `doc/arch/trap.md` 补充委托和中断优先级的说明。

### S5 Sv32 MMU

**目标：** 实现 Sv32 地址翻译、页表遍历、TLB 和页故障，使 `-v` 环境的全部测试可以运行。

**必做内容：**

1. **先做没有 TLB 的串行页表遍历器（PTW）。**
   - 每次访存都遍历页表，协议和权限先做对。
   - PTW 用物理地址、通过 S2 的总线接口读页表，不能递归翻译自己的读取。
   - 读页表时发生总线错误，产生对应访问类型的**访问错误**（1/5/7），而不是页故障。
2. **翻译规则：**
   - 两级页表，支持 4 KiB 页和 4 MiB 超级页。超级页的低位 PPN 不为 0（不对齐的超级页）产生页故障。
   - PTE 合法性：`V=0`，或 `R=0` 且 `W=1`，都视为非法。
   - 权限检查：R/W/X/U，以及 SUM（S 模式访问 U 页）、MXR（可执行页可读）。U 模式访问 U=0 的页、S 模式在 SUM=0 时访问 U=1 的页、S 模式从 U 页取指，都产生页故障。
   - A/D 位按第 3 节软件管理：A=0，或向 D=0 的页写入，产生页故障。
   - `mstatus.MPRV`：M 模式下的数据访存按 `MPP` 指定的特权级翻译。
   - 页故障原因码：取指 12，load 13，store/AMO 15；`tval` 为原始虚拟地址。
3. **生效条件：** `satp.MODE=Sv32` 且当前特权级为 S 或 U 时翻译生效；M 模式始终不翻译（MPRV 情况除外）。
4. **`sfence.vma`：** 第一版忽略地址和 ASID 参数，刷新全部 TLB 项，并冲刷流水线中已经翻译过的取指。ASID 的处理策略写进文档：可以把 ASID 字段实现为可写，但所有 TLB 项一律当作全局对待，`sfence.vma` 时全刷。
5. **加小型 TLB：** 在无 TLB 版本的全部测试通过之后，再加取指和数据各一个小型全相联 TLB（例如 8 项）。用参数开关保留无 TLB 路径作为对照。
6. **与 S2 冲刷规则的配合：** PTW 进行中发生冲刷，按 S2 规则收回未完成的请求。

**边界：** 不做硬件 A/D 更新；不做 Svnapot、Svpbmt；TLB 只做最简单的替换策略；不加 cache。

**用到的测试：**

- 晋级为 PASS：
  - `rv32si-p-dirty`。动手前先读它的 dump：如果它只接受“硬件置 D 位”一种行为，就按 0.4 停下来讨论，不许擅自改 A/D 策略。
  - `rv32ui-v-*`（`ma_data` 除外）、`rv32um-v-*`、`rv32ua-v-*`、`rv32uzba-v-*`、`rv32uzbb-v-*`、`rv32uzbkb-v-*`、`rv32uzbs-v-*`。
- 以上测试在“无 TLB”和“有 TLB”两种配置下各跑一遍，每种配置 × 4 个延迟种子。
- 定向测试：第 6 节 S5 部分。

**完成标志：**

- [ ] 上述测试在两种配置 × 4 个种子下全部 PASS。
- [ ] S5 定向测试全部 PASS。
- [ ] `doc/arch/mmu.md` 写明 PTW 状态机、TLB 结构、`sfence.vma` 的行为、ASID 策略和 A/D 策略。

### S6 阻塞式 I/D cache

**目标：** 加入 I-cache 和 D-cache，同时保证所有可见性规则不被破坏。没有 cache 时访问 DDR 太慢，Linux 实际上跑不起来，所以这一阶段是必需的。

**必做内容：**

1. **I-cache：** 只读，直接映射或 2 路组相联，容量参数化（例如 8 KiB），行大小 16 或 32 字节。
2. **D-cache：** 阻塞式，同样参数化。写策略任选写直达或写回，但必须写进文档；选写回就要处理下面第 4 条。
3. **按地址图划分可缓存性：** 只有 RAM 区域可缓存；所有 MMIO 区域一律绕过 cache，并且每次访问都要实际发到总线上。
4. **可见性：**
   - `fence.i`：写回或排空 D-cache 中的脏数据（写直达则等写缓冲排空），然后使 I-cache 全部失效。
   - PTW 必须读到最新的页表：要么经过 D-cache 读，要么在 D-cache 是写回时保证一致。不得绕过脏的 D-cache 直接读内存。
   - `sfence.vma` 只刷 TLB，不刷 cache。这两者是不同的机制，不要混在一起。
5. **AMO / LR / SC 与 cache 的配合：** 在 D-cache 中完成，或者绕过 cache 并保证一致性，二选一，写进文档。
6. **保留开关：** 用参数保留“无 cache”配置作为对照。

**边界：** 不做非阻塞 cache、不做多个在途 miss、不做预取、不做 L2。

**用到的测试：** 全部已晋级测试，在“cache 开 / 关” × “TLB 开 / 关” × 4 个延迟种子下运行；第 6 节 S6 定向测试。

**完成标志：**

- [ ] 全部组合 PASS。
- [ ] S6 定向测试全部 PASS，其中 MMIO 访问次数由测试台精确计数。
- [ ] `doc/arch/cache.md` 写明组织结构、写策略、各种失效与刷新动作，以及它们和 TLB、PTW 的关系。

### S7 Linux 平台外设对齐

**目标：** 把 PLIC 和 UART 改成 OpenSBI 与 Linux 上游驱动直接能用的布局，避免以后为自定义外设写驱动。

**必做内容：**

1. **PLIC 按 SiFive 布局：**
   - 优先级 `0x0 + 4×id`，pending 在 `0x1000`。
   - 每个上下文的使能寄存器在 `0x2000 + 0x80×ctx`。
   - 每个上下文的阈值寄存器在 `0x200000 + 0x1000×ctx`，claim/complete 在阈值地址 `+4`。
   - 两个上下文：0 为 M（驱动 MEIP），1 为 S（驱动 SEIP）。
   - 源数量和优先级位宽参数化。
2. **UART：** 实现 ns16550A 寄存器子集，可以选择 `reg-shift=2`（4 字节步长）并写进文档。
   - 必须的寄存器：RBR/THR、IER、IIR/FCR、LCR、MCR、LSR，以及 `DLAB=1` 时的 DLL/DLM。
   - LSR 的 THRE/TEMT/DR 位语义要正确。
   - 中断接到 PLIC 的一个源。
   - 旧 UART 删除或保留在单独地址，二选一并写进文档。
3. **旧 timer 外设：** 它的功能已被 CLINT 取代，删除或从地址图中移除。
4. **测试台中的 UART 接收模型：** 在测试台里实现一个 UART 接收器，把 TX 线上的字节解码打印到日志，供定向测试比对字符串。

**边界：** 不改 CPU 核；不加新外设（例如 GPIO 中断、SPI）。

**用到的测试：** 更新后的 `tb_PLIC`、`tb_UART` 单元测试；第 6 节 S7 定向测试；全部回归无回退。

**完成标志：**

- [ ] 外设单元测试和 S7 定向测试全部 PASS，全回归无回退。
- [ ] 附录 C 是最终版；同时写出一份对应的设备树草稿片段 `doc/arch/platform.dts.txt`，只作说明，不参与构建，供下一阶段使用。

### 阶段完成后（不在本文范围）

当 S0–S7 全部完成时，就具备了进入下一阶段的条件：在 Verilator 中运行 OpenSBI 和 Linux 早期启动、可综合的 BRAM 和 AXI 主接口、Zynq PS DDR 集成、上板。届时另写规划。

---

## 6. 自编定向测试清单

riscv-tests 对中断、精确异常副作用、总线错误、MMIO 次数等覆盖不足，需要自己写汇编测试补上。

**写法：**

- 文件放在 `test/asm/<阶段>/<名字>.S`，使用 riscv-tests 的 `-p` 环境宏（`RVTEST_CODE_BEGIN`、`TEST_CASE`、`RVTEST_PASS`、`RVTEST_FAIL`），这样判定机制和 riscv-tests 完全一致。
- 构建方式：给 `W:\riscv-test\build_riscv_tests.py` 增加一个参数（例如 `--extra-src <工作区>\test\asm`），用同样的 `-p` 环境、编译参数、HEX 格式和 ISA 自检，生成 `.hex` 和 `.dump`。产物拷进工作区 `hex/directed/` 并加入 manifest。这个参数在第一个需要定向测试的阶段（S1）开头实现。汇编源码留在工作区，因为它们是本项目自己的测试。
- 需要测试台配合的测试（中断注入、错误注入、计数），通过 plusargs 配置测试台行为，例如 `+IRQ_AT=<周期>`、`+BUSERR_RANGE=<起始>:<结束>`。测试台把统计结果写回一个约定的内存地址，由测试程序自己判断对错。不许在测试台里按测试名写判定逻辑。

| 阶段 | 测试名 | 验证内容 |
| --- | --- | --- |
| S1 | `s1_illegal_sweep` | 遍历未实现 opcode、F/C/Zbc 编码、错误 funct 组合，逐个检查 mcause=2 且 `mtval` 为指令字 |
| S1 | `s1_csr_access` | 写只读 CSR 产生非法指令；`csrrs x0` 读只读 CSR 不陷入；访问不存在的 CSR 产生非法指令 |
| S1 | `s1_misaligned_no_side_effect` | 不对齐的 sw / sh 陷入后，目标附近的内存一个字节都没有变化 |
| S1 | `s1_irq_vs_store` | 测试台在一段连续 store 的不同周期注入外部中断（多个 `+IRQ_AT`），每个 store 的效果恰好出现一次（对 MMIO 的 LED 寄存器计数） |
| S1 | `s1_minstret_exact` | 执行一段已知长度、不含异常的循环，`minstret` 差值精确等于退休指令数；夹入异常和分支误预测后仍然精确 |
| S1 | `s1_mret_plain` | 没有先发生陷入，直接设置 `mepc` 后执行 `mret`，能跳转到目标 |
| S1 | `s1_x0` | 各类指令写 x0 无效，包括 load、CSR 读、乘除法 |
| S2 | `s2_selfmod` | 写入新指令、执行 `fence.i` 后执行到新指令；不执行 `fence.i` 时，规范允许看到旧指令，测试不对这种情况断言 |
| S2 | `s2_bus_error` | 对错误区间做取指、load、store，分别得到 mcause 1/5/7，`mtval` 正确，store 没有产生副作用 |
| S2 | `s2_unmapped` | 访问未映射地址产生访问错误 |
| S2 | `s2_mmio_once` | 对 LED / UART 做 N 次写和读，测试台计数恰好为 N（在多个延迟种子下） |
| S2 | `s2_flush_outstanding` | 在最大延迟下制造“取指请求在途时分支误预测”和“load 在途时陷入”，执行结果正确、不卡死 |
| S3 | `s3_sc_after_store` | LR 后本核对同一地址 store，SC 必须失败并返回 1，且不写入 |
| S3 | `s3_sc_after_trap` | LR 后发生陷入并返回，SC 必须失败 |
| S3 | `s3_amo_mmio` | 对 MMIO 执行 AMO 产生 mcause 7，外设没有收到任何访问 |
| S3 | `s3_amo_misaligned` | 不对齐的 AMO / LR / SC 产生 mcause 6 |
| S4 | `s4_mode_switch` | M→S→U 切换后再陷入返回，每一级读 `mstatus` 和访问特权 CSR 的结果符合规范 |
| S4 | `s4_delegation` | 把 U 模式 ecall（8）、非法指令（2）、断点（3）委托给 S，确认进入 `stvec` 且 `scause`/`sepc`/`stval` 正确；未委托的原因进入 `mtvec`；M 模式自身的异常即使对应位被委托也仍进入 M |
| S4 | `s4_mtimer` | CLINT 定时器连续触发 10 次 M 模式中断，每次重写 `mtimecmp` |
| S4 | `s4_stimer_via_m` | M 模式处理 MTIP 后置位 `mip.STIP`，S 模式收到定时器中断（这是 OpenSBI 的典型做法） |
| S4 | `s4_msip` | 写 CLINT `msip` 触发软件中断，清零后不再触发 |
| S4 | `s4_counteren` | `mcounteren` / `scounteren` 关闭时，S 和 U 读 `cycle`、`time`、`instret` 产生非法指令 |
| S4 | `s4_tw_tsr_tvm` | 三个陷阱位各自生效 |
| S4 | `s4_wfi_wake` | `wfi` 后定时器中断能唤醒并进入处理程序 |
| S5 | `s5_superpage` | 4 MiB 超级页能正常访问；不对齐的超级页产生页故障 |
| S5 | `s5_perm_matrix` | R/W/X/U × S/U 模式 × SUM / MXR 的组合，逐项检查是否故障以及原因码 |
| S5 | `s5_ad_fault` | A=0、D=0 时分别产生对应的页故障，软件置位后重试成功 |
| S5 | `s5_ptw_buserr` | 页表位于错误区间时，产生访问错误而不是页故障 |
| S5 | `s5_sfence` | 修改 PTE 后，执行 `sfence.vma` 前后分别观察到旧映射和新映射 |
| S5 | `s5_mprv` | M 模式下 MPRV=1、MPP=S 时，数据访问按 S 模式翻译 |
| S6 | `s6_selfmod_icache` | 在 I-cache 开启时重复 `s2_selfmod` |
| S6 | `s6_evict` | 访问超过 D-cache 容量的数据并回读，数据正确（写回策略时验证脏行写回） |
| S6 | `s6_pt_update` | 用 store 修改页表，`sfence.vma` 后 PTW 读到的是新值 |
| S6 | `s6_mmio_uncached` | 重复 `s2_mmio_once`，次数精确 |
| S7 | `s7_plic_s_claim` | PLIC 源经 S 上下文触发 SEIP，S 模式完成 claim/complete |
| S7 | `s7_uart16550_tx` | 轮询 LSR 后写 THR 输出字符串，测试台 UART 模型收到的内容一致 |

---

## 7. 通用完成定义与提交检查清单

每个 PR 合并前逐项打勾：

- [ ] `python scripts/regress.py all --seeds 0-3`（S2 前不带 `--seeds`）退出码为 0。PR 里贴汇总表。
- [ ] manifest 中新晋级的测试都列在 PR 描述里，并且每个都亲眼看到过从 FAIL 变成 PASS。
- [ ] 没有任何测试从 `PASS` 降为 `XFAIL`；如果有，附上负责人的书面同意和 `doc/decisions.md` 的条目。
- [ ] 综合检查不新增锁存器或多驱动。
- [ ] 附录和 `doc/arch/` 下受影响的文档已在同一个 PR 里更新。
- [ ] 没有提交 `build/`、波形或日志等生成物；没有提交本机绝对路径或个人信息。

---

## 附录 A：测试清单（按晋级阶段）

“现状”取自 2026-10-21 的基线。S0 之后以 manifest 为准，本表只用于规划。

| 套件 | 测试 | 晋级阶段 | 备注 |
| --- | --- | --- | --- |
| rv32ui-p | 除 `fence_i`、`ma_data`、`ld_st` 外的 39 个 | S0（现已通过） | |
| rv32ui-p | `ld_st` | S0 | 现状是 1000 周期超时，延长超时后判定 |
| rv32ui-p | `fence_i` | S2 | |
| rv32ui-p | `ma_data` | 永久 XFAIL | 设计决策：不对齐访问一律陷入 |
| rv32um-p | 全部 8 个 | S0（现已通过） | |
| rv32mi-p | `csr`、`scall`、`sbreak`、`ma_fetch` | S0（现已通过） | |
| rv32mi-p | `instret_overflow`、`zicntr`、`pmpaddr`、`lh/lw/sh/sw-misaligned` | S0 先记为 PASS，S1 复核 | 疑似空过 |
| rv32mi-p | `mcsr`、`shamt`、`ma_addr`、`breakpoint` | S1 | |
| rv32mi-p | `illegal` | S4 | S1 中失败编号要推进 |
| rv32si-p | `scall`、`wfi` | S0 先记为 PASS，S4 复核 | 疑似空过 |
| rv32si-p | `csr`、`ma_fetch`、`sbreak` | S4 | |
| rv32si-p | `dirty` | S5 | 先确认它对 A/D 策略的要求 |
| rv32ua-p | 全部 10 个 | S3 | |
| rv32uzba-p、uzbkb-p | 全部 | S0（现已通过） | |
| rv32uzbb-p | 除 `clz`、`ctz`、`rol`、`ror`、`rori` 外的 13 个 | S0（现已通过） | |
| rv32uzbb-p | `clz`、`ctz`、`rol`、`ror`、`rori` | S1 | |
| rv32uzbs-p | 除 `bseti` 外的 7 个 | S0（现已通过） | |
| rv32uzbs-p | `bseti` | S1 | |
| rv32ui/um/ua/uzba/uzbb/uzbkb/uzbs-v | 全部（`ma_data` 除外） | S5 | 需用 S0 重新生成的镜像 |
| rv32uf/ud/uzfh/uc/uzbc/uzbkx | 全部 | 不在本阶段范围 | 不进 manifest；相关编码由 `s1_illegal_sweep` 保证会陷入 |

## 附录 B：CSR 演进表

“—”表示该阶段不存在（访问产生非法指令）；“RO0”表示只读 0；“✓”表示按规范完整实现。

| CSR | 地址 | 现状 | S1 | S4 | S5 |
| --- | --- | --- | --- | --- | --- |
| `mstatus` | 0x300 | 32 位全部可写 | ✓（MIE、MPIE、MPP 固定为 11） | ✓（加 SIE、SPIE、SPP、MPRV、SUM、MXR、TVM、TW、TSR） | 同 S4 |
| `mstatush` | 0x310 | — | RO0 | RO0 | RO0 |
| `misa` | 0x301 | 读 0 | 0x4000_1100（S3 后为 0x4000_1101） | 0x4014_1101 | 同 S4 |
| `medeleg` / `mideleg` | 0x302 / 0x303 | — | — | ✓ | ✓ |
| `mie` / `mip` | 0x304 / 0x344 | 只有 MEIE 起作用，`mip` 不由硬件驱动 | ✓（只有 MEIP 有来源） | ✓（全部 6 个中断位） | ✓ |
| `mtvec` | 0x305 | 不做 WARL | ✓（Direct 模式） | ✓ | ✓ |
| `mcounteren` | 0x306 | — | — | ✓ | ✓ |
| `mcountinhibit` | 0x320 | — | ✓（CY、IR） | ✓ | ✓ |
| `mscratch` / `mepc` / `mcause` / `mtval` | 0x340–0x343 | 有，不做 WARL | ✓ | ✓ | ✓ |
| `mcycle(h)` / `minstret(h)` | 0xB00/0xB80、0xB02/0xB82 | — | ✓（64 位，真实退休计数） | ✓ | ✓ |
| `cycle(h)` / `instret(h)` | 0xC00/0xC80、0xC02/0xC82 | 32 位，`instret` 为估算 | ✓（只读影子） | ✓（受 counteren 控制） | ✓ |
| `time(h)` | 0xC01 / 0xC81 | — | — | ✓（读 CLINT `mtime`） | ✓ |
| `mvendorid` / `marchid` / `mimpid` / `mhartid` | 0xF11–0xF14 | 可写 | RO0 | RO0 | RO0 |
| `mconfigptr` | 0xF15 | — | RO0 | RO0 | RO0 |
| `menvcfg(h)` | 0x30A / 0x31A | — | — | RO0 | RO0 |
| `pmpcfg0-3` / `pmpaddr0-15` | 0x3A0– / 0x3B0– | — | RO0 | RO0 | RO0 |
| `tselect` / `tdata1-3` / `tinfo` | 0x7A0–0x7A4 | — | ✓（无触发器） | 同 S1 | 同 S1 |
| `sstatus` / `sie` / `sip` | 0x100 / 0x104 / 0x144 | — | — | ✓（`mstatus` / `mie` / `mip` 的视图） | ✓ |
| `stvec` / `scounteren` / `sscratch` / `sepc` / `scause` / `stval` | 0x105 / 0x106 / 0x140–0x143 | — | — | ✓ | ✓ |
| `senvcfg` | 0x10A | — | — | RO0 | RO0 |
| `satp` | 0x180 | — | — | 只存储，不生效 | ✓（Sv32） |

## 附录 C：地址图（S2 起生效，S7 定稿）

| 区域 | 起始地址 | 大小 | 可缓存 | 说明 |
| --- | --- | --- | --- | --- |
| CLINT | 0x0200_0000 | 64 KiB | 否 | `msip` 在 +0x0，`mtimecmp(h)` 在 +0x4000 / +0x4004，`mtime(h)` 在 +0xBFF8 / +0xBFFC（S4） |
| PLIC | 0x0C00_0000 | 64 MiB | 否 | S2 起迁到此基址；S7 改为 SiFive 布局 |
| UART | 0x1000_0000 | 4 KiB | 否 | S2 迁到此处时仍是旧寄存器布局；S7 改为 16550 |
| LED / IO | 0x1000_1000 | 4 KiB | 否 | 原 IO 寄存器，定向测试用来计数 |
| 旧 timer | 0x1000_2000 | 4 KiB | 否 | S4 由 CLINT 取代，S7 移除 |
| RAM | 0x8000_0000 | 1 MiB（参数化） | 是 | 复位 PC 在此；`tohost` 也在此区间内，由测试台监视 |
| 其他 | — | — | — | 访问产生访问错误异常 |

这个地址图与 QEMU `virt` 平台的主要设备位置一致，便于以后直接复用 OpenSBI 通用平台和设备树。
