# RV32M Multiply/Divide IP

This directory packages the final RV32M execution unit independently of the CPU
pipeline. It is a reusable RTL IP snapshot; no Vivado project is required.

## Files

- `rtl/rv32m_mul_div_ip.sv` — RV32M operation controller and result selection.
- `rtl/rv32m_mul_pipeline_ip.sv` — pipelined 32-bit multiply implementation.
- `rtl/rv32m_divider_model_ip.sv` — AXI-Stream compatible divider behavioural
  model for RTL simulation.

## Integration

Instantiate `rv32m_mul_div_ip` in an execute stage. Its ports match the former
CPU-local `mul` unit: `is_mul`, `is_multicycle`, `mul_src1`, `mul_src2`,
`mul_op`, signedness flags, `result_ready`, and `kill`; it returns `mul_result`
and `mul_stall`.

`mul_op[3:0]` uses the CPU's established RV32M encoding: bits `[3]`/`[2]`
select low/high multiply and bits `[1]`/`[0]` select divide/remainder. The
controller handles divide-by-zero, signed `INT_MIN / -1`, and pipeline-flush
draining of an already accepted divider response.

## Parameters

- `MUL_HIGH_PIPE_STAGES`: `2` or `3`; default `3` for the final timing-oriented
  implementation. Low-word `MUL` completes in two cycles.
- `DIVIDER_RESULT_REMAINDER_HIGH`: set to `1` for the bundled behavioural model
  (`{remainder, quotient}`), or `0` for the Vivado Divider Generator output
  convention (`{quotient, remainder}`).

For FPGA implementation, replace only the `rv32m_divider_model_ip` instance
with the generated Divider Generator IP and set
`DIVIDER_RESULT_REMAINDER_HIGH` to `0`. The AXI-Stream ports are intentionally
kept compatible.

## Notes

The multiply pipeline requests DSP inference for the four 16x16 partial
products. The controller and model are synthesizable, but the behavioural
divider is intended for functional simulation; use the generated divider IP
for the target FPGA implementation.
