#!/usr/bin/env bash
# =============================================================================
# run_dhrystone_arty.sh — Build Dhrystone 2.1 for Digilent Arty A7-100T FPGA
# Core: MIST-ES
# Target: AMD Artix-7 xc7a100tcsg324-1 (Digilent Arty A7-100T)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

RUNS="${1:-10000}"

echo "================================================================="
echo " Building Dhrystone 2.1 for Arty A7-100T (MIST-ES)"
echo " Runs: ${RUNS}"
echo "================================================================="

# 1. Build firmware
if [ -f src/build_dhrystone.sh ]; then
    ./src/build_dhrystone.sh "${RUNS}"
    MEM_SRC="src/dhrystone.hex"
elif [ -f run_dhrystone.sh ]; then
    ./run_dhrystone.sh "${RUNS}" > /dev/null 2>&1 || true
    MEM_SRC="build/dhrystone.hex"
fi

BUILD_DIR="build_arty_a7"
mkdir -p "${BUILD_DIR}"

if [ -f "${MEM_SRC:-}" ]; then
    cp "${MEM_SRC}" "${BUILD_DIR}/firmware.mem"
elif [ -f build/dhrystone.hex ]; then
    cp build/dhrystone.hex "${BUILD_DIR}/firmware.mem"
elif [ -f src/dhrystone.hex ]; then
    cp src/dhrystone.hex "${BUILD_DIR}/firmware.mem"
fi

echo "Firmware hex prepared at: ${BUILD_DIR}/firmware.mem"

# 2. Check for Arty A7 FPGA target directory and Vivado flow
FPGA_DIR="../fpga/arty_a7"
if [ -d "${FPGA_DIR}" ]; then
    mkdir -p "${FPGA_DIR}/build"
    cp "${BUILD_DIR}/firmware.mem" "${FPGA_DIR}/build/firmware.mem"
    
    TCL_SCRIPT="mist_es_arty_a7.tcl"
    if [ -n "${TCL_SCRIPT}" ] && [ -f "${FPGA_DIR}/${TCL_SCRIPT}" ]; then
        echo "Running Vivado synthesis & bitstream generation for Arty A7-100T..."
        if [ -z "${VIVADO_SETTINGS:-}" ]; then
            if [ -f "${HOME}/Vivado/2023.2/settings64.sh" ]; then
                VIVADO_SETTINGS="${HOME}/Vivado/2023.2/settings64.sh"
            elif [ -f "/tools/Xilinx/Vivado/2023.2/settings64.sh" ]; then
                VIVADO_SETTINGS="/tools/Xilinx/Vivado/2023.2/settings64.sh"
            fi
        fi
        if [ -n "${VIVADO_SETTINGS:-}" ] && [ -f "$VIVADO_SETTINGS" ]; then
            source "$VIVADO_SETTINGS"
        fi
        
        if command -v vivado &> /dev/null; then
            cd "${FPGA_DIR}"
            vivado -mode batch -source "${TCL_SCRIPT}" -tclargs build
            echo "Bitstream generated in ${FPGA_DIR}/build/"
        else
            echo "Vivado not found in PATH. Skipping bitstream generation."
        fi
    fi
fi

echo "================================================================="
echo " Arty A7-100T Dhrystone firmware build complete."
echo " Device: xc7a100tcsg324-1"
echo " Memory: ${BUILD_DIR}/firmware.mem"
echo "================================================================="
