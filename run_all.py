#!/usr/bin/env python3
"""
run_all.py

用途：
1) 编译 RTL + Testbench
2) 批量切换 HEX 并运行仿真
3) 汇总每条指令的 PASS/FAIL 结果

后续维护入口（最常改的地方）：
- 改测试集合：UI_INSTS / MI_INSTS
- 改编译内容：compile_design()
- 改仿真命令：simulate_one()
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path


# UI 指令测试集合（rv32ui-p-*.hex）
UI_INSTS = [
    "sw",
    "lw",
    "add",
    "addi",
    "sub",
    "and",
    "andi",
    "or",
    "ori",
    "xor",
    "xori",
    "sll",
    "srl",
    "sra",
    "slli",
    "srli",
    "srai",
    "slt",
    "slti",
    "sltu",
    "sltiu",
    "beq",
    "bne",
    "blt",
    "bge",
    "bltu",
    "bgeu",
    "jal",
    "jalr",
    "lui",
    "auipc",
    "lh",
    "lhu",
    "sh",
    "sb",
    "lb",
    "lbu",
]

# MI 指令测试集合（rv32mi-p-*.hex）
MI_INSTS = ["csr", "scall", "sbreak", "ma_fetch"]


def resolve_repo_root() -> Path:
    # 用于判定“一个目录是不是工程根目录”的必要路径
    required_paths = [
        Path("rtl") / "cpu_top",
        Path("test"),
        Path("hex") / "riscv-tests",
    ]

    def is_repo_root(path: Path) -> bool:
        return all((path / p).exists() for p in required_paths)

    candidates: list[Path] = [Path.cwd()]

    # EXE（PyInstaller）模式：优先检查当前工作目录，再检查 exe 所在目录
    if getattr(sys, "frozen", False):
        exe_dir = Path(sys.executable).resolve().parent
        candidates.extend([exe_dir, exe_dir.parent])
    else:
        # 脚本模式：可直接用本文件所在目录
        candidates.append(Path(__file__).resolve().parent)

    for candidate in candidates:
        if is_repo_root(candidate):
            return candidate

    return Path.cwd()


def run_cmd(command: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    # 统一的 shell 命令执行器，便于收集 stdout/stderr
    return subprocess.run(
        command,
        cwd=str(cwd),
        shell=True,
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )


def looks_like_hex_not_loaded(output: str) -> bool:
    # 情况1：日志出现 readmem 错误关键词
    lower = output.lower()
    if "readmem" in lower and ("cannot" in lower or "error" in lower or "unable" in lower):
        return True

    # 情况2：调试打印中大量出现 X（常见于 hex 未正确加载）
    x_value_hits = len(
        re.findall(
            r"debug_(?:inst_pc|wb_pc|wb_rf_data|data):\s*[xX]{4,8}",
            output,
            flags=re.IGNORECASE,
        )
    )
    return x_value_hits >= 5


def simulate_one(
    repo_root: Path,
    suite_prefix: str,
    inst: str,
    results_dir: Path,
) -> tuple[bool, str]:
    # 本次仿真要用的源 HEX 与目标 HEX（testbench 固定读取 rv32-p-riscv.hex）
    src_hex = repo_root / "hex" / "riscv-tests" / f"{suite_prefix}-{inst}.hex"
    dst_hex = repo_root / "hex" / "riscv-tests" / "rv32-p-riscv.hex"

    if not src_hex.exists():
        return False, f"[ERROR] 缺少 HEX 文件: {src_hex}"

    # 每条指令仿真前先把目标 hex 覆盖为当前测试用例
    shutil.copyfile(src_hex, dst_hex)

    # 仿真命令入口：如果你想改仿真行为（加波形/改 do 脚本），改这里
    cp = run_cmd('vsim -c -do "run -all; quit -force" tb_cpu_top', repo_root)
    output = (cp.stdout or "") + (cp.stderr or "")

    result_file = results_dir / f"{inst}.txt"
    result_file.write_text(output, encoding="utf-8", errors="replace")

    passed = "Test passed." in output
    if passed:
        return True, f"[PASSED] {suite_prefix}-{inst}"

    hint = ""
    if looks_like_hex_not_loaded(output):
        hint = (
            "\n[HINT] 检测到访存/调试值大量为 X，极可能 HEX 未成功加载。"
            "\n       请检查 test/tb_cpu_top.sv 中 MEM_ADDR 路径与当前工程路径是否一致。"
        )
    return False, f"[FAILED] {suite_prefix}-{inst}{hint}\n详情见: {result_file}"


def compile_design(repo_root: Path) -> tuple[bool, str]:
    # 编译文件选择入口：如果你想改编译范围、编译顺序，改这里
    sv_files = sorted((repo_root / "rtl" / "cpu_top").glob("*.sv"))
    svh_files = sorted((repo_root / "rtl" / "cpu_top").glob("*.svh"))
    test_sv_files = sorted((repo_root / "test").glob("*.sv"))

    all_files = sv_files + svh_files + test_sv_files
    if not all_files:
        return False, "Compile failed!\n未找到待编译的 SV/SVH 文件。"

    # 这里是 vlog 编译命令入口
    cp = subprocess.run(
        ["vlog", "-sv", *[str(p) for p in all_files]],
        cwd=str(repo_root),
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    output = (cp.stdout or "") + (cp.stderr or "")
    if cp.returncode != 0:
        return False, f"Compile failed!\n{output}"
    return True, "Compile finished."


def run_suite(repo_root: Path, suite_name: str, suite_prefix: str, insts: list[str]) -> int:
    # 执行一个测试集合（如 UI / MI）
    print(f"\nStarting simulation for {suite_name} instructions...")
    results_dir = repo_root / "results"
    results_dir.mkdir(exist_ok=True)

    for inst in insts:
        print(f"\n====== Simulating {suite_prefix}-{inst} ======")
        ok, message = simulate_one(repo_root, suite_prefix, inst, results_dir)
        print(message)
        if not ok:
            result_path = results_dir / f"{inst}.txt"
            if result_path.exists():
                print("\n--- 失败日志片段开始 ---")
                print(result_path.read_text(encoding="utf-8", errors="replace"))
                print("--- 失败日志片段结束 ---")
            return 1
    return 0


def parse_args() -> argparse.Namespace:
    # 命令行参数：可扩展（比如加 --only、--suite）
    parser = argparse.ArgumentParser(description="Run all RISC-V tests (Python refactor of run_all.bat)")
    parser.add_argument(
        "--skip-compile",
        action="store_true",
        help="Skip vlog compile stage.",
    )
    return parser.parse_args()


def main() -> int:
    # 主流程：定位工程 -> 编译 -> 跑 UI -> 跑 MI
    args = parse_args()
    repo_root = resolve_repo_root()

    if not args.skip_compile:
        print("Compiling design...")
        ok, message = compile_design(repo_root)
        print(message)
        if not ok:
            return 1

    if run_suite(repo_root, "UI", "rv32ui-p", UI_INSTS) != 0:
        return 1

    if run_suite(repo_root, "MI", "rv32mi-p", MI_INSTS) != 0:
        return 1

    print("\nAll tests finished!")
    print("ALL TESTS PASSED!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
