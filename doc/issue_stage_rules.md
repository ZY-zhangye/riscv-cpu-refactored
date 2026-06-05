# Issue Stage Rules

This document records the first safe baseline rules for `rtl/cpu_top/issue_stage.sv`.

## Ordering

- Program order must never change.
- The lower-address instruction is always older.
- In `IDLE`, a safe pair issues as:
  - older instruction to lane0
  - younger instruction to lane1
- If the pair is unsafe, only the older instruction issues to lane0 and the younger instruction remains buffered.
- In `LANE0`, only lane0 may issue. Lane1 stays invalid until the buffered single instruction is drained.

## Buffering

- Issue owns a 2-entry holding buffer: `buf0` is older and `buf1` is younger.
- IF provides one fetch packet containing `fs_to_is_bus` and `fs_to_is_bus1`, guarded by shared `fs_to_is_valid`.
- Issue asserts `is_allowin` only when it can accept both instructions without dropping buffered instructions.
- If the buffer is full and no pair is consumed, IF must stall.

## Pairing

The first baseline only allows simple integer pairs.

A pair may issue together only when all of the following are true:

- Both buffer entries are valid.
- Both instructions are simple integer instructions.
- The older instruction does not write a GPR that the younger instruction reads.
- Both instructions do not write the same non-x0 GPR.
- `ds_allowin` and `ds_allowin1` are both asserted.

The first baseline does not implement same-cycle lane0-to-lane1 forwarding.

## Forced Single Issue

The pair must fall back to ordered lane0-only issue if either instruction is:

- load or store
- branch or jump
- CSR, system, or fence
- FPU
- multiply/divide or another multicycle instruction
- unknown or not known to be safe

## Flush

- `br_taken || exception_flag` is a global issue flush.
- During global flush:
  - valid issue lanes keep moving forward when downstream allows them
  - flushed instructions carry `is_flush` / `is_flush1` to later pipeline stages
  - issue buffer entries consumed by the flush cycle are cleared
  - `is_flush` and `is_flush1` are asserted for one cycle
- This also applies in `LANE0`: if the older instruction has already issued and the younger instruction is buffered, a branch redirect or exception redirect must clear the buffered instruction and assert both flush signals.
