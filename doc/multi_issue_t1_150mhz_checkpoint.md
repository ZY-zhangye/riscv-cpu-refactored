# 顺序多发 T1 150 MHz 压力路径优化检查点

## 输入报告

- 基线 RTL：L3K `6760658`；
- 报告目录：`vivado-project/jyd2025-reference/reports/L3K_6760658_150MHz_stress`；
- 目标周期：6.667 ns（150 MHz）；
- setup WNS -0.800 ns、TNS -481.135 ns、失败端点 1,357 / 40,067；
- 路由完成，压力结果仅用于定位，不替代 125/130 MHz 已签核基线。

## 前 20 条路径归因

前 20 条路径不再只由 DRAM `WEA` 主导，而是形成两个明确路径簇。

### Issue queue flush 扇出

最差路径从 EX lane0 的分支/JALR 计算出发，经 `br_redirect`、IF
`fetch_kill` 和 issue 容量控制，终止于 `queue1~queue3` payload 或
`queue_info*` 的 CE：

- WNS -0.800 ns；
- 数据路径约 6.843 ns；
- 17~18 级逻辑；
- 路由约占 75%。

虽然原 RTL 在 flush 时已不清零 payload，但整个队列更新仍放在
`if (global_flush) ... else ...` 下。综合器因此仍把 redirect 接入所有宽
payload、预译码和 tag 寄存器的 CE/D 锥。

本次修改让 payload 更新无条件执行普通的消费/入队状态转移。flush 周期
`lane*_fire` 与 `packet_accept` 已经为零，payload 会自然保持；只有
`queue_count` 和下一包 tag 被清零。这样不改变队列有效性语义，同时把
redirect 从宽队列寄存器更新锥中移除。

### DRAM WEA 地址译码

代表路径终止于 DRAM BRAM `WEA[0]`：

- WNS -0.775 ns；
- 数据路径 6.616 ns；
- 11 级逻辑；
- 路由占 84.689%。

板级 `perip_bridge` 使用两个通用 32-bit 上下界比较器识别
`0x8010_0000~0x8013_FFFF`，比较结果直接进入 `dram_wen`。该窗口是
256 KiB 对齐范围，可直接用 `perip_addr[31:18] == 14'b1000_0000_0001_00`
译码。本次同时将读请求、写请求和延迟读返回选择改为该高位译码，保持
BRAM 地址、数据和访问周期不变。

## 验证

- 全 RTL/testbench 编译：Errors 0、Warnings 0；
- 板级 `perip_bridge`、`display_seg`、`counter` 编译：Errors 0、Warnings 0；
- `tb_issue_stage`：通过；
- `tb_mem_commit`：通过；
- `tb_multi_issue_l2`：通过；
- `tb_multi_issue_l3`：通过，27 cycles、34 instret、IPC 1.259；
- `tb_perf_counters`：通过；
- `tb_dram_driver`：通过。

本机 Vivado 2023.2 重建 150 MHz 综合检查点时，流程在生成
`blk_mem_gen_0` 的 VHDL synthesis wrapper 阶段失败，尚未进入 RTL
综合。因此本检查点只证明功能回归和路径结构优化成立，150 MHz 是否签核
仍以后续重新综合、布局布线结果为准。

## 下一步

1. 用本提交重新生成 L3K 150 MHz post-synthesis checkpoint；
2. 运行 `impl_stress_fast.tcl l3k150`，确认 issue queue CE 路径簇消失；
3. 检查 DRAM `WEA` 是否只剩本地高位译码与写 mask 路径；
4. 若 150 MHz 仍失败，按新的前 20 条路径簇继续处理，不增加访存周期；
5. 150 MHz 通过后，重新复核 125/130 MHz setup/hold 和完整 benchmark。
