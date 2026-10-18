#!/bin/bash
set -e

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
MIST_ES_DIR="$(dirname "$SCRIPT_DIR")"

# Detect RISC-V GCC
TC="${RISCV_TC:-}"
if [[ -n "$TC" && -x "$TC/riscv-none-elf-gcc" ]]; then
    RISCV_GCC="$TC/riscv-none-elf-gcc"
elif command -v riscv-none-elf-gcc &>/dev/null; then
    RISCV_GCC="riscv-none-elf-gcc"
elif command -v riscv64-unknown-elf-gcc &>/dev/null; then
    RISCV_GCC="riscv64-unknown-elf-gcc"
elif command -v riscv32-unknown-elf-gcc &>/dev/null; then
    RISCV_GCC="riscv32-unknown-elf-gcc"
elif command -v riscv64-elf-gcc &>/dev/null; then
    RISCV_GCC="riscv64-elf-gcc"
else
    echo "ERROR: No RISC-V GCC found. Set RISCV_TC or ensure riscv-none-elf-gcc / riscv64-unknown-elf-gcc is in your PATH."
    exit 1
fi
echo "[BUILD] Toolchain: $RISCV_GCC"

# Move to bench directory
cd "$MIST_ES_DIR/bench"

echo "========================================="
echo " Building and Running CoreMark Simulation"
echo " (1,000 iterations: ~785M cycles, approx. 10-15 mins)"
echo "========================================="

# Clean previous builds
rm -f build/coremark.hex build/coremark.elf

# Build CoreMark (reduced iterations for fast sim)
make coremark ITERATIONS=1000 RISCV_GCC="$RISCV_GCC"

# Run simulation
make run-mist-es-coremark TIMEOUT_CYCLES=5000000000

echo ""
echo "========================================="
echo " CoreMark Results"
echo "========================================="
python3 -c '
import re

log_path = "results/mist_es/coremark.log"
try:
    text = open(log_path).read()
    
    # Extract total ticks from CoreMark output
    ticks_match = re.search(r"Total ticks\s*:\s*(\d+)", text)
    iter_match = re.search(r"Iterations\s*:\s*(\d+)", text)
    
    if ticks_match and iter_match:
        ticks = int(ticks_match.group(1))
        iterations = int(iter_match.group(1))
        
        cpi = ticks / iterations
        cm_per_mhz = 1_000_000 / cpi
        
        print(f"  ╔══════════════════════════════════════╗")
        print(f"  ║  CoreMark Metrics                    ║")
        print(f"  ╠══════════════════════════════════════╣")
        print(f"  ║  Iterations    : {iterations:<20}║")
        print(f"  ║  Total Ticks   : {ticks:<20,}║")
        print(f"  ║  Cycles/Iter   : {cpi:<20,.1f}║")
        print(f"  ║  CoreMark/MHz  : {cm_per_mhz:<20.4f}║")
        print(f"  ╚══════════════════════════════════════╝")
    else:
        print("Could not find ticks/iterations in the log.")
except Exception as e:
    print(f"Error parsing log: {e}")
'

# Fail unless the simulation passed and CoreMark's CRC self-checks found no error.
LOG=results/mist_es/coremark.log
if grep -aq 'ERROR! \(list\|matrix\|state\) crc' "$LOG" ||
   ! grep -aqE '^\[BENCH\] coremark .* PASS$' "$LOG"; then
  echo "CoreMark: FAIL (see bench/$LOG)"; exit 1
fi
echo "CoreMark: PASS"
