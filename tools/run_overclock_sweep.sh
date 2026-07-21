#!/usr/bin/env bash
set -uo pipefail

root=/home/zy/work/overclock_sweep_20260719
status_file="$root/sweep_status.txt"
worker="$root/scripts/run_overclock_frequency.sh"
prepare_status="$root/prepare_status.txt"

wait_for_prepare() {
    for _ in $(seq 1 120); do
        if [[ -f "$prepare_status" ]] && grep -q '^PREPARE_SWEEP_COMPLETE=1$' "$prepare_status"; then
            return 0
        fi
        if [[ -f "$prepare_status" ]] && grep -q 'STATE=FAILED' "$prepare_status"; then
            return 1
        fi
        sleep 10
    done
    return 2
}

run_pair() {
    local first="$1"
    local second="$2"
    printf 'STAGE=BUILDING_%s_%s START=%s\n' "$first" "$second" "$(date -Iseconds)" >> "$status_file"
    bash "$worker" "$first" 8 > "$root/${first}MHz_driver.log" 2>&1 &
    first_pid=$!
    bash "$worker" "$second" 8 > "$root/${second}MHz_driver.log" 2>&1 &
    second_pid=$!
    wait "$first_pid"
    first_rc=$?
    wait "$second_pid"
    second_rc=$?
    if [[ $first_rc -ne 0 ]] || [[ $second_rc -ne 0 ]]; then
        printf 'STAGE=FAILED_%s_%s RC=%s,%s\n' "$first" "$second" "$first_rc" "$second_rc" >> "$status_file"
        return 1
    fi
    printf 'STAGE=COMPLETE_%s_%s FINISH=%s\n' "$first" "$second" "$(date -Iseconds)" >> "$status_file"
}

mkdir -p "$root/artifacts"
: > "$status_file"
printf 'STAGE=WAITING_FOR_PLL_PREPARE START=%s\n' "$(date -Iseconds)" >> "$status_file"
if ! wait_for_prepare; then
    printf 'STAGE=FAILED_PLL_PREPARE FINISH=%s\n' "$(date -Iseconds)" >> "$status_file"
    exit 30
fi

sweep_failed=0
if ! run_pair 210 220; then
    sweep_failed=1
fi
if ! run_pair 230 240; then
    sweep_failed=1
fi
printf 'STAGE=BUILDING_250 START=%s\n' "$(date -Iseconds)" >> "$status_file"
bash "$worker" 250 12 > "$root/250MHz_driver.log" 2>&1
last_rc=$?
if [[ $last_rc -ne 0 ]]; then
    printf 'STAGE=FAILED_250 RC=%s\n' "$last_rc" >> "$status_file"
    sweep_failed=1
else
    printf 'STAGE=COMPLETE_250 FINISH=%s\n' "$(date -Iseconds)" >> "$status_file"
fi
if [[ $sweep_failed -ne 0 ]]; then
    printf 'OVERCLOCK_SWEEP_COMPLETE_WITH_FAILURES=1\n' >> "$status_file"
    exit 40
fi
printf 'OVERCLOCK_SWEEP_COMPLETE=1\n' >> "$status_file"
