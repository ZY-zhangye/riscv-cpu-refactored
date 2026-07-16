#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERILATOR_EXE="${VERILATOR_EXE:-/home/zy/tools/verilator/bin/verilator}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/verilator_coremark}"
INST_HEX="${INST_HEX:-${ROOT_DIR}/board_tests/05_coremark/output/inst.hex}"
DATA_HEX="${DATA_HEX:-${ROOT_DIR}/board_tests/05_coremark/output/data.hex}"

if [[ ! -f "${INST_HEX}" || ! -f "${DATA_HEX}" ]]; then
    echo "missing CoreMark memory image" >&2
    echo "INST_HEX=${INST_HEX}" >&2
    echo "DATA_HEX=${DATA_HEX}" >&2
    exit 2
fi

mkdir -p "${BUILD_DIR}"
cd "${ROOT_DIR}"

"${VERILATOR_EXE}" \
    -sv \
    --cc \
    --exe \
    --build \
    --top-module my_cpu \
    --Mdir "${BUILD_DIR}/obj_dir" \
    --build-jobs 16 \
    -MAKEFLAGS "OPT_FAST=-O3 OPT_SLOW=-O3 OPT_GLOBAL=-O3" \
    -O3 \
    --x-assign fast \
    --x-initial fast \
    -Irtl/cpu_top \
    -Irtl/my_cpu \
    -Wno-fatal \
    -Wno-DEFOVERRIDE \
    -Wno-TIMESCALEMOD \
    -Wno-WIDTHEXPAND \
    -Wno-WIDTHTRUNC \
    -Wno-CASEINCOMPLETE \
    -Wno-LATCH \
    -Wno-MULTIDRIVEN \
    -CFLAGS "-O3 -march=native -mtune=native -flto -DNDEBUG" \
    -LDFLAGS "-O3 -march=native -mtune=native -flto" \
    rtl/cpu_top/*.sv \
    rtl/my_cpu/*.sv \
    sim/verilator_coremark/coremark_main.cpp

exec "${BUILD_DIR}/obj_dir/Vmy_cpu" \
    "+INST_HEX=${INST_HEX}" \
    "+DATA_HEX=${DATA_HEX}" \
    "$@"
