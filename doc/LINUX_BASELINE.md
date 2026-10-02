# Linux 接续开发工作区基线

- 仓库：https://github.com/ZY-zhangye/riscv-cpu-refactored （保持公开）。
- 工作区：`W:\riscv-cpu-refactored`。
- 来源：`main`，提交 `d78188fa64b86977d0ce9cb570d3ced46ca0119c`。
- 开发分支：`dev/linux-bringup`。
- 验证日期：2026-10-02；Questa Sim-64 2024.1。

## 实测结果

原 `run_all.bat all` 重新执行 **77/77 通过**，纯编译记录为 0 errors / 0 warnings。UI 37、MI 4、UM 8、Zba 3、Zbb 13、Zbkb 5、Zbs 7。逐用例检查了成功标记与错误标记，不使用旧报告作为本轮证据。

另外 **8/8 已有定向测试通过**：`tb_mul_pipeline`、`tb_div_kill_drain`、`tb_stack_value_buffer`、`tb_if_sync_btb_single`、`tb_lw_live_bypass`（默认关闭实验旁路）、`tb_PLIC`、`tb_timer`、`tb_UART`。除法冲刷测试需要 `TB_DIV_KILL_DRAIN`，在独立库中编译其专用 divider 模型，不能直接从普通回归 work 库加载。

证据摘要位于 [linux_baseline_results.json](linux_baseline_results.json)，包含实际执行用例、HEX / RTL 与结果日志 SHA-256。完整本机日志位于 `build/baseline/` 和 `results/`，按现有规则忽略，不把构建缓存提交进 Git。

## 重现入口

工具需在 PATH 中。在仓库根目录首次运行：

```powershell
vlib work
.\run_all.bat all
```

原脚本包含结尾 `pause`；本次用 `cmd /c 'echo.|run_all.bat all'` 非交互运行。脚本会复制当前测试到 `hex/riscv-tests/rv32-p-riscv.hex`，本轮在运行前保存、结束后逐字恢复该跟踪文件。未来改进回归时优先隔离生成文件并保留脚本失败退出语义。

定向测试使用默认已编译的 work 库，例如：

```powershell
vsim -c -onfinish stop -do "run -all; quit -force" tb_stack_value_buffer
```

除法冲刷用例独立编译：

```powershell
vlib build/baseline/div_work
vlog -sv -work build/baseline/div_work +define+TB_DIV_KILL_DRAIN +incdir+rtl/cpu_top rtl/cpu_top/mul_pipeline.sv rtl/cpu_top/mul.sv test/tb_div_kill_drain.sv
vsim -c -lib build/baseline/div_work -onfinish stop -do "run -all; quit -force" tb_div_kill_drain
```

## 结论边界与下一步

本次接续只添加路线与验证记录，保留现有 RTL、测试脚本和目录。`main` 比毕业设计 project2 工作树包含更多后续优化，两者不是同一版；F 盘前期迁移的通过结果不归属于本仓库。

现有测试验证 DEBUG_EN 仿真配置及指定用例，不证明完整特权、A 扩展、Sv32、厂商 IP、板级时序或 Linux 已实现。历史 MMIO / 性能计数文档仍须与当前 CSR 实现核对；FPU 是占位，`instret` 仍是分支 / 异常扣减估算。

下一步首先完善退休观测、精确异常和 CSR / 指令合法性测试，随后设计统一且支持背压、错误响应的内存接口。按 [Linux 演进路线](LINUX_ROADMAP.md) 依次推进原子操作、特权与 SBI、MMU、缓存、AXI / DDR 和内核启动。具体 Zynq 开发板型号确定后再建立该板的时钟、PS 配置和引脚约束。
