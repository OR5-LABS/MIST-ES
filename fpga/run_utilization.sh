#!/usr/bin/env bash
# =============================================================================
# run_utilization.sh — Master FPGA Resource Utilization & Timing Benchmark Runner
#
# Runs Vivado 2023.2 synthesis for MIST-ES Core and SoC in both Default
# (Machine Mode) and SECURE (M+U, PMP/ePMP, ECC) configurations.
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v vivado &>/dev/null; then
    echo "[INFO] Using vivado from PATH: $(command -v vivado)"
elif [ -n "${VIVADO_SETTINGS:-}" ] && [ -f "$VIVADO_SETTINGS" ]; then
    echo "[INFO] Sourcing Vivado from VIVADO_SETTINGS: $VIVADO_SETTINGS"
    source "$VIVADO_SETTINGS"
elif [ -f "/vivado/Vivado/2023.2/settings64.sh" ]; then
    echo "[INFO] Sourcing Vivado 2023.2 environment..."
    source "/vivado/Vivado/2023.2/settings64.sh"
elif [ -f "/tools/Xilinx/Vivado/2023.2/settings64.sh" ]; then
    echo "[INFO] Sourcing Vivado 2023.2 environment..."
    source "/tools/Xilinx/Vivado/2023.2/settings64.sh"
elif [ -f "/opt/Xilinx/Vivado/2023.2/settings64.sh" ]; then
    echo "[INFO] Sourcing Vivado 2023.2 environment..."
    source "/opt/Xilinx/Vivado/2023.2/settings64.sh"
else
    echo "[WARNING] Vivado settings file not found at ${VIVADO_SETTINGS:-standard locations}, relying on system PATH."
fi

TCL_SCRIPT="$SCRIPT_DIR/arty_a7/synth_utilization.tcl"
BUILD_BASE="$SCRIPT_DIR/arty_a7/build_util"

mkdir -p "$BUILD_BASE"

echo "=========================================================================="
echo "  MIST-ES RISC-V CORE & SOC RESOURCE UTILIZATION SUITE (Xilinx Artix-7)"
echo "=========================================================================="

run_synth() {
    local target=$1
    local secure=$2
    local out_dir="$BUILD_BASE/${target}_secure_${secure}"
    echo ""
    echo "[RUNNING] Target: $target | SECURE: $secure -> Output: $out_dir"
    mkdir -p "$out_dir"
    vivado -mode batch -source "$TCL_SCRIPT" -tclargs "$target" "$secure" "$out_dir" > "$out_dir/vivado.log" 2>&1
    echo "[COMPLETED] Target: $target | SECURE: $secure"
}

# Run Synthesis for all 4 configurations
run_synth "core" 0
run_synth "core" 1
run_synth "soc"  0
run_synth "soc"  1

echo ""
echo "=========================================================================="
echo "  POST-SYNTHESIS / IMPLEMENTATION UTILIZATION & TIMING SUMMARY REPORT"
echo "=========================================================================="

parse_rpt() {
    local out_dir=$1
    python3 - "$out_dir" << 'EOF'
import sys, os, re

out_dir = sys.argv[1]
rpt_path = os.path.join(out_dir, "utilization.rpt")
tmg_path = os.path.join(out_dir, "timing.rpt")
pwr_path = os.path.join(out_dir, "power.rpt")

luts, ffs, dsps, brams = "—", "—", "—", "—"
wns, fmax, power = "—", "—", "—"

if os.path.exists(rpt_path):
    with open(rpt_path) as f:
        content = f.read()
        m_lut = re.search(r"\|\s+Slice LUTs\*?\s+\|\s+(\d+)\s+\|", content)
        if m_lut: luts = m_lut.group(1)
        
        m_ff = re.search(r"\|\s+Slice Registers\s+\|\s+(\d+)\s+\|", content)
        if m_ff: ffs = m_ff.group(1)
        
        m_dsp = re.search(r"\|\s+DSPs\s+\|\s+(\d+)\s+\|", content)
        if m_dsp: dsps = m_dsp.group(1)
        
        m_bram = re.search(r"\|\s+Block RAM Tile\s+\|\s+(\d+)\s+\|", content)
        if m_bram: brams = m_bram.group(1)

if os.path.exists(tmg_path):
    with open(tmg_path) as f:
        content = f.read()
        m_wns = re.search(r"^\s*(-?\d+\.\d+)\s+-?\d+\.\d+\s+\d+", content, re.MULTILINE)
        if m_wns:
            val = float(m_wns.group(1))
            wns = f"{val:+.3f} ns"
            period = 20.0  # 50 MHz clock constraint
            fmax_val = 1000.0 / (period - val)
            fmax = f"{fmax_val:.2f} MHz"

if os.path.exists(pwr_path):
    with open(pwr_path) as f:
        content = f.read()
        m_pwr = re.search(r"\|\s+Total On-Chip Power \(W\)\s+\|\s+([\d\.]+)\s+\|", content)
        if m_pwr:
            power = f"{m_pwr.group(1)} W"

print(f"{luts:10} | {ffs:10} | {dsps:6} | {brams:6} | {wns:10} | {fmax:12} | {power:10}")
EOF
}

echo ""
printf "| %-25s | %-10s | %-10s | %-6s | %-6s | %-10s | %-12s | %-10s |\n" \
    "Configuration" "LUTs" "FFs" "DSPs" "BRAMs" "WNS (ns)" "Fmax (MHz)" "Power"
echo "|---------------------------|------------|------------|--------|--------|------------|--------------|------------|"

c_def=$(parse_rpt "$BUILD_BASE/core_secure_0")
c_sec=$(parse_rpt "$BUILD_BASE/core_secure_1")
s_def=$(parse_rpt "$BUILD_BASE/soc_secure_0")
s_sec=$(parse_rpt "$BUILD_BASE/soc_secure_1")

printf "| %-25s | %s |\n" "Core (Default)" "$c_def"
printf "| %-25s | %s |\n" "Core (SECURE)" "$c_sec"
printf "| %-25s | %s |\n" "SoC Full (Default)" "$s_def"
printf "| %-25s | %s |\n" "SoC Full (SECURE)" "$s_sec"

echo "=========================================================================="

