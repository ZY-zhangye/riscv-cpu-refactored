#!/usr/bin/env python3
"""Run the original ISA and directed Questa tests in an isolated workspace."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone


GROUPS = (
    ("UI_INSTS", "rv32ui-p"),
    ("MI_INSTS", "rv32mi-p"),
    ("UM_INSTS", "rv32um-p"),
    ("ZBA_INSTS", "rv32uzba-p"),
    ("ZBB_INSTS", "rv32uzbb-p"),
    ("ZBKB_INSTS", "rv32uzbkb-p"),
    ("ZBS_INSTS", "rv32uzbs-p"),
)
DIRECTED = (
    ("tb_mul_pipeline", "[MUL_PIPELINE] PASS"),
    ("tb_stack_value_buffer", "PASS: stack value buffer directed tests"),
    ("tb_if_sync_btb_single", "IF SYNC 128-ENTRY BTB TEST PASSED"),
    ("tb_lw_live_bypass", "PASS tb_lw_live_bypass live=0 stalls=5"),
    ("tb_PLIC", "Test passed."),
    ("tb_timer", "Test passed."),
    ("tb_UART", "Test passed."),
)
FAILURES = re.compile(
    r"\*\*\s+(?:Error|Fatal)(?:\s|:)|\[FAILED\]|Test failed\.|Simulation timeout",
    re.IGNORECASE,
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path)
    parser.add_argument("--tool-dir", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    build = (args.build_dir or repo / "build/hello_zynq/isa_regression").resolve()
    build.mkdir(parents=True, exist_ok=True)
    logs = build / "logs"
    logs.mkdir(exist_ok=True)
    ini = build / "modelsim.ini"
    result_file = build / "regression_results.json"
    shared_hex = repo / "hex/riscv-tests/rv32-p-riscv.hex"
    original_hex_hash = sha256(shared_hex)
    local_hex = build / "hex/riscv-tests/rv32-p-riscv.hex"
    local_hex.parent.mkdir(parents=True, exist_ok=True)

    tool_dir = args.tool_dir
    if tool_dir is None:
        resolved = shutil.which("vsim") or shutil.which("vsim.exe")
        if not resolved:
            raise RuntimeError("Questa vsim must be on PATH, or pass --tool-dir")
        tool_dir = Path(resolved).parent
    tools = {name: str(tool_dir / f"{name}.exe") for name in ("vlib", "vmap", "vlog", "vsim")}
    for name, path in tools.items():
        if not Path(path).is_file():
            raise RuntimeError(f"Missing Questa {name}: {path}")

    env = os.environ.copy()
    env.pop("MODELSIM", None)
    summary = {
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "repository": str(repo),
        "build_directory": str(build),
        "tools": tools,
        "modelsim_ini": str(ini),
        "shared_hex": str(shared_hex),
        "shared_hex_sha256_before": original_hex_hash,
        "shared_hex_modified": False,
        "memory_selection": "per-case copy under isolated simulator cwd; shared HEX is never written",
        "source_sha256": {},
        "steps": [],
        "isa": [],
        "directed": [],
        "status": "RUNNING",
    }

    def save() -> None:
        result_file.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    def run(label: str, command: list[str], *, timeout: int = 120) -> tuple[str, dict]:
        log = logs / f"{label}.log"
        started = time.monotonic()
        timed_out = False
        with log.open("w", encoding="utf-8", newline="\n") as handle:
            try:
                proc = subprocess.run(command, cwd=build, env=env, stdout=handle,
                                      stderr=subprocess.STDOUT, timeout=timeout, check=False)
                code = proc.returncode
            except subprocess.TimeoutExpired:
                timed_out = True
                code = -1
                handle.write(f"\nRUNNER_TIMEOUT seconds={timeout}\n")
        output = log.read_text(encoding="utf-8", errors="replace")
        step = {
            "name": label, "command": command, "log": str(log),
            "log_sha256": sha256(log), "returncode": code,
            "timeout": timed_out, "seconds": round(time.monotonic() - started, 3),
        }
        summary["steps"].append(step)
        save()
        return output, step

    def require_tool(label: str, command: list[str]) -> str:
        output, step = run(label, command)
        if step["returncode"] or FAILURES.search(output):
            raise RuntimeError(f"{label} failed; inspect {step['log']}")
        return output

    def simulate(label: str, library: str, top: str, marker: str, image: Path | None = None) -> dict:
        if image is not None:
            # MEM_ADDR is a localparam in the original TB. Resolve its unchanged
            # relative path inside this isolated cwd instead of editing shared HEX.
            shutil.copyfile(image, local_hex)
        command = [tools["vsim"], "-c", "-modelsimini", "modelsim.ini", "-lib", library,
                   "-onfinish", "stop", "-wlf", f"{label}.wlf",
                   "-do", "onerror {quit -code 1 -force}; run -all; quit -code 0 -force", top]
        output, step = run(label, command)
        result = {
            "name": label, "top": top, "library": library,
            "pass_marker": marker, "pass_marker_found": marker in output,
            "error_marker_found": bool(FAILURES.search(output)),
            "returncode": step["returncode"], "timeout": step["timeout"],
            "log": step["log"], "log_sha256": step["log_sha256"],
            "seconds": step["seconds"],
        }
        if image is not None:
            result.update(image=str(image), image_sha256=sha256(image))
        result["status"] = "PASS" if (
            result["pass_marker_found"] and not result["error_marker_found"]
            and result["returncode"] == 0 and not result["timeout"]
        ) else "FAIL"
        return result

    try:
        # Every mapping operation is local to build/modelsim.ini. Never pass an
        # absolute Windows path as vsim -lib (W: would be parsed as lib.name).
        if not ini.exists():
            require_tool("vmap_copy", [tools["vmap"], "-c"])
        env["MODELSIM"] = ini.as_posix()
        for library in ("isa_work", "div_kill_work"):
            library_path = build / library
            if not library_path.exists():
                require_tool(f"vlib_{library}", [tools["vlib"], str(library_path)])
            require_tool(f"vmap_{library}", [tools["vmap"], "-modelsimini", "modelsim.ini",
                                            library, library_path.as_posix()])

        # Compile only the original test benches; the board divider test has a
        # same-name replacement divider and therefore belongs to its own runner.
        tracked_tests = subprocess.check_output(
            ["git", "ls-files", "test/*.sv"], cwd=repo, text=True).splitlines()
        sources = (sorted((repo / "rtl/cpu_top").glob("*.sv"))
                   + sorted((repo / "rtl/my_cpu").glob("*.sv"))
                   + [repo / name for name in tracked_tests])
        for source in sources:
            summary["source_sha256"][str(source.relative_to(repo))] = sha256(source)
        for header_dir in (repo / "rtl/cpu_top", repo / "rtl/my_cpu"):
            for header in sorted(header_dir.glob("*.svh")):
                summary["source_sha256"][str(header.relative_to(repo))] = sha256(header)
        includes = [f"+incdir+{repo / 'rtl/cpu_top'}", f"+incdir+{repo / 'rtl/my_cpu'}",
                    f"+incdir+{repo / 'test'}"]
        require_tool("compile_isa", [tools["vlog"], "-sv", "-modelsimini", "modelsim.ini",
                                    "-work", "isa_work", *includes, *map(str, sources)])

        run_all = (repo / "run_all.bat").read_text(encoding="utf-8")
        cases = []
        for group, prefix in GROUPS:
            match = re.search(rf"(?im)^set {group}=(.+)$", run_all)
            if not match:
                raise RuntimeError(f"Missing run_all.bat list {group}")
            cases.extend((group, f"{prefix}-{name}") for name in match.group(1).split())
        if len(cases) != 77:
            raise RuntimeError(f"Expected the original 77 ISA tests, got {len(cases)}")
        summary["run_all_sha256"] = sha256(repo / "run_all.bat")
        for index, (group, name) in enumerate(cases, 1):
            image = repo / "hex/riscv-tests" / f"{name}.hex"
            if not image.is_file():
                raise RuntimeError(f"Missing ISA image: {image}")
            result = simulate(name, "isa_work", "tb_my_cpu", "Test passed.", image)
            result["group"] = group
            summary["isa"].append(result)
            save()
            print(f"ISA {index:02d}/77 {result['status']} {name}", flush=True)

        for top, marker in DIRECTED:
            result = simulate(top, "isa_work", top, marker)
            summary["directed"].append(result)
            save()
            print(f"DIRECTED {result['status']} {top}", flush=True)

        div_sources = [repo / "rtl/cpu_top/mul_pipeline.sv", repo / "rtl/cpu_top/mul.sv",
                       repo / "test/tb_div_kill_drain.sv"]
        require_tool("compile_div_kill", [tools["vlog"], "-sv", "-modelsimini", "modelsim.ini",
                                         "-work", "div_kill_work", "+define+TB_DIV_KILL_DRAIN",
                                         *includes, *map(str, div_sources)])
        result = simulate("tb_div_kill_drain", "div_kill_work", "tb_div_kill_drain",
                          "PASS tb_div_kill_drain result=9")
        summary["directed"].append(result)
        print(f"DIRECTED {result['status']} tb_div_kill_drain", flush=True)
        summary["isa_passed"] = sum(r["status"] == "PASS" for r in summary["isa"])
        summary["directed_passed"] = sum(r["status"] == "PASS" for r in summary["directed"])
        summary["status"] = "PASS" if (summary["isa_passed"] == 77 and summary["directed_passed"] == 8) else "FAIL"
    except Exception as exc:
        summary["status"] = "FAIL"
        summary["runner_error"] = str(exc)
        print(f"REGRESSION FAILED: {exc}", file=sys.stderr, flush=True)
    finally:
        # Shared bytes are never written; still detect any unexpected concurrent
        # modification and retain both hashes in the machine-readable evidence.
        final_hex_hash = sha256(shared_hex)
        summary["shared_hex_sha256_after"] = final_hex_hash
        summary["shared_hex_unchanged"] = final_hex_hash == original_hex_hash
        if final_hex_hash != original_hex_hash:
            summary["status"] = "FAIL"
        summary["finished_utc"] = datetime.now(timezone.utc).isoformat()
        save()
    print(f"BOARD_REGRESSION_{summary['status']} isa={summary.get('isa_passed', 0)}/77 "
          f"directed={summary.get('directed_passed', 0)}/8 shared_hex_unchanged={summary['shared_hex_unchanged']} "
          f"summary={result_file}", flush=True)
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
