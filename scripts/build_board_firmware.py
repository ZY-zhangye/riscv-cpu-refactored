#!/usr/bin/env python3
"""Native, dependency-free HelloZynq firmware build and ELF/image validation."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REGIONS = {"instruction": (0x80000000, 16 * 1024), "data": (0x80100000, 256 * 1024)}
DEFAULT_TOOLCHAIN = Path("F:/Tools/Apps/xpack-riscv-none-elf-gcc-15.2.0-1/bin")


def run(command: list[str]) -> str:
    result = subprocess.run(command, text=True, capture_output=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}{result.stderr}")
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    return result.stdout


def parse_elf(path: Path) -> tuple[dict, dict[str, bytearray]]:
    content = path.read_bytes()
    if content[:7] != b"\x7fELF\x01\x01\x01":
        raise RuntimeError("expected ELF32, little endian, ELF version 1")
    header = struct.unpack_from("<16sHHIIIIIHHHHHH", content)
    _, kind, machine, _, entry, _, sections_at, flags, _, _, _, section_size, section_count, names_index = header
    if kind != 2 or machine != 243 or entry != REGIONS["instruction"][0]:
        raise RuntimeError(f"unexpected ELF type/machine/entry: {kind}/{machine}/{entry:#x}")
    if flags & 0xF:
        raise RuntimeError(f"compressed, non-soft-float, or RVE ELF flags are forbidden: {flags:#x}")
    sections = [struct.unpack_from("<IIIIIIIIII", content, sections_at + i * section_size)
                for i in range(section_count)]
    names = sections[names_index]
    name_bytes = content[names[4]: names[4] + names[5]]
    images = {name: bytearray(length) for name, (_, length) in REGIONS.items()}
    allocated = []
    for section in sections:
        name_at, section_type, section_flags, address, offset, size, *_ = section
        if not section_flags & 2 or not size:
            continue
        name = name_bytes[name_at:].split(b"\0", 1)[0].decode("ascii")
        region = next((name for name, (base, length) in REGIONS.items()
                       if base <= address and address + size <= base + length), None)
        if region is None:
            raise RuntimeError(f"allocated section {name} outside memory regions: {address:#x}+{size:#x}")
        if section_flags & 4 and region != "instruction":
            raise RuntimeError(f"executable section {name} is outside IROM")
        base, _ = REGIONS[region]
        if section_type != 8:  # NOBITS .bss is zeroed by board_start.S.
            payload = content[offset:offset + size]
            if len(payload) != size:
                raise RuntimeError(f"truncated section {name}")
            images[region][address - base:address - base + size] = payload
        allocated.append({"name": name, "address": f"0x{address:08X}", "bytes": size,
                          "region": region, "zero_initialized": section_type == 8})
    return {"elf_class": 32, "endianness": "little", "machine": "RISC-V", "entry": f"0x{entry:08X}",
            "elf_flags": flags, "allocated_sections": allocated}, images


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, choices=("smoke", "coremark"))
    parser.add_argument("--cpu-hz", type=int, default=50_000_000)
    parser.add_argument("--iterations", type=int, default=0, help="CoreMark: 0 calibrates, >0 fixes iterations")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--toolchain-bin", type=Path, default=DEFAULT_TOOLCHAIN)
    args = parser.parse_args()
    if not 1_000_000 <= args.cpu_hz <= 200_000_000:
        parser.error("--cpu-hz must be 1000000..200000000")
    if not 0 <= args.iterations <= 0x7FFFFFFF:
        parser.error("--iterations must be 0..2147483647")
    output = (args.output or ROOT / "build/hello_zynq/firmware" / args.app).resolve()
    output.mkdir(parents=True, exist_ok=True)
    # A failed rebuild must not leave a prior successful manifest looking current.
    manifest_path = output / "manifest.json"
    if manifest_path.exists():
        manifest_path.unlink()
    tools = {}
    for name in ("gcc", "objdump", "readelf", "nm", "size"):
        candidate = args.toolchain_bin / f"riscv-none-elf-{name}.exe"
        if not candidate.is_file():
            candidate = args.toolchain_bin / f"riscv-none-elf-{name}"
        if not candidate.is_file():
            raise RuntimeError(f"missing tool: {candidate}")
        tools[name] = str(candidate)
    platform = ROOT / "board_tests/platform"
    sources = [platform / "board_start.S", platform / "board_runtime.c"]
    if args.app == "smoke":
        sources += [ROOT / "board_tests/00_smoke/main.c"]
    else:
        sources += sorted((ROOT / "board_tests/05_coremark/src").glob("*.c"))
    flags = ["-Os", "-g", "-Wall", "-Wextra", "-march=rv32im_zicsr", "-mabi=ilp32", "-mcmodel=medany",
             "-ffreestanding", "-fno-builtin", "-fno-common", "-fno-pic", "-fno-pie",
             "-fno-stack-protector", "-fno-asynchronous-unwind-tables", "-fno-unwind-tables",
             "-ffunction-sections", "-fdata-sections", "-msmall-data-limit=0", "-mno-relax"]
    hashed_paths = sources + [platform / "board_linker.ld", platform / "board_runtime.h",
                              platform / "my_cpu_mmio.h", Path(__file__).resolve()]
    if args.app == "coremark":
        hashed_paths += sorted((ROOT / "board_tests/05_coremark/src").glob("*.h"))
    source_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in hashed_paths}
    compiler_version = run([tools["gcc"], "--version"]).splitlines()[0]
    build_id = hashlib.sha256(json.dumps([source_hashes, compiler_version, args.app, args.cpu_hz, args.iterations, flags],
                                       sort_keys=True).encode()).hexdigest()[:12]
    defines = [f"-DBOARD_CPU_HZ={args.cpu_hz}u", f"-DITERATIONS={args.iterations}",
               f'-DBOARD_BUILD_ID="{build_id}"', f'-DBOARD_COMPILER_FLAGS="{" ".join(flags)}"']
    elf = output / "firmware.elf"
    command = [tools["gcc"], *flags, *defines, "-I", str(platform), *map(str, sources),
               "-nostdlib", "-Wl,--no-relax,--gc-sections,--build-id=none",
               f"-Wl,-T,{platform / 'board_linker.ld'}", f"-Wl,-Map,{output / 'firmware.map'}",
               "-o", str(elf), "-lgcc"]
    run(command)
    checks, images = parse_elf(elf)
    undefined = run([tools["nm"], "-u", str(elf)]).strip()
    if undefined:
        raise RuntimeError(f"undefined symbols:\n{undefined}")
    attributes = run([tools["readelf"], "-A", str(elf)])
    match = re.search(r'Tag_RISCV_arch:\s*"([^"]+)"', attributes)
    if not match:
        raise RuntimeError("missing ISA attributes")
    isa = match.group(1)
    extensions = [re.sub(r"\d.*", "", part) for part in isa.removeprefix("rv32").split("_")]
    if not set(extensions) <= {"i", "m", "zicsr", "zmmul"} or not {"i", "m", "zicsr"} <= set(extensions):
        raise RuntimeError(f"unexpected ISA; no C/F/D/A or other extensions allowed: {isa}")
    checks.update({"isa": isa, "undefined_symbols": 0, "no_compressed_atomic_float": True,
                   "capacity_checks": "passed", "abi": "ilp32"})
    (output / "firmware.dump").write_text(run([tools["objdump"], "-d", str(elf)]), encoding="utf-8")
    (output / "firmware.attributes.txt").write_text(attributes, encoding="utf-8")
    size = run([tools["size"], str(elf)]).strip()
    for name, image in images.items():
        stem = "inst" if name == "instruction" else "data"
        words = [f"{word[0]:08X}" for word in struct.iter_unpack("<I", image)]
        text = "\n".join(words) + "\n"
        for suffix in ("mem", "hex"):
            (output / f"{stem}.{suffix}").write_text(text, encoding="ascii")
        (output / f"{stem}.coe").write_text("memory_initialization_radix=16;\nmemory_initialization_vector=\n" +
                                          ",\n".join(words) + ";\n", encoding="ascii")
    artifact_names = ("firmware.elf", "firmware.dump", "firmware.map", "inst.mem", "data.mem",
                      "inst.hex", "data.hex", "inst.coe", "data.coe")
    manifest = {"schema_version": 1, "app": args.app, "build_id": build_id, "cpu_hz": args.cpu_hz,
                "iterations": args.iterations, "uart_baud": 115200,
                "uart_baud_register": (args.cpu_hz + 57600) // 115200 - 1,
                "uart_control_register": "0x14", "entry": checks["entry"], "elf_checks": checks,
                "regions": {name: {"base": f"0x{base:08X}", "bytes": length, "words": length // 4}
                            for name, (base, length) in REGIONS.items()},
                "stack_reserved_bytes": 8192, "compiler": compiler_version,
                "compile_command": command, "source_sha256": source_hashes, "size": size,
                "artifacts": {name: {"path": str(output / name), "sha256": hashlib.sha256((output / name).read_bytes()).hexdigest()}
                              for name in artifact_names},
                "verification_scope": "Compile/link/image checks only; hardware execution is not implied.",
                "expected_marker": "SMOKE_PASS" if args.app == "smoke" else "COREMARK_RESULT",
                "coremark_score_policy": "CRC pass and actual timer duration >=10s; SHORT never reports a valid score."}
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(size)
    print(f"FIRMWARE_BUILD_PASS app={args.app} cpu_hz={args.cpu_hz} manifest={manifest_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, struct.error) as error:
        print(f"FIRMWARE_BUILD_FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
