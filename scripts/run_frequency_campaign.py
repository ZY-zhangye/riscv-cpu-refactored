#!/usr/bin/env python3
"""Build and measure separate real-board CoreMark frequency experiments.

This script programs volatile PL configurations and opens one passive UART
capture process per attempt. It never writes flash, restores another image,
resets board power, sends mail, or shuts down the computer. Use --plan-only to
inspect the complete frequency range and commands without starting any process.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
CAPTURE_PYTHON = Path(os.environ.get("RV_CAPTURE_PYTHON", sys.executable))


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_json(path: Path, value: dict) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def classify_capture(result: dict, capture_rc: int, program_verified: bool,
                     expected_hz: int, boot_seen: bool) -> tuple[str, str]:
    """Keep tool/transport failures separate from an executed frequency test."""
    if not program_verified:
        return "TOOL_BLOCKED", "programming did not have verified DONE/success evidence"
    if capture_rc not in (0, 1) or result.get("status") in ("ERROR", "CAPTURE_ERROR", "TOOL_ERROR"):
        return "TOOL_BLOCKED", "capture process reported a tool/transport error"
    fields = result.get("coremark", {})
    if fields and int(fields.get("cpu_hz", expected_hz)) != expected_hz:
        return "TOOL_BLOCKED", "UART result frequency differs from the built image"
    if (capture_rc == 0 and result.get("status") == "PASS" and
            result.get("valid_coremark") is True and boot_seen):
        return "PASS", "CRC and >=10-second CoreMark result independently accepted by capture tool"
    if result.get("status") in ("TIMEOUT", "INVALID_COREMARK", "FIRMWARE_FAIL"):
        return "COREMARK_FAIL", ("no matching BOOT after verified programming" if not boot_seen else
                                  "timeout, CRC/validation failure, or invalid performance duration/result")
    return "TOOL_BLOCKED", "capture completed without a supported verdict; not a frequency-failure verdict"


class Campaign:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.output = args.root_output.resolve()
        self.report_path = self.output / "campaign.json"
        self.current_capture: subprocess.Popen | None = None
        self.report = {
            "schema_version": 1, "pid": os.getpid(), "started_at": now(),
            "started_at_singapore": datetime.now(timezone(timedelta(hours=8))).isoformat(),
            "status": "RUNNING", "phase": "initializing", "updated_at": now(),
            "configuration": {"start_mhz": args.start_mhz, "step_mhz": args.step_mhz,
                              "max_mhz": args.max_mhz, "iterations": args.iterations,
                              "port": args.port, "capture_seconds": args.duration,
                              "confirm_failure": args.confirm_failure, "jobs": args.jobs,
                              "root_output": str(self.output)},
            "points": [], "last_pass": None, "first_fail": None,
            "restore_performed": False, "flash_written": False,
            "scope": "Actual board experiments; negative timing is retained, DRC failures are never programmed.",
        }

    def save(self, phase: str | None = None) -> None:
        if phase:
            self.report["phase"] = phase
        self.report["updated_at"] = now()
        atomic_json(self.report_path, self.report)

    def command(self, argv: list[str], log: Path, phase: str, owner: dict) -> dict:
        record = {"argv": argv, "stdout_log": str(log), "started_at": now(), "status": "RUNNING"}
        owner.setdefault("commands", []).append(record)
        with log.open("w", encoding="utf-8") as stream:
            process = subprocess.Popen(argv, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                       shell=False, stdin=subprocess.DEVNULL)
            record["pid"] = process.pid
            self.save(phase)
            try:
                record["returncode"] = process.wait()
            except KeyboardInterrupt:
                record["status"] = "INTERRUPTED_CHILD_MAY_STILL_RUN"
                record["finished_at"] = now()
                self.save("interrupted")
                raise
        record.update(status="FINISHED", finished_at=now())
        self.save()
        return record

    def build_argv(self, hz: int, build: Path) -> list[str]:
        argv = [self.args.pwsh, "-NoProfile", "-File", str(ROOT / "scripts/run_board.ps1"),
                "-Mode", "Build", "-App", "coremark", "-CpuHz", str(hz),
                "-Iterations", str(self.args.iterations), "-BuildDir", str(build),
                "-Python", sys.executable, "-Jobs", str(self.args.jobs)]
        if self.args.toolchain_bin:
            argv += ["-ToolchainBin", str(self.args.toolchain_bin)]
        if self.args.vivado:
            argv += ["-Vivado", str(self.args.vivado)]
        return argv

    def program_argv(self, build: Path, timing_met: bool) -> list[str]:
        argv = [self.args.pwsh, "-NoProfile", "-File", str(ROOT / "scripts/run_board.ps1"),
                "-Mode", "Program", "-BuildDir", str(build)]
        if not timing_met:
            argv += ["-AllowTimingFailure"]
        if self.args.target:
            argv += ["-Target", self.args.target]
        if self.args.vivado:
            argv += ["-Vivado", str(self.args.vivado)]
        return argv

    def capture_argv(self, hz: int, output: Path) -> list[str]:
        return [str(self.args.capture_python), "-B", str(ROOT / "scripts/board_capture.py"),
                "--port", self.args.port, "--duration", str(self.args.duration),
                "--until", "COREMARK_RESULT", "--cpu-hz", str(hz),
                "--require-valid-coremark", "--output", str(output)]

    def attempt(self, point: dict, number: int) -> dict:
        build = Path(point["build_dir"])
        directory = build / f"attempt_{number:02d}"
        directory.mkdir()
        capture_dir = directory / "capture"
        attempt = {"number": number, "started_at": now(), "status": "RUNNING",
                   "output": str(directory), "capture_output": str(capture_dir)}
        point.setdefault("attempts", []).append(attempt)
        log_path = directory / "capture_stdout.log"
        argv = self.capture_argv(point["cpu_hz"], capture_dir)
        capture_record = {"argv": argv, "started_at": now(), "stdout_log": str(log_path), "status": "RUNNING"}
        attempt["capture_process"] = capture_record
        with log_path.open("w", encoding="utf-8") as log:
            capture = subprocess.Popen(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                       shell=False, stdin=subprocess.DEVNULL)
            self.current_capture = capture
            capture_record["pid"] = capture.pid
            self.save(f"capture_ready_wait_{point['mhz']}MHz_attempt{number}")
            ready_path = capture_dir / "ready.json"
            capture_started = time.monotonic()
            deadline = capture_started + self.args.ready_timeout
            while not ready_path.is_file() and capture.poll() is None and time.monotonic() < deadline:
                time.sleep(0.1)
            if capture.poll() is not None or not ready_path.is_file():
                attempt.update(status="TOOL_BLOCKED", reason="capture did not become ready/alive; no programming attempted")
                if capture.poll() is None:
                    capture.terminate()
                    capture.wait(timeout=10)
            else:
                ready = load_json(ready_path)
                attempt["capture_ready"] = ready
                before_program = set(build.glob("program_*.json"))
                attempt["program_started_at"] = now()
                program = self.command(self.program_argv(build, point["timing"]["timing_met"]),
                                       directory / "program_stdout.log", f"program_{point['mhz']}MHz_attempt{number}", attempt)
                new_records = sorted(set(build.glob("program_*.json")) - before_program)
                accepted = []
                for path in new_records:
                    evidence = load_json(path)
                    if (evidence.get("bitstream_sha256") == point["bitstream_sha256"] and
                            any(marker.startswith("BOARD_PROGRAM_SUCCESS ") for marker in evidence.get("success_marker", []))):
                        accepted.append({"path": str(path), "sha256": sha256(path), "record": evidence})
                program_verified = (program["returncode"] == 0 and len(accepted) == 1 and
                                    sha256(build / "hellozynq.bit") == point["bitstream_sha256"])
                attempt["program_verified"] = program_verified
                attempt["program_evidence"] = accepted
                if not program_verified:
                    attempt.update(status="TOOL_BLOCKED", reason="JTAG/DONE success was not verified")
                    if capture.poll() is None:
                        capture.terminate()
                remaining = self.args.duration + 15 - (time.monotonic() - capture_started)
                try:
                    capture.wait(timeout=max(1, remaining))
                except subprocess.TimeoutExpired:
                    capture.terminate()
                    capture.wait(timeout=10)
                    attempt.update(status="TOOL_BLOCKED", reason="capture process exceeded its own bounded duration")
                result_path = capture_dir / "capture_result.json"
                if attempt["status"] != "TOOL_BLOCKED":
                    if not result_path.is_file():
                        attempt.update(status="TOOL_BLOCKED", reason="capture produced no structured result; inspect tool log")
                    else:
                        result = load_json(result_path)
                        attempt["capture_result"] = result
                        attempt["capture_result_sha256"] = sha256(result_path)
                        raw = capture_dir / "rx.bin"
                        if not raw.is_file() or sha256(raw) != result.get("raw_sha256"):
                            attempt.update(status="TOOL_BLOCKED", reason="capture raw-byte evidence missing or hash mismatch")
                        else:
                            attempt["capture_artifacts"] = {path.name: {"path": str(path), "sha256": sha256(path)}
                                for path in capture_dir.iterdir() if path.is_file()}
                            # A matching BOOT must have arrived after programming
                            # started; old output from the previous image cannot pass.
                            expected_boot = f"[COREMARK] BOOT build={point['firmware_build_id']} ".encode()
                            assembled = bytearray()
                            boot_seen = False
                            for line in (capture_dir / "rx.jsonl").read_text(encoding="utf-8-sig").splitlines():
                                event = json.loads(line)
                                previous_length = len(assembled)
                                assembled.extend(bytes.fromhex(event.get("rx_hex", "")))
                                new_match = assembled.find(expected_boot, max(0, previous_length - len(expected_boot) + 1))
                                if new_match >= 0 and event["utc"] >= attempt["program_started_at"]:
                                    boot_seen = True
                                    break
                            attempt["matching_boot_after_program_start"] = boot_seen
                            if result.get("status") == "TIMEOUT" and result.get("finished_at", "") < program["finished_at"]:
                                status, reason = "TOOL_BLOCKED", "capture timed out before programming completed; no frequency verdict"
                            else:
                                status, reason = classify_capture(result, capture.returncode, program_verified,
                                                                  point["cpu_hz"], boot_seen)
                            attempt.update(status=status, reason=reason)
            capture_record.update(returncode=capture.returncode, finished_at=now(), status="FINISHED")
            self.current_capture = None
        attempt["finished_at"] = now()
        self.save()
        return attempt

    def run(self) -> int:
        self.output.mkdir(parents=True, exist_ok=False)
        self.save("starting")
        try:
            for mhz in range(self.args.start_mhz, self.args.max_mhz + 1, self.args.step_mhz):
                build = self.output / f"coremark_{mhz:03d}MHz"
                build.mkdir()
                point = {"mhz": mhz, "cpu_hz": mhz * 1_000_000, "build_dir": str(build),
                         "started_at": now(), "status": "BUILDING"}
                self.report["points"].append(point)
                print(f"CAMPAIGN_BUILD_START mhz={mhz} build={build}", flush=True)
                command = self.command(self.build_argv(point["cpu_hz"], build), build / "build_stdout.log",
                                       f"build_{mhz}MHz", point)
                summary_path = build / "build_summary.json"
                if not summary_path.is_file():
                    point.update(status="TOOL_BLOCKED", reason="build produced no structured summary; no frequency verdict")
                else:
                    summary = load_json(summary_path)
                    vendor = summary.get("vivado_result") or {}
                    point["timing"] = {key: vendor.get(key) for key in
                                       ("status", "timing_met", "setup_slack_ns", "hold_slack_ns", "drc_met", "serious_drc_count")}
                    point["build_summary"] = {"path": str(summary_path), "sha256": sha256(summary_path)}
                    bit = build / "hellozynq.bit"
                    firmware = summary.get("firmware") or {}
                    point["firmware_build_id"] = firmware.get("build_id")
                    point["firmware_artifacts"] = firmware.get("artifacts", {})
                    point["firmware_manifest"] = str(build / "firmware/manifest.json")
                    if command["returncode"] != 0:
                        point.update(status="TOOL_BLOCKED", reason="build command failed; retained tool/DRC/timing evidence is not a CoreMark failure")
                    elif (not vendor.get("drc_met") or not vendor.get("bitstream_written") or
                            not bit.is_file() or not point["firmware_build_id"] or
                            summary.get("source_changed_during_build")):
                        point.update(status="TOOL_BLOCKED", reason="DRC/image/source-integrity gate failed; programming skipped")
                    elif (summary.get("config", {}).get("cpu_hz") != point["cpu_hz"] or
                          firmware.get("cpu_hz") != point["cpu_hz"] or firmware.get("app") != "coremark" or
                          firmware.get("iterations") != self.args.iterations or
                          sha256(bit) != summary.get("bitstream_sha256")):
                        point.update(status="TOOL_BLOCKED", reason="image/config/hash differs from requested experiment")
                    else:
                        point["bitstream_sha256"] = sha256(bit)
                        point["bitstream"] = str(bit)
                        point["status"] = "CAPTURING"
                        self.save()
                        first = self.attempt(point, 1)
                        point.update(status=first["status"], reason=first["reason"])
                        observed = first.get("capture_result", {})
                        point["coremark"] = observed.get("coremark")
                        point["capture_valid_coremark"] = observed.get("valid_coremark", False)
                        if first["status"] == "PASS":
                            self.report["last_pass"] = {"mhz": mhz, "build_dir": str(build),
                                "capture_result": str(Path(first["capture_output"]) / "capture_result.json")}
                        elif first["status"] == "COREMARK_FAIL":
                            self.report["first_fail"] = {"mhz": mhz, "build_dir": str(build),
                                "capture_result": str(Path(first["capture_output"]) / "capture_result.json")}
                            if self.args.confirm_failure:
                                confirmation = self.attempt(point, 2)
                                point["failure_confirmation"] = confirmation["status"]
                                point["failure_reproduced"] = confirmation["status"] == "COREMARK_FAIL"
                point["finished_at"] = now()
                print(f"CAMPAIGN_POINT_RESULT mhz={mhz} status={point['status']}", flush=True)
                self.save()
                if point["status"] != "PASS":
                    self.report["status"] = "FREQUENCY_FAILURE_FOUND" if point["status"] == "COREMARK_FAIL" else "TOOL_BLOCKED"
                    break
            else:
                self.report["status"] = "RANGE_COMPLETED"
            self.report["finished_at"] = now()
            self.save("finished_no_automatic_restore")
            return 0 if self.report["status"] == "RANGE_COMPLETED" else 2 if self.report["status"] == "TOOL_BLOCKED" else 1
        except BaseException as error:
            self.report.update(status="INTERRUPTED" if isinstance(error, KeyboardInterrupt) else "TOOL_BLOCKED",
                               exception=f"{type(error).__name__}: {error}", finished_at=now())
            if self.current_capture is not None and self.current_capture.poll() is None:
                self.current_capture.terminate()
                self.report["terminated_capture_pid"] = self.current_capture.pid
            self.save("interrupted_or_tool_error_no_automatic_restore")
            raise


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start-mhz", type=int, default=60)
    parser.add_argument("--step-mhz", type=int, choices=(5, 10), default=10)
    parser.add_argument("--max-mhz", type=int, default=400)
    parser.add_argument("--iterations", type=int, default=0)
    parser.add_argument("--root-output", type=Path, required=True)
    parser.add_argument("--port", default="COM6")
    parser.add_argument("--duration", type=float, default=180)
    parser.add_argument("--ready-timeout", type=float, default=15)
    parser.add_argument("--confirm-failure", action="store_true", help="repeat the first failed frequency once; then stop")
    parser.add_argument("--capture-python", type=Path, default=CAPTURE_PYTHON)
    parser.add_argument("--pwsh", default="pwsh")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--vivado", type=Path)
    parser.add_argument("--toolchain-bin", type=Path)
    parser.add_argument("--target", default="")
    parser.add_argument("--plan-only", action="store_true", help="print commands; create no directories and start no processes")
    args = parser.parse_args()
    if not 5 <= args.start_mhz <= args.max_mhz <= 400 or args.start_mhz % 5 or args.max_mhz % 5:
        parser.error("range must be multiples of 5 MHz within 5..400 MHz")
    if not 0 <= args.iterations <= 1_000_000_000:
        parser.error("--iterations must be 0..1000000000")
    if args.duration < 30 or args.ready_timeout <= 0 or not 1 <= args.jobs <= 32:
        parser.error("duration must be >=30 seconds, ready-timeout positive, jobs 1..32")
    return args


def main() -> int:
    args = arguments()
    campaign = Campaign(args)
    if args.plan_only:
        print(json.dumps([{"mhz": mhz, "build": campaign.build_argv(mhz * 1_000_000, campaign.output / f"coremark_{mhz:03d}MHz"),
                           "capture": campaign.capture_argv(mhz * 1_000_000, campaign.output / f"coremark_{mhz:03d}MHz/attempt_01/capture"),
                           "program_timing_met": campaign.program_argv(campaign.output / f"coremark_{mhz:03d}MHz", True),
                           "program_timing_failed": campaign.program_argv(campaign.output / f"coremark_{mhz:03d}MHz", False)}
                          for mhz in range(args.start_mhz, args.max_mhz + 1, args.step_mhz)], indent=2))
        return 0
    if not args.capture_python.is_file() or not shutil.which(args.pwsh):
        raise RuntimeError("capture Python or pwsh is missing; no campaign started")
    if campaign.output.exists():
        raise RuntimeError("--root-output must be new; prior campaign evidence will not be overwritten")
    return campaign.run()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("CAMPAIGN_INTERRUPTED: inspect campaign.json PIDs before another run", file=sys.stderr)
        raise SystemExit(130)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"CAMPAIGN_TOOL_BLOCKED: {error}", file=sys.stderr)
        raise SystemExit(2)
