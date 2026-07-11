# 顺序多发 L3J 实际程序画像与 M 扩展测量检查点

## 实际程序静态画像

读取实际测评镜像 `irom-v2-instruction-stats.txt`，共 2,216 条静态指令。主要类别如下：

| 类别 | 数量 | 占比 |
| --- | ---: | ---: |
| ALU immediate | 764 | 34.48% |
| Load | 341 | 15.39% |
| Store | 301 | 13.58% |
| Conditional branch | 147 | 6.63% |
| Direct jump | 131 | 5.91% |
| Indirect jump | 118 | 5.32% |
| Upper immediate | 161 | 7.27% |
| PC relative | 108 | 4.87% |
| ALU register RV32I | 85 | 3.84% |
| ALU register RV32M | 39 | 1.76% |
| CSR/system | 21 | 0.95% |

由此得到：

- load/store 合计 28.97%，访存仍是实际程序中最大的复杂指令簇；
- branch/jal/jalr 合计 17.87%，BTB、方向预测和 RAS 优化与真实镜像高度相关；
- 普通整数 immediate/register、LUI 和 AUIPC 合计约 50.46%，持续支持 2-wide 简单整数配对；
- RV32M 静态占比仅 1.76%，但包含 `mul/mulh/mulhu/mulhsu/div/divu/rem/remu` 全部变体，单条停顿代价可能放大其动态影响；
- 该镜像没有 FPU 或 bitman 指令，后续不能用这些扩展的人工窗口收益代表当前实际测评收益。

这份文件是静态指令镜像统计，不包含循环次数、热点或动态分支方向。因此不把静态占比直接转换成 benchmark 权重，也不把九窗口 `OVERALL` 当作实际程序 IPC 预测值；它只用于校正覆盖范围和优化优先级。

完成日期：2026-07-11

## Benchmark 调整

性能邮箱升级为 `L3J0`、version 5，增加独立 `MEXT` 窗口。编译目标改为 `rv32im_zicsr`，窗口每轮显式执行八种 RV32M 运算，避免编译器删除或合并。九个报告各增加 `result_dependency` 字段，邮箱共 772 bytes。

测量计数器同时修正：原 `loaduse` 实际把 load 未就绪和 mul/div 等多周期结果未就绪的相关等待混在一起。现在拆分为：

- `loaduse`：只统计依赖尚未返回的 load 结果；
- `multidep`（CSR `0x7D5`）：统计依赖尚未完成的多周期执行结果；
- `exstall`：EX 本身因多周期操作未完成而停止推进。

该拆分不改变 hazard 或流水线行为，只提高归因准确性。单元测试覆盖新 CSR 的计数、清零和读取。

## 默认 L3J 结果

默认配置为 128 项 BTB、2-bit 方向计数、JALR BTB 预测和 8-depth RAS：

| 窗口 | cycles | instret | IPC | loaduse | multidep | exstall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ALU | 144,018 | 216,013 | 1.499 | 1 | 0 | 0 |
| MEXT | 178,025 | 54,016 | 0.303 | 1 | 110,000 | 136,000 |
| BRANCH_RETURN | 456,063 | 760,025 | 1.666 | 0 | 0 | 0 |
| MEMORY | 462,859 | 601,238 | 1.298 | 46,081 | 0 | 0 |
| 九窗口总计 | 1,763,327 | 2,279,453 | 1.292 | — | — | — |

MEXT 的低 IPC 和大量 `multidep/exstall` 证明 RV32M 即使静态占比不高，也需要作为独立性能主线观察。当前窗口对四类乘法和四类除法/余数等量采样；实际镜像中乘法族 23 条、除法/余数族 16 条，窗口对慢速除法略偏保守。

RAS 默认打开后，RETURN 窗口保持 11 次误预测。定义 `L3I_DISABLE_RAS` 的回退配置得到 40,015 次误预测、616,079 cycles；固定 `sink=0x9D3BF787` 在两套配置中一致。

## 验证

- 全部 RTL/testbench 编译 Errors 0、Warnings 0；
- `tb_perf_counters`、`tb_issue_stage`、`tb_multi_issue_l2`、`tb_multi_issue_l3` 通过；
- 默认 RAS 与 `L3I_DISABLE_RAS` 回退 benchmark 均通过；
- 九窗口 exceptions=0，固定 sink 校验通过；
- L3 微基准保持 27 cycles、34 instret、IPC 1.259。

## 决策与后续方向

1. RAS 转为默认配置，保留 `L3I_DISABLE_RAS` 回退开关。
2. Benchmark 保留独立诊断窗口，不按静态指令比例生成伪“真实 IPC”。获取动态 trace 后再建立加权模型。
3. L3H/L3I 云端综合继续重点检查 IF/next-PC；若失败，可独立回退 BTB 容量或 RAS。
4. 下一轮本机仿真应拆分乘法族与除法/余数族，确定 136,000 个 EX stall 的来源，再决定是否评估流水化乘法接受率或保持现状。
5. 访存占比接近 29%，但当前 MEMORY IPC 1.298，仍需结合实际动态 trace 判断 store buffer/LSU 是否优先于 M 扩展优化。
