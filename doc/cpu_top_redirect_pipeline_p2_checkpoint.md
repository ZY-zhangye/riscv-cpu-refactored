# CPU Top 175 MHz Redirect Pipeline P2 Checkpoint

## 输入报告

器件与约束：`xc7k325tffg900-2`，`175 MHz`（周期 `5.714 ns`）。P1 整体综合结果：

```text
WNS               -3.205 ns
TNS            -7172.875 ns
Failing endpoints       4988
LUT                    16039
FF                     14960
```

最差路径：

```text
u_exe_stage0/mem_result_reg_reg[1]/C
  -> u_if_stage/ras_spec_count_reg[0]/CE
```

数据路径为 `8.658 ns`，23 级逻辑，其中逻辑 `2.071 ns`、估算布线 `6.587 ns`。前 200 条路径几乎全部属于同一个控制锥，端点集中在 `ras_spec_count[*]/CE` 与 `queue3[*]/CE`。

## 根因

原路径包含两个串接问题：

1. EX 的前递操作数经过 JALR 加法/分支比较，直接生成高扇出的全局 redirect；
2. RAS 预测决定 IF lane1 valid，当前 packet 宽度又参与 Issue 容量判断，`issue_allowin` 最后反向控制 RAS 投机 push/pop，形成跨 IF/Issue 的组合反馈控制锥。

因此该路径不是乘除法 IP 数据路径。继续优化局部 LUT 无法消除 6 ns 以上的跨模块布线。

## P2 RTL 修改

### 分支解析寄存边界

`cpu_top.sv` 只在分支 bundle 实际通过 EX->MEM 握手时，锁存以下窄控制事件：

```text
br_redirect / br_redirect_target
bp_update_valid / pc / taken / target / call / return
```

下一拍这些寄存信号再扇出到 IF、Issue 和 ID。分支本身已进入 MEM；同一时钟沿进入 EX 的年轻 bundle 由新增的 `branch_flush` 显式清除，EX skid 也同时失效，错误路径不能进入后续提交链。

该改变对预测正确的分支不增加 flush；误预测恢复增加一拍。

### IF/Issue 容量解耦

Issue 对双字 IF 接口始终预留两个槽位，`capacity_allow` 不再读取 `fs_to_is_valid0/1`。这切断：

```text
RAS/BTB prediction -> lane1 valid -> Issue capacity
  -> IF advance -> RAS speculative CE
```

单指令 packet 在“队列满 4 项且本拍只消费 1 项”时可能多等一拍；普通双取指吞吐和队列安全不变。

### RAS 恢复修正

redirect 已由 `br_taken_reg` 延迟一拍。此时 committed RAS 在前一沿已经接收 `bp_update_valid`，所以恢复只复制 committed stack/sp/count。旧逻辑再次应用寄存后的 call/return metadata，会把同一分支 push/pop 两次，P2 已删除该重复操作。

## RTL 验证

全 RTL/testbench 编译：`Errors 0, Warnings 0`。

通过：

```text
tb_issue_stage
tb_mem_commit
tb_multi_issue_l2
tb_multi_issue_l3
tb_mul_special
tb_if_ras_recovery
tb_my_cpu (当前 rv32-p-riscv.hex)
```

L3 微基准：`30 cycles / 34 instret`，P1 为 29 cycles。

完整九窗口 benchmark：

```text
P1 cycles       1,770,715
P2 cycles       1,790,106
P2 instret      2,279,454
P2 IPC              1.273
P2 brmisp          19,389
Delta cycles       19,391
```

周期增量几乎等于误预测数，符合每次误预测增加一个 redirect 流水拍的预期。九个窗口异常数均为 0。

benchmark sink 仍为 P1 已存在的 `0x4A27AD51`，与 testbench 的 `0x9D3BF787` 期望不一致，因此不能宣称完整 benchmark 签核通过。P2 没有改变该 sink。

## 下一轮外部综合检查

本阶段未运行 Vivado。用当前 RTL 重做相同的 175 MHz quick synth 后重点检查：

1. `mem_result_reg[*]/C -> ras_spec_count[*]/CE` 是否退出前 200；
2. `mem_result_reg[*]/C -> queue3[*]/CE` 是否退出前 200；
3. 全局控制路径起点是否迁移到新 `br_redirect_reg/Q`；
4. EX 局部 JALR/compare 到 `br_redirect_reg/D` 是否满足 5.714 ns；
5. 新最差路径是否迁移到 DRAM WEA、BTB lookup、MEM exception 或其他局部路径；
6. WNS、TNS、failing endpoints 与 P1 的变化。

如果新最差路径是 EX JALR 到 redirect 寄存器 D，下一步只需拆分/前移 JALR target 或比较逻辑；不应重新接回全局组合 redirect。
