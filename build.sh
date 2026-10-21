#!/usr/bin/env bash
# ============================================================================
# build.sh — build & run MIST-ES under Icarus Verilog.
#
#   ./build.sh [sim|cosim|rvfi|debug|pmp|epmp|upriv|mml|ecc|axil|fpga|bench|clean]
#
#   sim    (default) compile the core + SoC and run the self-checking smoke test
#   cosim  run smoke, then co-simulate against the golden RV32IM ISA model
#   rvfi   build the RVFI (riscv-formal interface) self-check
#   debug  build the JTAG / Debug-Module self-check
#   pmp    build the SECURE config (U-mode + PMP) and run the PMP test program
#   epmp   as pmp, exercising the ePMP (mseccfg) rules
#   upriv  SECURE: U-mode access to M-level CSRs and MRET must trap
#   mml    SECURE: Smepmp mseccfg.MML (machine mode lockdown) rules
#   ecc    build the register-file SECDED ECC unit test
#   axil   build the AXI4-Lite master/slave interconnect self-check
#   fpga   build the FPGA SoC sim (UART banner + LED blink) from firmware.mem
#   clean  remove build artifacts
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

IVL="${IVERILOG:-iverilog}"
VVP="${VVP:-vvp}"
ACTION="${1:-sim}"

R=rtl            # mist_es core + SoC
C=rtl/common     # shared datapath leaf cells

# Every simulation build needs the same leaf-cell set.
CELLS="$C/mist_es_pkg.sv $C/mist_es_alu.sv $C/mist_es_regfile.sv \
       $C/mist_es_muldiv.sv $C/mist_es_csr.sv $C/mist_es_rvc.sv \
       $C/mist_es_immgen.sv $C/mist_es_branch.sv $C/mist_es_decode.sv $C/mist_es_pmp.sv"
CORE="$R/mist_es_core.sv $R/mist_es_debug.sv $R/mist_es_soc.sv"

if [[ "$ACTION" == "clean" ]]; then
  rm -rf sim programs/build/*.hex *.vcd
  echo "Cleaned."
  exit 0
fi
mkdir -p sim programs/build

# Most testbenches end with $finish whatever the outcome, so vvp exits 0 even
# on failure. check_verdict fails the script unless the log holds the expected
# PASS verdict and no FAIL / TIMEOUT / MISMATCH / FATAL / ERROR line.
check_verdict() {  # $1 = test name, $2 = log file, $3 = PASS regex
  if grep -aEq '\bFAIL|TIMEOUT|MISMATCH|FATAL|^ERROR' "$2"; then
    echo "$1: FAILED (failure reported in $2)"; exit 1
  fi
  if ! grep -aEq "$3" "$2"; then
    echo "$1: FAILED (no PASS verdict in $2)"; exit 1
  fi
}

# ---- register-file ECC (SECDED) unit test ---------------------------------
if [[ "$ACTION" == "ecc" ]]; then
  echo "Building register-file SECDED ECC unit test..."
  "$IVL" -g2012 -I "$C" -o sim/tb_regfile_ecc \
    "$C/mist_es_pkg.sv" "$C/mist_es_regfile_ecc.sv" tb/tb_regfile_ecc.sv
  "$VVP" sim/tb_regfile_ecc | tee sim/ecc.log
  check_verdict ecc sim/ecc.log '^ECC: PASS'
  exit 0
fi

# ---- SECURE config: U-mode + PMP / ePMP -----------------------------------
if [[ "$ACTION" == "pmp" || "$ACTION" == "epmp" || "$ACTION" == "upriv" || "$ACTION" == "mml" ]]; then
  TC="${RISCV_TC:-/opt/riscv/bin}"
  GCC=""
  OBJCOPY=""
  if [[ -n "$TC" && -x "$TC/riscv-none-elf-gcc" ]]; then
    GCC="$TC/riscv-none-elf-gcc"
    OBJCOPY="$TC/riscv-none-elf-objcopy"
  elif command -v riscv-none-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv-none-elf-gcc)
    OBJCOPY=$(command -v riscv-none-elf-objcopy)
  elif command -v riscv64-unknown-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv64-unknown-elf-gcc)
    OBJCOPY=$(command -v riscv64-unknown-elf-objcopy)
  elif command -v riscv64-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv64-elf-gcc)
    OBJCOPY=$(command -v riscv64-elf-objcopy)
  elif command -v riscv32-unknown-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv32-unknown-elf-gcc)
    OBJCOPY=$(command -v riscv32-unknown-elf-objcopy)
  fi

  SRCASM=sw/pmp_test.S; HEXNAME=pmp
  if [[ "$ACTION" == "epmp" ]]; then
    SRCASM=sw/epmp_test.S; HEXNAME=epmp
  elif [[ "$ACTION" == "upriv" ]]; then
    SRCASM=sw/upriv_test.S; HEXNAME=upriv
  elif [[ "$ACTION" == "mml" ]]; then
    SRCASM=sw/mml_test.S; HEXNAME=mml
  fi

  if [[ -n "$GCC" && -x "$GCC" ]]; then
    echo "Assembling $SRCASM using $GCC ..."
    if ! "$GCC" -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding \
           -Wl,-Ttext=0 "$SRCASM" -o "programs/build/${HEXNAME}.elf" 2>/dev/null; then
      echo "rv32imc_zicsr failed; retrying assembly with -march=rv32imc ..."
      "$GCC" -march=rv32imc -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding \
             -Wl,-Ttext=0 "$SRCASM" -o "programs/build/${HEXNAME}.elf"
    fi
    "$OBJCOPY" -O binary -j .text "programs/build/${HEXNAME}.elf" "programs/build/${HEXNAME}.bin"
    python3 sw/bin2hex.py "programs/build/${HEXNAME}.bin" "programs/build/${HEXNAME}.hex"
  else
    echo "No RISC-V toolchain found; using prebuilt programs/build/${HEXNAME}.hex."
  fi
  echo "Building MIST-ES SECURE sim (U-mode + PMP + ePMP + regfile ECC)..."
  "$IVL" -g2012 -DMIST_ES_SECURE -I "$C" -I "$R" -o sim/tb_mist_es \
    $CELLS "$C/mist_es_regfile_ecc.sv" $CORE tb/tb_mist_es.sv
  echo "Running $ACTION test on MIST-ES..."
  "$VVP" sim/tb_mist_es +IMEM="programs/build/${HEXNAME}.hex" | tee "sim/${HEXNAME}.log"
  # The testbench ends with $finish either way; fail the script unless it passed.
  check_verdict "$ACTION" "sim/${HEXNAME}.log" '^\[TB\] PASS'
  exit 0
fi

# ---- default: compile + smoke ---------------------------------------------
python3 programs/build_smoke.py
echo "Compiling..."
"$IVL" -g2012 -I "$C" -I "$R" -o sim/tb_mist_es $CELLS $CORE tb/tb_mist_es.sv
echo "Running smoke..."
"$VVP" sim/tb_mist_es +IMEM=programs/build/smoke.hex | tee sim/smoke.log
check_verdict smoke sim/smoke.log '^\[TB\] PASS'

# ---- golden co-simulation --------------------------------------------------
if [[ "$ACTION" == "cosim" ]]; then
  echo "Co-simulating against the golden RV32IM ISA model..."
  VVP="$VVP" python tools/cosim.py \
      --hex programs/build/smoke.hex --sim sim/tb_mist_es
fi

# ---- RVFI (riscv-formal interface) self-check -----------------------------
if [[ "$ACTION" == "rvfi" ]]; then
  echo "Building RVFI self-check..."
  "$IVL" -g2012 -DRISCV_FORMAL -I "$C" -I "$R" -o sim/tb_mist_es_rvfi \
    $CELLS $CORE tb/tb_mist_es_rvfi.sv
  "$VVP" sim/tb_mist_es_rvfi +IMEM=programs/build/smoke.hex | tee sim/rvfi.log
  check_verdict rvfi sim/rvfi.log '^RVFI: PASS'
fi

# ---- JTAG / Debug-Module self-check ---------------------------------------
if [[ "$ACTION" == "debug" ]]; then
  echo "Building JTAG / Debug-Module self-check..."
  "$IVL" -g2012 -I "$C" -I "$R" -o sim/tb_mist_es_debug \
    $CELLS $CORE tb/tb_mist_es_debug.sv
  "$VVP" sim/tb_mist_es_debug +IMEM=programs/build/smoke.hex | tee sim/debug.log
  check_verdict debug sim/debug.log '^DEBUG: PASS'
fi

# ---- Verilator benchmark suite (CoreMark) -------------------
if [[ "$ACTION" == "bench" ]]; then
  echo "Running MIST-ES benchmark suite (CoreMark)..."
  echo "  Verilator model + CoreMark will be compiled and simulated."
  echo "  Results will appear in bench/results/report.md"
  echo ""
  if [[ -n "${RISCV_TC:-}" ]]; then
    export PATH="$RISCV_TC:$PATH"
  fi
  make -C "$(dirname "$0")/bench" all \
    ${ITERATIONS:+ITERATIONS="$ITERATIONS"} \
    ${SCALE:+SCALE="$SCALE"}
  exit 0
fi

# ---- AXI4-Lite bus integration self-check --------------------------------
if [[ "$ACTION" == "axil" ]]; then
  echo "Building AXI4-Lite bus integration self-check..."
  python3 programs/build_smoke.py
  "$IVL" -g2012 -I "$C" -I "$R" -o sim/tb_mist_es_axil \
    $CELLS "$R/mist_es_core.sv" "$R/mist_es_debug.sv" "$R/mist_es_axil.sv" tb/tb_mist_es_axil.sv
  "$VVP" sim/tb_mist_es_axil +IMEM=programs/build/smoke.hex | tee sim/axil.log
  check_verdict axil sim/axil.log '^\[TB\] PASS'
  exit 0
fi

# ---- FPGA SoC sim (UART banner + LED blink) -------------------------------
if [[ "$ACTION" == "fpga" ]]; then
  echo "Building FPGA SoC sim..."
  [[ -f sw/firmware.mem ]] || (cd sw && bash build_fpga_hello.sh)
  "$IVL" -g2012 -DSIMULATION -I "$C" -I "$R" -o sim/tb_mist_es_fpga \
    $CELLS "$R/mist_es_core.sv" "$R/mist_es_debug.sv" \
    fpga/common/mist_es_uart.sv fpga/mist_es_fpga.sv fpga/tb_mist_es_fpga.sv
  "$VVP" sim/tb_mist_es_fpga | tee sim/fpga.log
  check_verdict fpga sim/fpga.log '^FPGA: PASS'
fi
