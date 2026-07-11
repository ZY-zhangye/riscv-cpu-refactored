# L3P 125 MHz 提交候选

> 状态更新：后续 L3Q 检查发现 multiplier IP 为 6 拍而 RTL 控制原为 4 拍，并建立了多组可选性能配置。修正后的结果与综合建议见 `multi_issue_l3q_performance_candidates.md`。

## 决策

150 MHz 压力优化暂告一段落，提交候选固定为 125 MHz。L3M/L3N/L3O 针对物理路径的 RTL 改动回退到 L3K 功能基线，保留 L3L 的外设高位地址译码；这些实验虽改善了部分关键路径，但未在可靠 benchmark 镜像上完成发布级功能验证。

125 MHz 候选默认启用已有的 `L3F_SAME_CYCLE_ALU_BYPASS`。它允许同一取指包内的 lane1 简单 ALU 指令直接消费 lane0 ALU 结果，减少不必要的 RAW 串行化。load、控制流、bitman 等不安全组合仍保持原阻塞规则。

## Benchmark 修复

`PERF_BENCH` 下 RTL 的 `PC_START` 为 `0x0000_0000`，但 benchmark 链接脚本一度把 `.text` 放在 `0x8000_0000`，导致仿真重复进入部分窗口并最终超时。链接地址恢复为 `0x0000_0000` 后，九个窗口均一次完成，性能邮箱仍位于 `0x6000_0800`。

## 125 MHz A/B 结果

两组使用同一份 125 MHz 镜像，sink 均为 `0x9D3BF787`，异常计数均为 0。

| 配置 | 总 cycles | instret | IPC | 变化 |
| --- | ---: | ---: | ---: | ---: |
| L3K 功能基线 | 1,749,321 | 2,279,454 | 1.303 | — |
| 同周期 ALU 旁路 | 1,691,321 | 2,279,454 | 1.347 | cycles -3.32%，IPC +3.38% |

收益主要来自 ALU、随机分支和返回负载；MEMORY 等不适用该旁路的负载周期不变。

## 发布验证

- Questa 完整九窗口 benchmark：通过。
- 邮箱版本：5。
- CPU 频率字段：125,000,000 Hz。
- sink：`0x9D3BF787`。
- Vivado 实现由云端对本提交按 125 MHz 常规流程执行，无需特殊综合选项。
