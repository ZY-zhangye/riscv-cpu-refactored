#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERILATOR_EXE="${VERILATOR_EXE:-/home/zy/tools/verilator/bin/verilator}"
IROM_COE="${IROM_COE:-}"
DRAM_COE="${DRAM_COE:-}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/verilator_soc}"

if [[ -z "${IROM_COE}" && $# -gt 0 && "${1}" != +* ]]; then
    IROM_COE="$1"
    shift
fi
if [[ -z "${DRAM_COE}" && $# -gt 0 && "${1}" != +* ]]; then
    DRAM_COE="$1"
    shift
fi

if [[ -z "${IROM_COE}" || ! -f "${IROM_COE}" ]]; then
    echo "usage: IROM_COE=/path/irom-v2.coe DRAM_COE=/path/dram.coe $0 [irom.coe] [dram.coe] [plusargs...]" >&2
    exit 2
fi

mkdir -p "${BUILD_DIR}"
IROM_HEX="${BUILD_DIR}/irom-v2.mem"
DRAM_HEX="${BUILD_DIR}/dram.mem"

convert_coe() {
    local source_file="$1"
    local output_file="$2"
    awk '
        BEGIN { in_vector = 0 }
        tolower($0) ~ /memory_initialization_vector/ { in_vector = 1; next }
        in_vector {
            line = $0
            gsub(/[;,\r]/, " ", line)
            count = split(line, fields, /[[:space:]]+/)
            for (i = 1; i <= count; i++) {
                if (fields[i] ~ /^[0-9a-fA-F]+$/) {
                    print toupper(fields[i])
                }
            }
        }
    ' "${source_file}" > "${output_file}"
}

convert_coe "${IROM_COE}" "${IROM_HEX}"
IROM_WORDS="$(wc -l < "${IROM_HEX}")"
if (( IROM_WORDS == 0 || IROM_WORDS > 4096 )); then
    echo "invalid IROM word count: ${IROM_WORDS}" >&2
    exit 3
fi

DRAM_ARGS=()
if [[ -n "${DRAM_COE}" ]]; then
    if [[ ! -f "${DRAM_COE}" ]]; then
        echo "DRAM COE not found: ${DRAM_COE}" >&2
        exit 4
    fi
    convert_coe "${DRAM_COE}" "${DRAM_HEX}"
    DRAM_ARGS+=("+DRAM_HEX=${DRAM_HEX}")
fi

cd "${ROOT_DIR}"
"${VERILATOR_EXE}" \
    -sv \
    --timing \
    --binary \
    --top-module tb_soc_irom_v2 \
    --Mdir "${BUILD_DIR}/obj_dir" \
    -Irtl/cpu_top \
    -Wno-fatal \
    -Wno-TIMESCALEMOD \
    -Wno-WIDTHEXPAND \
    -Wno-WIDTHTRUNC \
    -Wno-CASEINCOMPLETE \
    -Wno-LATCH \
    -Wno-MULTIDRIVEN \
    -f sim/verilator_soc/soc_irom_v2.f \
    sim/verilator_soc/wait_for_enter.cpp

echo "[SOC] IROM words: ${IROM_WORDS}"
exec "${BUILD_DIR}/obj_dir/Vtb_soc_irom_v2" \
    "+IROM_HEX=${IROM_HEX}" \
    "${DRAM_ARGS[@]}" \
    "$@"
