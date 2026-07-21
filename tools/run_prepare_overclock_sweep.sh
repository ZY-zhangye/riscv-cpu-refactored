#!/usr/bin/env bash
set -uo pipefail

root=/home/zy/work/overclock_sweep_20260719
prepare_tcl="$root/scripts/prepare_overclock_frequency.tcl"
status_file="$root/prepare_status.txt"

: > "$status_file"
for freq in 210 220 230 240 250; do
    project="$root/projects/jyd_writegate_${freq}MHz_20260719"
    log="$project/prepare_frequency.log"
    printf 'FREQ=%s STATE=RUNNING\n' "$freq" >> "$status_file"

    vivado -mode batch -log "$log" -journal "$project/prepare_frequency.jou" \
        -source "$prepare_tcl" -tclargs "$project" "$freq"
    rc=$?

    if [[ $rc -eq 0 ]] && grep -q '^OVERCLOCK_PLL_GENERATION_COMPLETE=1$' "$log"; then
        actual="$(grep '^OVERCLOCK_PLL_REQUESTED_FREQ=' "$log" | tail -n 1 | cut -d= -f2-)"
        printf 'FREQ=%s STATE=SUCCESS PLL_MHZ=%s\n' "$freq" "$actual" >> "$status_file"
    else
        printf 'FREQ=%s STATE=FAILED RC=%s\n' "$freq" "$rc" >> "$status_file"
        exit 20
    fi
done

printf 'PREPARE_SWEEP_COMPLETE=1\n' >> "$status_file"
