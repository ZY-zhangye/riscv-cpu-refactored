# HelloZynq bare-metal firmware

Build on Windows with Python 3 and the installed xPack toolchain:

```powershell
python scripts/build_board_firmware.py --app smoke --cpu-hz 50000000
python scripts/build_board_firmware.py --app coremark --cpu-hz 50000000 --iterations 0
```

`--output` selects the exact output directory; its default is
`build/hello_zynq/firmware/<app>`. `--toolchain-bin` overrides the default
`F:/Tools/Apps/xpack-riscv-none-elf-gcc-15.2.0-1/bin`.

Each build emits `firmware.elf`, map/disassembly, `inst.mem`/`data.mem`, matching
HEX/COE files, and `manifest.json` with source/artifact SHA-256 hashes, frequency,
UART divisor, compiler command, and ELF validation results. Instructions occupy
`0x80000000..0x80003fff`; initialized data and constants occupy
`0x80100000..0x8013ffff`. The data region reserves an 8 KiB stack at its top.
Images contain exactly 4096 and 65536 little-endian 32-bit words respectively,
with zero-filled gaps. Both images must enter the board's memory initialization.
The startup sets SP/mtvec, disables interrupts, clears BSS, and calls main;
it does not copy data from instruction memory or rely on WFI.

The build uses RV32IM+Zicsr / ILP32, disables small-data addressing and linker
relaxation, and rejects non-RV32/little-endian ELFs, wrong entry, unsupported
ISA attributes, undefined symbols, and out-of-range allocated sections.
It does not invoke Vivado, program hardware, or open a serial port.

At 50 MHz the UART writes BAUD=433 and CTRL=0x14 for 115200/8N1. Polling
transmission has a 100 ms timeout and records a persistent UART fault.
Only the board's two LED bits are physically visible; full error values remain
in the LED register and trap details in `board_trap_mcause`.

Smoke prints an immediate BOOT line, then tests initialized data, BSS, constants,
recursive stack frames, byte/halfword/word RAM access, MUL/DIV/REM, UART register
readback, Timer countdown, and LED MMIO readback. It reports `SMOKE_PASS` or
`SMOKE_FAIL code=...`. After success it echoes received bytes; this simple echo
does not implement the older board test project's PING/ECHO line protocol.

CoreMark keeps the existing benchmark algorithms and official reporting path.
Its port prints a BOOT banner before calibration. `--iterations 0` uses the
official auto-calibration; fixed small iterations are useful for functional
simulation. A prescaled hardware timer near 1 MHz extends the measurement window
to about 71 minutes. Frequencies that do not divide 1 MHz exactly still use the
exact CPU frequency and divider in time/score arithmetic. The timer has 32-bit
ticks; a single timing interval must remain below one complete timer wrap.

The port observes the official known-seed and CRC output and adds:

* `COREMARK_CRC status=PASS|FAIL list=... matrix=... state=...`
* `COREMARK_RESULT status=PASS|SHORT|FAIL valid=... score_x1000=...`
  with exact iterations, timer-derived CPU cycles, duration and CPU frequency.

`SHORT` means the CRC passed but the run did not satisfy the performance duration
requirement. A score is emitted only after official validation, correct CRCs,
at least 10 seconds according to the hardware timer, and no UART fault. Integer
64-bit arithmetic prints iterations/second and score/MHz to six decimal places.
The 32-bit cycle CSR delta is also printed as an independent modulo counter;
the prescaled timer supplies duration for longer runs. These are firmware
measurements; building a valid image alone does not establish a board result or
an independently certified CoreMark submission.
