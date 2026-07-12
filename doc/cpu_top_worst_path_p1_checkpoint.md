# cpu_top 175 MHz Worst Path P1 Checkpoint

## Input Path

The integrated quick-synth worst path was:

```text
u_exe_stage1/mem_result_reg_reg[1]/C
  -> u_issue_stage/queue3_reg[0]/CE
```

WNS was `-3.321 ns`, with 23 logic levels and an estimated 6.703 ns route component. The path crossed lane1 EX, lane0 redirect merge, IF RAS/fetch control, and issue queue acceptance.

## P1 Changes

### Queue physical movement

`issue_stage` now distinguishes:

- `lane*_fire`: architectural issue/retirement-visible events, still masked by redirect;
- `lane*_shift`: physical queue movement, not masked by redirect;
- `capacity_allow`: normal queue capacity decision;
- `packet_accept`: normal packet write, independent of the global flush override.

Flush still clears `queue_count` and packet tag, and masks issue outputs. Invalid payload movement during a flush is architecturally invisible, but redirect no longer directly controls the wide queue payload CE/D cone.

### RAS redirect boundary

`if_stage` now uses the already registered `br_taken_reg` and registered branch call/return metadata when restoring the speculative RAS state. The immediate `br_taken` signal remains a fetch-kill input, so redirect recovery behavior is not intentionally delayed; only the wide RAS stack update CE cone is separated from EX1 data.

## Simulation

- RTL compile: Errors 0, Warnings 0;
- `tb_issue_stage`: passed;
- `tb_mem_commit`: passed;
- `tb_multi_issue_l2`: passed;
- `tb_multi_issue_l3`: passed, 29 cycles / 34 instret;
- `tb_mul_special`: passed.

## Next Quick-Synth Checks

1. Confirm `ras_spec_stack_reg[*]/CE` and `ras_spec_count_reg[*]/CE` no longer start at `u_exe_stage1/mem_result_reg_reg[1]/C`.
2. Confirm `queue3_reg[*]/CE` is driven by local shift/capacity logic rather than redirect/IF fetch control.
3. Check whether the new worst path is still EX1 JALR data, or has migrated to DRAM WEA/other physical routing.
4. Run branch-call/return, RAS, exception and full benchmark validation before accepting the timing result.
