# RISC-V Z 扩展总结：zba / zbb / zbc / zbs / zbkb / zbkx

本文用于后续在当前 RV32 CPU 中添加比赛现场可能抽选的 Z 扩展指令。

参考来源：

- RISC-V Unprivileged ISA Specification, Chapter 30, "B" Extension for Bit Manipulation, Version 1.0.0
  - https://docs.riscv.org/reference/isa/unpriv/b-st-ext.html
- RISC-V Unprivileged ISA Specification, Chapter 32, Scalar Cryptography Extensions, Version 1.0.1
  - https://docs.riscv.org/reference/isa/v20240411/unpriv/scalar-crypto.html

## 总体结论

比赛文档给出的现场添加范围是：

- zba：地址生成
- zbb：基础位操作
- zbc：无进位乘法
- zbs：单 bit 操作
- zbkb：密码学常用位操作
- zbkx：交叉置换

当前设计是 RV32，因此只需要关注 RV32 可用指令。RV64-only 指令可以先忽略。

如果只看 RV32，六类扩展合并后约有 39 条唯一指令需要纳入候选池。它们大部分可以复用现有 ALU 路径；`clmul*` 类更接近乘法单元；`zip/unzip/xperm*` 更适合单独组合逻辑模块。

## RV32 指令总表

| 扩展 | RV32 需要关注的指令 | 主要硬件类型 |
|---|---|---|
| zba | `sh1add`, `sh2add`, `sh3add` | 移位加法 |
| zbb | `andn`, `orn`, `xnor`, `clz`, `ctz`, `cpop`, `max`, `maxu`, `min`, `minu`, `sext.b`, `sext.h`, `zext.h`, `rol`, `ror`, `rori`, `orc.b`, `rev8` | ALU 位操作 |
| zbc | `clmul`, `clmulh`, `clmulr` | carry-less multiply |
| zbs | `bclr`, `bclri`, `bext`, `bexti`, `binv`, `binvi`, `bset`, `bseti` | 单 bit mask 操作 |
| zbkb | `andn`, `orn`, `xnor`, `pack`, `packh`, `brev8`, `rev8`, `rol`, `ror`, `rori`, `zip`, `unzip` | 密码学位操作 |
| zbkx | `xperm4`, `xperm8` | nibble/byte lookup |

注意：

- `zbb` 和 `zbkb` 有重叠：`andn`, `orn`, `xnor`, `rev8`, `rol`, `ror`, `rori`。
- `zbc` 与 `zbkc` 有重叠，但比赛范围写的是 `zbc`，此处不单独总结 `zbkc`。
- `.uw` 指令和 `*w` 指令基本是 RV64 相关，当前 RV32 CPU 可以不实现。

## RV32 每条指令格式速查

这里的“指令格式”指后续实现译码时最直接需要用到的汇编/操作数字段格式，而不是完整二进制编码表。完整编码实现时建议对抽中的指令再回查官方 encoding 表。

常见格式：

- R 型二源格式：`op rd, rs1, rs2`
- I 型立即数格式：`op rd, rs1, shamt`
- 一元寄存器格式：`op rd, rs`
- 一元指令通常仍编码在 OP-IMM 或 OP 类指令空间里，只是汇编层只显式使用一个源寄存器。

| 扩展 | 指令 | 汇编格式 | 格式类别 | 操作数说明 |
|---|---|---|---|---|
| zba | `sh1add` | `sh1add rd, rs1, rs2` | R 型二源 | `rd = (rs1 << 1) + rs2` |
| zba | `sh2add` | `sh2add rd, rs1, rs2` | R 型二源 | `rd = (rs1 << 2) + rs2` |
| zba | `sh3add` | `sh3add rd, rs1, rs2` | R 型二源 | `rd = (rs1 << 3) + rs2` |
| zbb/zbkb | `andn` | `andn rd, rs1, rs2` | R 型二源 | 第二源取反后 AND |
| zbb/zbkb | `orn` | `orn rd, rs1, rs2` | R 型二源 | 第二源取反后 OR |
| zbb/zbkb | `xnor` | `xnor rd, rs1, rs2` | R 型二源 | XOR 后整体取反 |
| zbb | `clz` | `clz rd, rs` | 一元寄存器 | 统计前导 0 |
| zbb | `ctz` | `ctz rd, rs` | 一元寄存器 | 统计尾随 0 |
| zbb | `cpop` | `cpop rd, rs` | 一元寄存器 | 统计置位 bit 数 |
| zbb | `max` | `max rd, rs1, rs2` | R 型二源 | 有符号最大值 |
| zbb | `maxu` | `maxu rd, rs1, rs2` | R 型二源 | 无符号最大值 |
| zbb | `min` | `min rd, rs1, rs2` | R 型二源 | 有符号最小值 |
| zbb | `minu` | `minu rd, rs1, rs2` | R 型二源 | 无符号最小值 |
| zbb | `sext.b` | `sext.b rd, rs` | 一元寄存器 | byte 符号扩展 |
| zbb | `sext.h` | `sext.h rd, rs` | 一元寄存器 | halfword 符号扩展 |
| zbb | `zext.h` | `zext.h rd, rs` | 一元寄存器 | halfword 零扩展 |
| zbb/zbkb | `rol` | `rol rd, rs1, rs2` | R 型二源 | 左旋，旋转量来自 `rs2[4:0]` |
| zbb/zbkb | `ror` | `ror rd, rs1, rs2` | R 型二源 | 右旋，旋转量来自 `rs2[4:0]` |
| zbb/zbkb | `rori` | `rori rd, rs1, shamt` | I 型立即数 | 右旋，旋转量来自 `shamt[4:0]` |
| zbb | `orc.b` | `orc.b rd, rs` | 一元寄存器 | 每个 byte 非零则输出 `8'hff` |
| zbb/zbkb | `rev8` | `rev8 rd, rs` | 一元寄存器 | byte 顺序反转 |
| zbc | `clmul` | `clmul rd, rs1, rs2` | R 型二源 | carry-less multiply low |
| zbc | `clmulh` | `clmulh rd, rs1, rs2` | R 型二源 | carry-less multiply high |
| zbc | `clmulr` | `clmulr rd, rs1, rs2` | R 型二源 | carry-less multiply reversed |
| zbs | `bclr` | `bclr rd, rs1, rs2` | R 型二源 | 清除 `rs2[4:0]` 指定 bit |
| zbs | `bclri` | `bclri rd, rs1, shamt` | I 型立即数 | 清除 `shamt[4:0]` 指定 bit |
| zbs | `bext` | `bext rd, rs1, rs2` | R 型二源 | 提取 `rs2[4:0]` 指定 bit |
| zbs | `bexti` | `bexti rd, rs1, shamt` | I 型立即数 | 提取 `shamt[4:0]` 指定 bit |
| zbs | `binv` | `binv rd, rs1, rs2` | R 型二源 | 翻转 `rs2[4:0]` 指定 bit |
| zbs | `binvi` | `binvi rd, rs1, shamt` | I 型立即数 | 翻转 `shamt[4:0]` 指定 bit |
| zbs | `bset` | `bset rd, rs1, rs2` | R 型二源 | 置位 `rs2[4:0]` 指定 bit |
| zbs | `bseti` | `bseti rd, rs1, shamt` | I 型立即数 | 置位 `shamt[4:0]` 指定 bit |
| zbkb | `pack` | `pack rd, rs1, rs2` | R 型二源 | 拼接两个低 16 bit |
| zbkb | `packh` | `packh rd, rs1, rs2` | R 型二源 | 拼接两个低 8 bit，高位补 0 |
| zbkb | `brev8` | `brev8 rd, rs` | 一元寄存器 | 每个 byte 内 bit 反转 |
| zbkb | `zip` | `zip rd, rs` | 一元寄存器 | bit interleave |
| zbkb | `unzip` | `unzip rd, rs` | 一元寄存器 | bit deinterleave |
| zbkx | `xperm4` | `xperm4 rd, rs1, rs2` | R 型二源 | nibble 查表置换 |
| zbkx | `xperm8` | `xperm8 rd, rs1, rs2` | R 型二源 | byte 查表置换 |

## 建议火力覆盖候选集

赛事方如果会从该集合中抽 9 条，且现场只要求实现其中 1 条，建议提前覆盖“实现成本低、时序扰动小、容易一次写对”的大集合。目标不是把所有重逻辑都塞进现有 ALU 关键路径，而是让绝大多数可能抽中的简单指令已经有现成路径。

### A 档：建议优先实现，低时序风险，覆盖 28 条

这些指令大多是固定移位加法、简单逻辑、比较选择、符号扩展、单 bit mask 或纯重排。放入独立 `bitmanip_unit` 后，只在 EXE 结果 mux 增加一路选择，对原有 ALU 路径影响相对可控。

| 类别 | 指令 |
|---|---|
| zba 固定移位加法 | `sh1add`, `sh2add`, `sh3add` |
| 取反逻辑 | `andn`, `orn`, `xnor` |
| min/max | `min`, `max`, `minu`, `maxu` |
| 扩展 | `sext.b`, `sext.h`, `zext.h` |
| byte/bit 重排简单类 | `orc.b`, `rev8`, `brev8`, `pack`, `packh`, `zip`, `unzip` |
| zbs 全部单 bit 类 | `bclr`, `bclri`, `bext`, `bexti`, `binv`, `binvi`, `bset`, `bseti` |

为什么优先：

- 很多是纯 LUT/连线/固定移位，功能验证简单。
- `zbs` 的 8 条共享同一个 `mask = 32'b1 << idx` 逻辑，投入一次能覆盖 8 条。
- `pack/packh/rev8/brev8` 是纯重排，几乎不引入算术长链。
- `zip/unzip` 比 `pack` 稍容易写错，但仍是固定 bit permutation，不需要加法器或乘法器。

### B 档：可继续覆盖，时序中等，额外覆盖 6 条

| 类别 | 指令 |
|---|---|
| 旋转 | `rol`, `ror`, `rori` |
| 计数 | `clz`, `ctz`, `cpop` |

说明：

- 当前 CPU 已有变量移位，旋转可以复用类似 shifter 思路，但需要两个移位结果 OR 在一起。
- `clz/ctz` 是优先编码器，`cpop` 是加法树，功能不难，但组合深度比 A 档更明显。
- 如果综合时序紧，可以把 B 档放在独立模块，并用综合约束/层次观察它是否成为 EXE 关键路径。

### C 档：不建议为“火力覆盖”优先做，重逻辑，覆盖 5 条

| 类别 | 指令 |
|---|---|
| carry-less multiply | `clmul`, `clmulh`, `clmulr` |
| crossbar permutation | `xperm4`, `xperm8` |

原因：

- `clmul*` 是 32 级 GF(2) 部分积 XOR 逻辑，和普通乘法不同，若组合实现很容易成为长路径。
- `xperm4/xperm8` 是多路查表 mux，`xperm8` 尤其容易形成较宽选择网络。
- 如果确实抽中这些，建议现场单独加针对性实现；提前全覆盖会增加验证和时序压力。

### 推荐策略

实际火力覆盖建议：

1. 先实现 A 档 28 条。
2. 若回归和综合时序仍稳，再加入 B 档 6 条。
3. 暂不主动加入 C 档 5 条，除非赛事练习样例或现场提示显示倾向抽这些。

这样最多可提前覆盖 34 条 RV32 候选指令，同时避开最可能冲击 EXE 时序的 5 条重逻辑指令。

## zba：Address Generation

用途：加速数组寻址，形式是 `(rs1 << N) + rs2`。

RV32 指令：

| 指令 | 语义 |
|---|---|
| `sh1add rd, rs1, rs2` | `rd = (rs1 << 1) + rs2` |
| `sh2add rd, rs1, rs2` | `rd = (rs1 << 2) + rs2` |
| `sh3add rd, rs1, rs2` | `rd = (rs1 << 3) + rs2` |

RV32 可忽略：

- `add.uw`
- `sh1add.uw`
- `sh2add.uw`
- `sh3add.uw`
- `slli.uw`

实现提示：

- 最适合直接扩展 ALU。
- 对时序友好，移位量固定为 1/2/3，再走 32 位加法器。
- 可复用当前 `exe_stage` 的 `alu_result` 路径。

## zbb：Basic Bit-Manipulation

用途：基础位操作、计数、旋转、扩展、min/max、字节反转等。

### 逻辑取反类

| 指令 | 语义 |
|---|---|
| `andn rd, rs1, rs2` | `rd = rs1 & ~rs2` |
| `orn rd, rs1, rs2` | `rd = rs1 | ~rs2` |
| `xnor rd, rs1, rs2` | `rd = ~(rs1 ^ rs2)` |

实现提示：纯组合逻辑，最容易加。

### 计数类

| 指令 | 语义 |
|---|---|
| `clz rd, rs` | 从 MSB 开始统计连续 0 的个数 |
| `ctz rd, rs` | 从 LSB 开始统计连续 0 的个数 |
| `cpop rd, rs` | 统计 1 的个数，也叫 popcount |

边界：

- 输入为 0 时，`clz` 和 `ctz` 返回 XLEN，也就是 RV32 返回 32。
- `cpop(0)` 返回 0。

实现提示：

- `clz/ctz` 可以用优先编码器。
- `cpop` 可以用加法树。
- 如果现场只抽一条，先写直接组合逻辑即可；后续再考虑平衡树优化时序。

### min/max 类

| 指令 | 语义 |
|---|---|
| `min rd, rs1, rs2` | 有符号最小值 |
| `max rd, rs1, rs2` | 有符号最大值 |
| `minu rd, rs1, rs2` | 无符号最小值 |
| `maxu rd, rs1, rs2` | 无符号最大值 |

实现提示：

- 可复用已有 `slt/sltu` 比较逻辑。
- 有符号比较要注意符号位不同的情况。

### 符号/零扩展类

| 指令 | 语义 |
|---|---|
| `sext.b rd, rs` | `rd = sign_extend(rs[7:0])` |
| `sext.h rd, rs` | `rd = sign_extend(rs[15:0])` |
| `zext.h rd, rs` | `rd = zero_extend(rs[15:0])` |

实现提示：纯连线，适合放入 ALU。

### 旋转类

| 指令 | 语义 |
|---|---|
| `rol rd, rs1, rs2` | 左旋，旋转量 `rs2[4:0]` |
| `ror rd, rs1, rs2` | 右旋，旋转量 `rs2[4:0]` |
| `rori rd, rs1, shamt` | 立即数右旋，旋转量 `shamt[4:0]` |

公式：

- `rol(x, s) = (x << s) | (x >> (32 - s))`
- `ror(x, s) = (x >> s) | (x << (32 - s))`

实现注意：

- `s = 0` 时不能让右移/左移量变成 32 后产生工具差异。推荐写成：
  - `s == 0 ? x : ((x << s) | (x >> (32 - s)))`
  - `s == 0 ? x : ((x >> s) | (x << (32 - s)))`

### 字节类

| 指令 | 语义 |
|---|---|
| `orc.b rd, rs` | 对每个 byte：如果该 byte 非 0，输出 `8'hff`；否则输出 `8'h00` |
| `rev8 rd, rs` | 字节顺序反转。RV32 下 `rd = {rs[7:0], rs[15:8], rs[23:16], rs[31:24]}` |

实现提示：

- `orc.b` 是 4 个 byte 并行判断。
- `rev8` 是纯字节重排。

RV32 可忽略：

- `clzw`
- `ctzw`
- `cpopw`
- `rolw`
- `rorw`
- `roriw`

## zbc：Carry-Less Multiplication

用途：GF(2) 多项式乘法，常用于 CRC 和密码学。

RV32 指令：

| 指令 | 语义 |
|---|---|
| `clmul rd, rs1, rs2` | 无进位乘法结果的低 32 位 |
| `clmulh rd, rs1, rs2` | 无进位乘法结果的高 32 位，偏高位版本 |
| `clmulr rd, rs1, rs2` | reversed high-part，用于某些 CRC/多项式算法 |

核心思想：

普通乘法的加法用进位加法；carry-less multiply 的“加法”是 XOR。

可用伪代码：

```text
product = 0[63:0]
for i in 0..31:
    if rs2[i] == 1:
        product ^= zero_extend(rs1) << i
```

结果选择建议：

- `clmul`: `rd = product[31:0]`
- `clmulh`: 等价于规范高位选择，注意不是简单无符号乘法高位
- `clmulr`: reversed variant，建议实现时直接按规范伪代码写测试对齐

实现提示：

- 不要复用现有普通 `mul` 的 `*` 结果，语义不同。
- 可以先做 32 级 XOR/AND 组合逻辑，功能最直接。
- 如果时序紧张，再做多周期或分层 XOR tree。

## zbs：Single-Bit Instructions

用途：单 bit 清除、提取、翻转、置位。

寄存器版本：

| 指令 | 语义 |
|---|---|
| `bclr rd, rs1, rs2` | `rd = rs1 & ~(1 << rs2[4:0])` |
| `bext rd, rs1, rs2` | `rd = zero_extend(rs1[rs2[4:0]])` |
| `binv rd, rs1, rs2` | `rd = rs1 ^ (1 << rs2[4:0])` |
| `bset rd, rs1, rs2` | `rd = rs1 | (1 << rs2[4:0])` |

立即数版本：

| 指令 | 语义 |
|---|---|
| `bclri rd, rs1, shamt` | `rd = rs1 & ~(1 << shamt[4:0])` |
| `bexti rd, rs1, shamt` | `rd = zero_extend(rs1[shamt[4:0]])` |
| `binvi rd, rs1, shamt` | `rd = rs1 ^ (1 << shamt[4:0])` |
| `bseti rd, rs1, shamt` | `rd = rs1 | (1 << shamt[4:0])` |

实现提示：

- 先生成 `mask = 32'b1 << index`。
- `bext/bexti` 输出只有 bit0 可能为 1，其余位为 0。
- 这些指令适合放入 ALU，逻辑简单。

## zbkb：Bit-Manipulation for Cryptography

用途：密码学中常见的位操作，包括旋转、取反逻辑、打包、bit/byte 反转、交织/解交织。

RV32 指令：

| 指令 | 语义 |
|---|---|
| `andn` | 同 zbb |
| `orn` | 同 zbb |
| `xnor` | 同 zbb |
| `rol` | 同 zbb |
| `ror` | 同 zbb |
| `rori` | 同 zbb |
| `rev8` | 同 zbb |
| `pack rd, rs1, rs2` | 取 `rs1[15:0]` 和 `rs2[15:0]` 拼成 32 位 |
| `packh rd, rs1, rs2` | 取 `rs1[7:0]` 和 `rs2[7:0]` 拼到低 16 位，高位补 0 |
| `brev8 rd, rs` | 每个 byte 内部 bit 反转 |
| `zip rd, rs` | bit interleave，用于把低/高半部分 bit 交织 |
| `unzip rd, rs` | bit deinterleave，是 `zip` 的逆操作 |

`pack` / `packh` 语义：

```text
pack  = {rs2[15:0], rs1[15:0]}
packh = {16'b0, rs2[7:0], rs1[7:0]}
```

`brev8` 语义：

```text
for each byte:
    out[i+7:i] = reverse_bits(in[i+7:i])
```

`zip/unzip` 实现提示：

- 这两个比 `pack` 类更容易写错，建议先用明确的 bit-by-bit 循环式组合逻辑。
- 后续如果要优化，可以改成分层 bit shuffle。

RV32 可忽略：

- `packw`
- `rolw`
- `rorw`
- `roriw`

## zbkx：Crossbar Permutations

用途：寄存器内小查找表，常用于常数时间 S-box/置换。

RV32 指令：

| 指令 | 语义 |
|---|---|
| `xperm4 rd, rs1, rs2` | 以 nibble 为粒度查表 |
| `xperm8 rd, rs1, rs2` | 以 byte 为粒度查表 |

`xperm4`：

- `rs1` 是 8 个 4-bit 元素组成的查找表。
- `rs2` 是 8 个 4-bit index。
- 对每个 nibble：
  - 如果 index < 8，输出 `rs1[index]`
  - 否则输出 0

伪代码：

```text
for i in 0..7:
    idx = rs2[4*i +: 4]
    if idx < 8:
        rd[4*i +: 4] = rs1[4*idx +: 4]
    else:
        rd[4*i +: 4] = 0
```

`xperm8`：

- `rs1` 是 4 个 8-bit 元素组成的查找表。
- `rs2` 是 4 个 8-bit index。
- 对每个 byte：
  - 如果 index < 4，输出 `rs1[index]`
  - 否则输出 0

伪代码：

```text
for i in 0..3:
    idx = rs2[8*i +: 8]
    if idx < 4:
        rd[8*i +: 8] = rs1[8*idx +: 8]
    else:
        rd[8*i +: 8] = 0
```

实现提示：

- 这是组合查表 mux，不建议塞进已有普通 ALU case 太深。
- 可以单独做 `bitmanip_unit`，再由 EXE result mux 选择。

## 对当前 CPU 的实现建议

当前设计里，指令译码集中在：

- `rtl/cpu_top/id_stage.sv`

执行集中在：

- `rtl/cpu_top/exe_stage.sv`

建议新增一个专用包：

```text
ZB_PACKET:
    zb_op
    zb_src1
    zb_src2_or_imm
    zb_is_imm
```

也可以先不改总线结构，直接扩展现有 ALU packet，但要注意：

- 现有 `ALU_PACKET_WIDTH` 只有 10 bit，已经对应 10 个基础 ALU op。
- 如果硬塞所有 Z 指令，宽度会明显膨胀。
- 更稳妥的方式是新增 `BITMANIP_PACKET_WIDTH`，在 `DS_ES_WIDTH` 中追加。

推荐分阶段实现：

1. 第一优先级：zba + zbs + zbb 简单逻辑类
   - `sh1add/sh2add/sh3add`
   - `andn/orn/xnor`
   - `sext.b/sext.h/zext.h`
   - `min/max/minu/maxu`
   - `bset/bclr/binv/bext` 及立即数版本
2. 第二优先级：zbb 计数/旋转/字节类
   - `clz/ctz/cpop`
   - `rol/ror/rori`
   - `orc.b/rev8`
3. 第三优先级：zbkb 额外指令
   - `pack/packh/brev8/zip/unzip`
4. 第四优先级：zbc/zbkx
   - `clmul/clmulh/clmulr`
   - `xperm4/xperm8`

## RV32 可忽略清单

这些指令不是当前 RV32 核心的重点：

- zba RV64-only：`add.uw`, `sh1add.uw`, `sh2add.uw`, `sh3add.uw`, `slli.uw`
- zbb RV64-only：`clzw`, `ctzw`, `cpopw`, `rolw`, `rorw`, `roriw`
- zbkb RV64-only：`packw`, `rolw`, `rorw`, `roriw`

## 后续实现时的检查清单

- 译码是否区分 OP / OP-IMM / 单操作数伪二操作数编码。
- 立即数版本是否只取 `shamt[4:0]`。
- `x0` 写回是否仍由 regfile 层屏蔽。
- 旋转量为 0 时是否返回原值。
- `clz/ctz` 输入为 0 时是否返回 32。
- `bext/bexti` 是否只写 bit0。
- `rev8/brev8/pack/packh/zip/unzip/xperm*` 是否有小型 directed test。
- 是否避免把过多组合逻辑放入当前 EXE 关键路径。
