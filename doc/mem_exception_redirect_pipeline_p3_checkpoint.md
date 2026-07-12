# MEM Exception Redirect Pipeline P3 Checkpoint

## P2 整体综合结果

器件与约束：`xc7k325tffg900-2`，`175 MHz`。

```text
WNS               -1.132 ns
TNS            -2753.171 ns
Failing endpoints       3677
LUT                    15817
FF                     15050
```

相对上一轮，WNS 改善 `2.073 ns`，TNS 改善 `4419.704 ns`。原 EX redirect 到 IF/Issue/RAS 的路径已经退出关键路径。

P2 最差路径：

```text
u_mem_stage0/ms_valid_reg/C
  -> u_regfile_csr/perf_bphit_reg[0]/CE
```

数据路径 `6.585 ns`，13 级逻辑；逻辑延迟 `0.862 ns`，估算布线 `5.723 ns`。

## 根因

`perf_bphit` 只是最先出现的端点。前 200 条路径表明同一控制锥还到达：

```text
perf_brmisp[*]/CE
bp_update_* / br_redirect_target[*]/CE
EX resident/skid payload CE
```

实际组合链为：

```text
MEM ms_valid
  -> interrupt/exception selection
  -> selected_exception_code
  -> CSR exception_flag
  -> EX dmem request / dual-lane LSU conflict
  -> EX bundle advance / branch event
  -> global metadata and performance-counter CE
```

因此只给性能计数器打拍不足以解决问题；需要切断架构级 MEM exception feedback。

## P3 RTL 修改

### CSR trap redirect 寄存边界

`regfile_csr.sv` 在异常/MRET 检测沿仍立即写入 `mepc/mcause/mtval/mstatus`，同时锁存：

```text
exception_flag
exception_addr
```

`exception_flag` 作为单拍脉冲在下一周期扇出到 IF、Issue、ID、EX 和 MEM。同步异常、中断与 MRET 的全局 redirect 均延后一拍，但异常状态写入时刻不变。

### 年轻流水状态清除

异常检测沿可能允许一组年轻指令进入 EX/MEM，因此：

- `exe_stage.sv` 在寄存后的 exception pulse 到来时清除 resident 与 skid valid；
- `mem_stage.sv` 同样清除 resident 与 skid valid，并在该周期把 `ms_flush` 拉高；
- store、GPR/FPR 写回和 retire 均在清除沿前被 `ms_flush` 屏蔽。

这保持了精确异常，不允许延迟 redirect 期间的年轻指令提交。

## RTL 验证

全 RTL/testbench 编译：`Errors 0, Warnings 0`。

通过：

```text
tb_perf_counters
  - exception redirect 非组合输出
  - trap target 下一拍锁存
  - mret target 下一拍锁存
tb_mem_commit
  - trap pulse 屏蔽并清除 resident store
tb_issue_stage
tb_multi_issue_l2
tb_multi_issue_l3
tb_if_ras_recovery
tb_mul_special
tb_my_cpu (当前 rv32-p-riscv.hex)
```

L3 微基准保持 `30 cycles / 34 instret`。

九窗口 benchmark 与 P2 完全一致：

```text
cycles       1,790,106
instret      2,279,454
IPC              1.273
exceptions           0
sink        0x4A27AD51
```

sink 与 testbench 的旧期望 `0x9D3BF787` 仍不一致，这是 P1/P2 已存在的问题，P3 未改变结果。

## 下一轮外部综合检查

本阶段未运行 Vivado。请使用当前 RTL 重做相同的 175 MHz quick synth，并检查：

1. `ms_valid_reg/C -> perf_bphit/perf_brmisp CE` 是否消失；
2. `ms_valid_reg/C -> bp_update/br_redirect_target CE` 是否消失；
3. `ms_valid_reg/C -> EX resident/skid CE` 是否消失；
4. 新增 `exception_flag_reg/D` 的输入路径是否满足 5.714 ns；
5. `exception_flag_reg/Q` 到各级 flush/CE 的扇出路径是否满足 5.714 ns；
6. 新的真实最差路径、WNS、TNS 与 failing endpoints。

按本轮路径分段估算，原链在 exception 寄存边界前后分别约为 3.2 ns 和 3.4 ns；如果布局没有异常拉远，两段都应满足 175 MHz。
