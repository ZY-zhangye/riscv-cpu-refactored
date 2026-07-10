# 顺序多发 L0 阶段检查点

## 阶段目标

L0 在不改变单发执行宽度的前提下，建立后续双发/多发改造所需的精确退休、性能计数和可比较 trace 基线。

完成日期：2026-07-10

## 已完成内容

### 精确退休计数

- `instret` 不再使用“有效写回周期减去分支/异常固定惩罚”的估算方式。
- MEM 阶段依据有效指令、flush 和 trap 状态产生 `retire_count[1:0]`。
- 当前单发实现输出 0 或 1；接口已为后续双发的 0/1/2 退休数量预留。
- branch、store、fence、mret 等不写 GPR 的正常指令也能作为退休指令计数；发生同步异常或被中断截断的指令不退休。

### 性能计数 CSR

实现了软件头文件中预留的 `0x7C0~0x7C9`：

| CSR | 含义 |
| --- | --- |
| `0x7C0 perf_ctrl` | bit0 使能性能窗口；bit1 写 1 清零全部窗口计数器 |
| `0x7C1 perf_cycle` | 窗口内周期数 |
| `0x7C2 perf_instret` | 窗口内精确退休指令数 |
| `0x7C3 perf_branch` | 已解析的 branch/jump 数量 |
| `0x7C4 perf_brmisp` | 产生 redirect 的预测错误数量 |
| `0x7C5 perf_bphit` | 未产生 redirect 的正确预测数量 |
| `0x7C6 perf_bpmiss` | 预测错误数量，当前与 `perf_brmisp` 同义 |
| `0x7C7 perf_loaduse` | load-use 冒险停顿周期数 |
| `0x7C8 perf_exstall` | 乘除法等执行级停顿周期数 |
| `0x7C9 perf_exception` | 同步异常和外部中断进入 trap 的次数 |

标准 `cycle/instret` 始终运行；性能窗口可以独立清零、启动和冻结。

### Commit 与 store trace

流水线现在将原始指令字携带到 WB，并提供以下调试信息：

- commit valid、PC、指令字；
- GPR/FPR 写使能、地址与数据；
- CSR 写使能、地址与数据；
- store 实际副作用事件的 PC、地址、字节写使能与写数据。

`tb_my_cpu` 输出稳定的单行记录：

```text
COMMIT pc=... inst=... gpr_wen=... gpr_addr=... gpr_data=... fpr_wen=... csr_wen=... csr_addr=... csr_data=...
STORE  pc=... addr=... wen=... data=...
```

测试结束判断同时要求 `debug_commit_valid`，避免仅因 WB PC 保持旧值而提前结束。

## 验证记录

- QuestaSim 2024.1 全 RTL 与 testbench 编译：Errors 0，Warnings 0。
- `tb_perf_counters`：通过。
- `run_all.bat all`：通过。
- ISA 回归：77/77 通过，包括 RV32I、机器模式异常/CSR、M 扩展以及当前实现的 Zba/Zbb/Zbkb/Zbs。
- 当前用户修改的 `hex/riscv-tests/rv32-p-riscv.hex` 未被覆盖；完整回归在隔离 Git worktree 中执行。

## 综合决策

本阶段没有复制执行单元、扩展寄存器堆端口或改变存储器结构，新增内容以计数寄存器、事件连线和调试数据字段为主。纯编译、单元测试和完整功能回归均通过，没有出现必须依赖综合才能判断的时序或资源风险，因此按计划不执行耗时综合。

## 已知边界

- `STORE` 记录的是当前硬件实际拉高数据存储器写使能的时刻，不代表未来双发版本中的有序 commit 点。精确 store 副作用仍需在 L2 阶段解决。
- `perf_bphit/perf_bpmiss` 当前表示预测结果正确/错误，不区分 BTB 表项是否命中。
- 单发阶段不存在 issue 配对或结构冲突拒绝计数；这些计数器将在 L1 issue stage 引入后增加。
- 当前 FPU 仍为占位实现，不纳入本阶段性能基线。

## 下一阶段入口

下一阶段为 L1“保守 2-wide 整数双发”。首先建立顺序 issue 边界、双条缓冲和独立 issue 单元测试，然后再扩展取指与双整数执行通路。
