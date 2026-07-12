# P7A 深流水线尝试复盘与教训

日期：2026-07-13

## 结论

本轮 P7A 的数据访存请求/响应流水化尝试未达到可签核状态，已完整回退。
当前没有保留 P7A RTL、响应接口、临时测试模块或板级 wrapper 改动。

本轮最有价值的结果不是一个可发布的 P7 版本，而是确认了几个必须在下一次
实现中先解决的协议问题：流水级准入条件必须与实际副作用准入条件一致，访存
请求必须带着完整年龄和 kill 语义穿过边界，且双发控制指令不能通过临时禁用
来掩盖 redirect/前递错误。

## 尝试范围

P7A 通过可选宏增加了单 outstanding LSU 请求/响应边界，主要改变包括：

- 在核心和数据存储器之间注册地址、写数据、写掩码、读写类型及请求元数据；
- 为外部 bridge 增加 response-valid，并让 MEM 在 load response 到达前保持 resident；
- 对 store 请求增加顺序提交限制；
- 为未对齐访问、flush packet 和 MEM skid entry 增加处理；
- 为验证这些协议增加 LSU 定向测试和 benchmark 观察 wrapper。

该方案没有完成 EX0/EX1/EX2、Issue output 或 IF/BTB 的后续拆分，也没有运行
Vivado 实现，因此不能据此声称达到 175 MHz。

## 定位过程

### 1. flush load 进入 MEM 会造成永久等待

P7A 中被 branch/exception flush 的 load 如果仍进入 MEM，EX 侧已经抑制了
访存请求，但 MEM 仍会等待 response-valid，形成永不满足的等待条件。

教训：flush 不是只清除写回使能。对会等待外部响应的 packet，EX->MEM 边界
必须同时取消 packet 的 valid，并保持 lane0/lane1 的年龄原子性。

### 2. 旧 allowin 不能代表新的 LSU 停顿

原有 EX stage 的 `es_allowin` 只观察传统 MEM 握手。P7A 又增加了 LSU busy、
store/load 冲突和 response 等待，但 ID->EX 仍可能依据旧 allowin 接收下一条
指令，覆盖正在等待 LSU 的 EX load。

该问题会表现为栈保存值丢失、恢复后的 `s2` 变成 0，最终 sink 读回错误地址。
把 P7A 的 ID->EX 准入绑定到包含 LSU 条件的 `ex_bundle_advance` 后，受限配置
的 sink 恢复到 P5 对照值。这是本轮最明确的 RTL 根因。

教训：任何新增的外部等待条件都必须进入同一套 stage hold/advance 状态机；
不能只在输出端屏蔽请求，而让上游继续替换 resident packet。

### 3. lane1 控制指令暴露了 branch/redirect 年龄问题

保留 lane1 控制配对时，P7A benchmark 在 `BRANCH_RETURN` 附近长时间重复执行，
曾观察到 lane1 branch 源操作数、taken 和 redirect 不一致。临时禁止
“lane0 simple integer + lane1 control”配对后，九个窗口可以完成，但这改变了
既有双发契约，并显著降低 IPC，因此不能作为修复。

恢复 lane1 控制配对并加入 EX hold 修复后，短定向多发测试通过，但完整 benchmark
仍长时间停滞，最终按约定停止并回退。

教训：不能用降低发射能力绕过控制流错误。下一版必须为 lane1 branch 增加明确的
packet age、redirect 优先级、flush 和前递断言，并单独验证 taken/not-taken、
branch 后 load/store 以及 RAS return。

### 4. 单 outstanding LSU 的吞吐代价是可见的

即使在能完成 benchmark 的受限配置中，单 outstanding 请求也会让 load/store
连续序列产生大量等待。它适合作为协议正确性的第一阶段，不适合作为最终 IPC
方案。后续需要在保持顺序提交的前提下增加请求/响应 FIFO 或至少允许安全的
连续请求接收。

### 5. benchmark golden 值必须先和镜像版本对齐

当前 P5 RTL benchmark 实测结果为 `sink=0x4A27AD51`，而 testbench 固定期望
`0x9D3BF787`。P5 回退后仍出现同样差异，说明该矛盾不是 P7 引入的，不能把它
误判为 P7 LSU 的唯一功能回归。下一次性能实验必须同时固定：

- benchmark ELF/hex 的版本和生成时间；
- sink golden 值的来源；
- testbench 期望值与镜像的校验；
- 变更前后的同一份镜像和同一套计数窗口。

## 实测结果

| 配置 | 结果 |
| --- | --- |
| P7A RTL 全量编译 | 通过，0 errors、0 warnings |
| P7A 受限配置（lane1 control 禁止） | 九窗口完成，exceptions=0，IPC=1.043；sink=0x4A27AD51，未达到 IPC 和 golden sink 要求 |
| P7A 恢复 lane1 control | 完整 benchmark 长时间停滞，无有效 IPC 签核数据 |
| P5 回退 RTL 全量编译 | 通过，0 errors、0 warnings |
| P5 回退定向 RTL 测试 | `tb_perf_counters`、`tb_issue_stage`、`tb_mem_commit`、`tb_multi_issue_l2`、`tb_multi_issue_l3`、`tb_dram_driver`、`tb_if_ras_recovery`、`tb_mul_special`、`tb_my_cpu` 全部通过 |
| P5 benchmark | cycles=1,790,178，instret=2,279,455，IPC=1.273，exceptions=0；因 sink golden 不一致失败 |
| `run_all.bat base` | 基础单元测试通过；在 `rv32mi-p-scall` 处失败，x10 期望 1、实际 3 |

相关日志保留在 `results/`：

```text
results/p5_benchmark_rollback.txt
results/mi_scall.txt
results/p7_benchmark_id_gate.txt
results/p7_benchmark_id_gate_lane1control.txt
```

## 下一次实施建议

1. 从 P5 HEAD 重新建立独立分支，先修正 benchmark 镜像与 golden sink 的版本一致性。
2. 先加入 LSU 请求保持、response 标签和 flush 的 directed tests，再接入完整 CPU。
3. 用显式 `valid/ready` 和 transaction age 驱动 EX/MEM/LSU，禁止 raw allowin 绕过
   新增的 LSU stall 条件。
4. 保持 lane1 控制配对能力，先完成 branch packet 的年龄/redirect/flush 断言，
   再进行性能测量。
5. 只有功能回归、benchmark sink 和 IPC A/B 均稳定后，才开始下一轮综合及时序评估。

## 当前暂存内容

本复盘文档与工作区中任务前已有的
`hex/riscv-tests/rv32-p-riscv.hex` 修改一起作为本次检查点暂存。
P7A 尝试本身不应被提交或用于实现签核。
