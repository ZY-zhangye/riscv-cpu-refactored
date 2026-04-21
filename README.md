## 快速使用

### 1) 运行全部测试（Python 版）

仓库根目录执行：

- `run_all.bat`（优先调用 `dist\\run_all.exe`，不存在时自动调用 `py run_all.py`）
- 或直接：`py run_all.py`

可选参数：

- `--skip-compile`：跳过 `vlog` 编译阶段。

### 2) 打包为 EXE（使用 py，而不是 python）

执行：`build_exe.bat`

打包产物：`dist\\run_all.exe`

封装方法说明：

1. 入口脚本是 `run_all.py`；
2. `build_exe.bat` 会调用 `py -m PyInstaller --onefile` 打包；
3. 生成 `dist\\run_all.exe`；
4. `run_all.bat` 会优先调用该 EXE（无 EXE 时回退到 `py run_all.py`）。

### 3) 故障提示（HEX 未加载）

运行中如果日志里访存/调试值大量出现 `X`（例如 `debug_data: xxxxxxxx`），脚本会给出提示：

- 极可能是 HEX 没有成功加载；
- 重点检查 `test/tb_cpu_top.sv` 的 `MEM_ADDR` 是否与本机工程路径一致。

### 4) 如果要改“编译内容 / 仿真内容”，改哪里？

#### 改编译内容

- 文件：`run_all.py`
- 函数：`compile_design()`
- 你可以改：
	- 编译文件范围（`sv_files/svh_files/test_sv_files`）
	- 编译命令参数（`vlog -sv` 后的参数）

#### 改仿真内容

- 文件：`run_all.py`
- 函数：`simulate_one()`
- 你可以改：
	- 仿真命令（当前是 `vsim -c -do "run -all; quit -force" tb_cpu_top`）
	- 每条测试前 HEX 的拷贝逻辑
	- 结果判定规则（当前是日志包含 `Test passed.`）

#### 改测试集合（跑哪些 case）

- 文件：`run_all.py`
- 变量：`UI_INSTS`、`MI_INSTS`
- 在这里增删指令名即可。

---

## 手工单步命令（保留）

`vlog -lint rtl/cpu_top/*.sv rtl/cpu_top/*.svh test/*.sv`

`vsim -voptargs=+acc tb_cpu_top`