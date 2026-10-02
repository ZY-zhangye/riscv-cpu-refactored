# 辅助 Verilator 仿真

Verilator 相关内容单独保存在此目录。日常仿真以仓库根目录 `run_all.bat` 的 Questa 指令回归为主；这里的模型和板级参考不编入默认 Questa 文件清单。

- `coremark/`：CPU / SoC 的 CoreMark C++ 驱动和构建入口。
- `soc/`：板级 SoC 测试台、仿真模型、文件清单和构建入口。
- `board_reference/`：仅为上述板级仿真保留的参考 RTL，不代表 Zynq-7020 平台适配。

在 Linux / WSL 中运行 `coremark/run_coremark.sh` 或 `soc/run_soc_irom_v2.sh`。脚本从自身位置定位仓库根目录；使用 `VERILATOR_EXE` 指定工具。SoC 测试需要 `IROM_COE` / `DRAM_COE`，CoreMark 默认使用仓库 `board_tests/05_coremark/output` 下的 HEX。输出写到仓库 `build/`。

本次只调整目录和引用，未重新执行 Verilator 功能仿真；Questa 回归结果不能代表这些辅助平台已验证。
