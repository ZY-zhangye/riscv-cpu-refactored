# RV32 Divider Refactor Handoff

## Scope and baseline

- Target FPGA part: `xc7k325tffg900-2` (Kintex-7 family).
- The Vivado project does not declare a `BoardPart`; the confirmed board-level
  identity is therefore the FPGA part and the existing JYD2025 pin constraints,
  not a named commercial board model.
- The legacy Divider Generator configuration is 32/32 unsigned Radix-2 with
  `C_LATENCY=35` in `vivado-project/jyd2025-reference/ip/divider/divider.xci`.
- `rtl/cpu_top/divider.sv` is a debug-only behavioral model with a separate
  nominal 10-cycle counter. That number is not the implemented hardware IP
  latency and must not be used for FPGA timing comparisons.
- The reciprocal divider is now connected to both CPU execute lanes through
  `rtl/cpu_top/mul.sv`; the active root RTL no longer calls the legacy Divider
  Generator for DIV/REM operations.

## Implemented module

Files:

- `rtl/cpu_top/rv32_div_rcp.sv`
- `rtl/cpu_top/rv32_recip_rom.sv`
- `rtl/cpu_top/rv32_recip_lut_f40.mem`

The module implements exact RV32 `DIV`, `DIVU`, `REM`, and `REMU` results:

1. Capture the request and classify divide-by-zero and signed overflow.
2. Compute signed magnitudes in `ST_SETUP`.
3. In `ST_NORMALIZE`, compute LZC, normalize the divisor, and form the ROM
   bucket from registered data. This is the input pipeline boundary added for
   the 160 MHz timing target.
4. Read a 40-bit reciprocal seed from a synchronous 65536-entry ROM.
5. Perform one Goldschmidt correction and reconstruct the correction product
   using two narrow partial products. `b_nr_pipe_reg` is an additional
   physical register in the existing `ST_REFINE` slot; it does not add a cycle.
6. Form an exact quotient product, check the remainder, apply at most one
   quotient correction, and restore signs.

There is no runtime `/` or `%` operator in the datapath. The only slash in the
RTL arithmetic is an elaboration-time parameter width expression.

## Latency contract

- Normal request: 14 clock intervals from accepted request edge to `done`.
- Divide-by-zero and `INT_MIN / -1`: 2 clock intervals.
- `req_ready` is asserted only in `ST_IDLE`; `done` is a one-cycle pulse and
  the result ports retain their last registered value.
- The CPU wrapper holds a completed result until EX is accepted, and cancels
  an in-flight request when the resident operation is flushed.

The normal path is 21 cycles shorter than the 35-cycle hardware IP (about
2.5x lower operation latency at the same clock). The special paths are 33
cycles shorter.

## Verification

QuestaSim 2024.1 was used from `PATH`:

```text
vlog -sv rtl/cpu_top/rv32_recip_rom.sv rtl/cpu_top/rv32_div_rcp.sv test/tb_rv32_div_rcp.sv
vsim -c -onfinish stop tb_rv32_div_rcp +N=100000 +BUCKETS=65536 -do "run -all; quit -code [coverage attribute -name TESTSTATUS -concise]"
```

Final result: `RCP_DIVIDER_TEST_PASSED checks=331279`, compiler errors and
warnings both zero. Coverage includes all ROM bucket endpoints, 100000 random
pairs, all LZC values 0..31 in signed and unsigned modes, signed magnitude
boundaries, divide-by-zero, overflow, quotient/remainder sign rules, fixed
latency, and changing inputs while busy.

## Single-module OOC timing

Vivado 2023.2 was run only on `rv32_div_rcp` plus its ROM, with no CPU top and
no legacy Divider IP. Report directory:

`F:/Tools/vivado-ooc/rv32-div-rcp-f40-split2`

Constraints use a 6.250 ns clock (160 MHz) and 0.200 ns setup uncertainty.
Post-route result:

| Metric | Result |
| --- | ---: |
| Setup WNS | `+0.522 ns` |
| Setup TNS | `0.000 ns` |
| Hold WHS | `-0.389 ns` |
| DSP48E1 | `16` |
| RAMB36E1 | `80` |
| LUT | `2862` |
| FF | `2235` |
| Routed nets | `4465 / 4465` |

The worst setup path is `seed_reg -> b_nr_reg`, with 4.471 ns data-path
delay. The reported hold violation is exclusively an OOC input-boundary path
(`dividend[*] -> raw_dividend_reg`) under `set_input_delay -min 0` and an
unmodeled board clock/pin delay; it is not an internal register-to-register
hold path. A board-level signoff must replace these placeholder I/O delays
with the real clock and pin constraints.

## CPU integration

`rtl/cpu_top/mul.sv` now:

- sends raw RV32 operands and the signed/remainder mode directly to
  `rv32_div_rcp`;
- issues one request per resident DIV/REM uop;
- tracks in-flight and held-result state independently;
- preserves a completion while MEM or the other lane applies backpressure;
- consumes a result only on `op_accept`; and
- drives the divider `cancel` input on flush/kill.

`rtl/cpu_top/exe_stage.sv` supplies `op_valid`, `op_accept`, and `op_kill` from
the real EX lifecycle. The current issue policy allows a mul/div uop in either
lane, so each lane instantiates its own divider. No shared-divider arbitration
was introduced in this integration.

The exception path was also corrected while closing the integration gate:

- `if_stage.sv` clears a pending registered branch redirect whenever an older
  trap is asserted, so a younger `j fail` cannot replay after `mtvec` wins;
- SYSTEM decode now matches the complete ECALL/EBREAK/MRET encodings;
- `regfile_csr.sv` tracks the current privilege and `mstatus.MPP`, resolves
  ECALL cause 8/9/11, and performs MRET redirection even without a prior trap.

## CPU-level verification

QuestaSim 2024.1 results after integration:

- full RTL/test compilation: 0 errors, 0 warnings;
- standalone divider: `RCP_DIVIDER_TEST_PASSED checks=331279`;
- wrapper hold/cancel/special cases: `MUL_SPECIAL_TEST_PASSED`;
- RAS/flush recovery: `IF_RAS_RECOVERY_TEST_PASSED`;
- CSR privilege/cause and standalone MRET checks: `PERF COUNTER TEST PASSED`;
- RV32I: 37/37 passed;
- RV32M: 8/8 passed, including DIV/DIVU/REM/REMU;
- implemented Z extensions: 28/28 passed; and
- seven pipeline/infrastructure unit tests passed.

The complete `run_all.bat all` regression is now green: `scall`, `sbreak`,
`csr`, and `ma_fetch` all pass, in addition to the RV32I/RV32M/Z groups.

The frozen nine-window benchmark was executed with `PERF_BENCH`, whose reset
PC and linked `_start` are both `0x00000000`. Runtime fetch/writeback PCs were
observed in the zero-based image. The result was:

| Metric | Result |
| --- | ---: |
| Sink | `0x9D3BF787` |
| Reports | `9 / 9` |
| Exceptions | `0` in every window |
| Cycles | `1,806,178` |
| Instructions retired | `2,279,455` |
| Reported IPC | `1.262` |
| Exact retired/cycle ratio | `1.262032314` |
| Throughput at the 160 MHz target | `201.925 MIPS` |

The benchmark image still reports 125 MHz in its mailbox metadata; this does
not affect the cycle/instruction IPC calculation. Relative to the historical
35-cycle IP-equivalent result (`1.149` IPC), the integrated divider improves
IPC by about 9.84%. It is about 0.89% below the historical 10-cycle DEBUG
divider result.

## Remaining build notes

- No full-core Vivado synthesis was run. Only the standalone divider OOC
  result above is a hardware timing/resource result.
- The archived-source Vivado scripts under
  `vivado-project/jyd2025-reference/scripts` do not automatically consume the
  active root RTL and do not currently add `rv32_recip_lut_f40.mem`. Before a
  future FPGA build, synchronize the selected source set and add the ROM file.
- The validated configuration keeps `MULTICYCLE_ENABLE` enabled and does not
  define `L3Q_MULDIV_BLOCKING_BYPASS`. The latter configuration has an existing
  flush/pending-state risk and should not be enabled without a directed fix and
  regression.
