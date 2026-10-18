#!/usr/bin/env bash
# build_fpga_hello.sh — assemble the FPGA bring-up demo into firmware.mem
# ($readmemh, one 32-bit word per line) for mist_es_fpga.
set -euo pipefail
cd "$(dirname "$0")"

TC="${RISCV_TC:-}"
GCC="${GCC:-}"
OBJCOPY="${OBJCOPY:-}"

if [[ -z "$GCC" ]]; then
  if [[ -n "$TC" && -x "$TC/riscv-none-elf-gcc" ]]; then
    GCC="$TC/riscv-none-elf-gcc"
    OBJCOPY="$TC/riscv-none-elf-objcopy"
  elif command -v riscv64-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv64-elf-gcc)
    OBJCOPY=$(command -v riscv64-elf-objcopy)
  elif command -v riscv-none-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv-none-elf-gcc)
    OBJCOPY=$(command -v riscv-none-elf-objcopy)
  elif command -v riscv64-unknown-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv64-unknown-elf-gcc)
    OBJCOPY=$(command -v riscv64-unknown-elf-objcopy)
  elif command -v riscv32-unknown-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv32-unknown-elf-gcc)
    OBJCOPY=$(command -v riscv32-unknown-elf-objcopy)
  fi
fi

if [[ -z "$GCC" || ! -x "$GCC" ]]; then
  echo "ERROR: No RISC-V GCC found to assemble fpga_hello."
  exit 1
fi

OUT="${1:-firmware.mem}"
if [[ "$OUT" == sw/* ]]; then
  OUT="${OUT#sw/}"
fi

"$GCC" -march=rv32imc -mabi=ilp32 -nostdlib -nostartfiles -fno-pic \
       -Wl,--no-relax -T fpga_hello.ld fpga_hello.S -o fpga_hello.elf
"$OBJCOPY" -O binary fpga_hello.elf fpga_hello.bin
python3 bin2hex.py fpga_hello.bin "$OUT"
echo "wrote $OUT"
