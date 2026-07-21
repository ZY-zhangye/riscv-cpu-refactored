#!/usr/bin/env bash
set -uo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: run_overclock_frequency.sh <frequency-mhz> <vivado-jobs>" >&2
    exit 2
fi

freq="$1"
jobs="$2"
root=/home/zy/work/overclock_sweep_20260719
project="$root/projects/jyd_writegate_${freq}MHz_20260719"
artifact_dir="$root/artifacts/${freq}MHz"
main_tcl="$root/scripts/cloud_full_build_to_bit.tcl"
recovery_tcl="$root/scripts/cloud_repair_postroute_and_bit.tcl"
main_log="$project/overclock_full_build.log"
main_jou="$project/overclock_full_build.jou"
recovery_log="$project/overclock_recovery.log"
recovery_jou="$project/overclock_recovery.jou"
status_file="$artifact_dir/build_status.txt"
main_rc=NA
recovery_rc=NA
mode=normal
start_time="$(date -Iseconds)"

mkdir -p "$artifact_dir"

write_status() {
    local status="$1"
    local reason="$2"
    local wns="${3:-NA}"
    local whs="${4:-NA}"
    {
        printf 'Status=%s\n' "$status"
        printf 'Reason=%s\n' "$reason"
        printf 'FrequencyMHz=%s\n' "$freq"
        printf 'Mode=%s\n' "$mode"
        printf 'WNS=%s\n' "$wns"
        printf 'WHS=%s\n' "$whs"
        printf 'MainVivadoExit=%s\n' "$main_rc"
        printf 'RecoveryVivadoExit=%s\n' "$recovery_rc"
        printf 'Project=%s\n' "$project"
        printf 'Started=%s\n' "$start_time"
        printf 'Finished=%s\n' "$(date -Iseconds)"
    } > "$status_file"
}

copy_outputs() {
    if [[ -d "$project/cloud_build_results" ]]; then cp -a "$project/cloud_build_results/." "$artifact_dir/"; fi
    if [[ -f "$main_log" ]]; then cp -f "$main_log" "$artifact_dir/"; fi
    if [[ -f "$main_jou" ]]; then cp -f "$main_jou" "$artifact_dir/"; fi
    if [[ -f "$recovery_log" ]]; then cp -f "$recovery_log" "$artifact_dir/"; fi
    if [[ -f "$recovery_jou" ]]; then cp -f "$recovery_jou" "$artifact_dir/"; fi
    return 0
}

hash_artifacts() {
    (
        cd "$artifact_dir" || exit 1
        find . -maxdepth 1 -type f ! -name SHA256SUMS.txt -printf '%f\n' \
            | sort | xargs -r sha256sum
    ) > "$artifact_dir/SHA256SUMS.txt"
}

if [[ ! -f "$project/JYD2026_Contest_Bitstream.xpr" ]]; then
    write_status FAILED PROJECT_MISSING
    exit 3
fi

printf 'BUILD_FREQ=%s STATE=RUNNING START=%s\n' "$freq" "$start_time" > "$artifact_dir/build_progress.txt"
main_complete=0
set +e
vivado -mode batch -log "$main_log" -journal "$main_jou" \
    -source "$main_tcl" -tclargs "$project" "$freq" "$jobs"
main_rc=$?
set -e
if [[ $main_rc -eq 0 ]] && grep -q '^CLOUD_BUILD_COMPLETE=1$' "$main_log"; then
    if grep -q '^CLOUD_BUILD_CLOCK_VALID=1$' "$main_log"; then
        main_complete=1
    fi
fi

if grep -q '^CLOUD_BUILD_CLOCK_PERIOD_MISMATCH=1$' "$main_log"; then
    copy_outputs
    write_status FAILED CLOCK_PERIOD_MISMATCH
    hash_artifacts
    exit 23
fi

if [[ $main_complete -ne 1 ]]; then
    fresh_dcp="$project/JYD2026_Contest_Bitstream.runs/impl_1/top_postroute_physopt.dcp"
    if [[ ! -f "$fresh_dcp" ]]; then
        copy_outputs
        write_status FAILED FULL_BUILD_FAILED_BEFORE_POSTROUTE_DCP
        hash_artifacts
        exit 20
    fi

    mode=quick-route-recovery
    printf 'BUILD_FREQ=%s STATE=RECOVERY START=%s\n' "$freq" "$(date -Iseconds)" > "$artifact_dir/build_progress.txt"
    set +e
    vivado -mode batch -log "$recovery_log" -journal "$recovery_jou" \
        -source "$recovery_tcl" -tclargs "$project" "$freq"
    recovery_rc=$?
    set -e
    if [[ $recovery_rc -ne 0 ]] || ! grep -q '^CLOUD_RECOVERY_COMPLETE=1$' "$recovery_log"; then
        copy_outputs
        write_status FAILED QUICK_ROUTE_RECOVERY_FAILED
        hash_artifacts
        exit 21
    fi
fi

copy_outputs
bit_file="$artifact_dir/cpu_base_${freq}MHz_cloud.bit"
dcp_file="$artifact_dir/postroute_cloud.dcp"
if [[ ! -f "$bit_file" ]] || [[ ! -f "$dcp_file" ]]; then
    write_status FAILED EXPECTED_ARTIFACT_MISSING
    hash_artifacts
    exit 22
fi

if [[ "$mode" == normal ]]; then
    wns="$(grep '^CLOUD_BUILD_WNS=' "$main_log" | tail -n 1 | cut -d= -f2-)"
    whs="$(grep '^CLOUD_BUILD_WHS=' "$main_log" | tail -n 1 | cut -d= -f2-)"
else
    wns="$(grep '^CLOUD_RECOVERY_WNS=' "$recovery_log" | tail -n 1 | cut -d= -f2-)"
    whs="$(grep '^CLOUD_RECOVERY_WHS=' "$recovery_log" | tail -n 1 | cut -d= -f2-)"
fi
wns="${wns:-NA}"
whs="${whs:-NA}"

tar --zstd -cf "$artifact_dir/jyd_writegate_${freq}MHz_full_project.tar.zst" \
    -C "$root/projects" "jyd_writegate_${freq}MHz_20260719"
write_status SUCCESS COMPLETE "$wns" "$whs"
hash_artifacts
printf 'BUILD_FREQ=%s STATE=SUCCESS WNS=%s WHS=%s\n' "$freq" "$wns" "$whs" > "$artifact_dir/build_progress.txt"
