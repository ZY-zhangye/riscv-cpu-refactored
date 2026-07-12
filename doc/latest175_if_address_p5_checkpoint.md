# latest175 P4 实现分析与 IF 地址路径 P5

## P4 实现基线

报告目录：

```text
vivado-project/jyd2025-reference/artifacts/latest175_p4
```

器件为 `xc7k325tffg900-2`，CPU 时钟约束为 `175 MHz`。这是完整综合、布局布线结果，未生成 bitstream。

| 指标 | P4 |
| --- | ---: |
| WNS | -1.004 ns |
| TNS | -392.473 ns |
| Setup failing endpoints | 1207 / 29079 |
| LUT | 13860 |
| FF | 15125 |
| LUTRAM | 362 |
| BRAM | 72 |
| DSP | 8 |

三份 BTB payload 已按预期推断为分布式 RAM：

```text
bp_mem_update_reg   RAM128X1S x 58
bp_mem_lookup0_reg  RAM64M x 40
bp_mem_lookup1_reg  RAM64M x 40
```

## P4 前 20 条实现路径

前 20 条路径分成两组：

| 路径组 | 数量 | 最差 slack |
| --- | ---: | ---: |
| `fs_pc -> bp_mem_lookup1 -> IROM1 address` | 13 | -1.004 ns |
| DRAM BRAM read -> MEM load select -> EX/WB register | 7 | -0.907 ns |

P4 最差路径为：

```text
u_if_stage/fs_pc_reg[3]
  -> lane1 BTB index increment
  -> bp_mem_lookup1 RAMD64E
  -> lane1 tag hit / prediction select
  -> lane1 fetch-address increment
  -> u_irom1 RAMB36E1/ADDRARDADDR[13]
```

```text
Data path   6.125 ns
Logic       1.745 ns
Route       4.380 ns
Logic levels       14
Slack      -1.004 ns
```

该路径已不包含 IROM data 到 RAS 再反馈 IROM address 的闭环。新的主要问题是：

1. `fs_pc_reg[3]` 的综合网扇出约 187，同时驱动 Issue packet、BTB index/tag 和顺序 PC 逻辑；
2. lane1 BTB lookup 仍需要 word-PC `+1`；
3. IROM 实际只消费 `addr[13:2]`，但原 RTL 的 `pc_out1 = next_pc + 32'd4` 允许综合器形成宽地址加法链。

## P5 RTL 修改

文件：`rtl/cpu_top/if_stage.sv`

P5 不增加流水级，不改变 BTB/RAS 容量、预测语义或 redirect 延迟。

### fs_pc 扇出约束

在 `fs_pc` 寄存器上增加：

```systemverilog
(* max_fanout = 32 *) logic [31:0] fs_pc;
```

目的是允许 Vivado 在 BTB LUTRAM 附近复制源寄存器，避免单根高扇出 PC 网跨越 IF packet 和预测器区域。下一轮实现需要从综合网表确认复制是否发生，不能只依赖属性存在。

### lane1 BTB 地址窄化

lane1 BTB RAM 地址只对低 `BP_INDEX_WIDTH` 位执行 word `+1`，并显式把 index 溢出作为 tag 的进位。该变换与原来的完整 word-PC `+1` 等价，但 RAM 地址不再依赖完整 30-bit word 加法结果。

### lane1 IROM word 地址窄化

IROM XPM 端口宽度为 12 bit，实际连接 `addr[13:2]`。P5 将 lane1 的 BRAM 地址计算改为：

```systemverilog
imem_word_addr1 = next_pc[13:2] + 12'd1;
```

高地址进位另行重建，以保持 32-bit `pc_out1` 与 `next_pc + 4` 等价；BRAM 地址路径只经过 12-bit word increment。

## Questa 验证

完整 RTL/testbench 编译：`Errors 0, Warnings 0`。

通过：

```text
tb_if_ras_recovery
tb_issue_stage
tb_multi_issue_l2
tb_multi_issue_l3
tb_perf_counters
tb_mem_commit
tb_mul_special
tb_my_cpu
```

L3 微基准保持：

```text
cycles   30
instret  34
```

九窗口 benchmark 与 P4 完全一致：

```text
cycles       1,790,178
instret      2,279,455
IPC              1.273
sink        0x9D3BF787
exceptions           0
```

## 下一轮实现检查

1. 确认 `bp_mem_lookup0/1/update` 仍推断为 LUTRAM；
2. 确认 `fs_pc` 是否出现 predictor-local register replica，最差网扇出是否下降；
3. 检查 `fs_pc -> bp_mem_lookup1 -> IROM1` 的逻辑级数、route delay 和 WNS；
4. 检查前 20 是否迁移到 DRAM read 路径；
5. 若 DRAM 成为最差路径，优先处理外设读回 mux 和 MEM load-data selection，再评估是否需要 load response 寄存边界；
6. 若 IF 仍差接近 1 ns，再进入真正的 fetch request/address 寄存拆分。该方案会增加一次取指响应阶段，需要单独验证 redirect、stall 和 IPC，不与本轮无延迟改写混在一起。

本阶段未运行 Vivado。
