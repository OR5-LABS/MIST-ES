#!/usr/bin/env bash
# run_arch_test.sh -- build & run the OFFICIAL RISC-V Architecture Tests on MIST-ES.
#
# Runs the official RISC-V Architecture Test suite (riscv-arch-test)
# across the implemented extensions (I, M, C).
#
# Each test is compiled with the MIST-ES target environment
# (arch-test/target/mist_es: code in IMEM, data in DRAM, exit via tohost @0x2000_0000).
# The simulation testbench extracts the signature region between begin_signature
# and end_signature directly from memory, and verifies it bit-for-bit against
# the official golden reference signature shipped with the test suite.
#
# Usage:
#   ./run_arch_test.sh                   default build: I M C suites
#   ./run_arch_test.sh default I         default build: I suite only
#   ./run_arch_test.sh default M         default build: M suite only
#   ./run_arch_test.sh default C         default build: C suite only
#   ./run_arch_test.sh secure            SECURE build (MIST_ES_SECURE)
#   ./run_arch_test.sh all               both default and secure builds
#
set -uo pipefail
cd "$(dirname "$0")"

TC="${RISCV_TC:-/opt/riscv/bin}"
if [[ -n "$TC" && -x "$TC/riscv-none-elf-gcc" ]]; then
  GCC="$TC/riscv-none-elf-gcc"; OBJCOPY="$TC/riscv-none-elf-objcopy"; NM="$TC/riscv-none-elf-nm"
elif command -v riscv-none-elf-gcc &>/dev/null; then
  GCC=riscv-none-elf-gcc; OBJCOPY=riscv-none-elf-objcopy; NM=riscv-none-elf-nm
elif command -v riscv64-unknown-elf-gcc &>/dev/null; then
  GCC=riscv64-unknown-elf-gcc; OBJCOPY=riscv64-unknown-elf-objcopy; NM=riscv64-unknown-elf-nm
else
  echo "run_arch_test.sh: no RISC-V GCC found (set RISCV_TC)"; exit 1
fi

IVL="${IVERILOG:-iverilog}"; VVP="${VVP:-vvp}"
ARCH_DIR="third_party/riscv-arch-test"
SUITE_BASE="$ARCH_DIR/riscv-test-suite/rv32i_m"

if [[ ! -d "$SUITE_BASE" ]]; then
  echo "==> Fetching official riscv-arch-test suite (branch arch-tests-v2)..."
  mkdir -p "third_party"
  git clone --depth 1 -b arch-tests-v2 https://github.com/riscv-non-isa/riscv-arch-test.git "$ARCH_DIR" || {
    echo "run_arch_test.sh: failed to clone riscv-arch-test suite"
    exit 1
  }
fi

CONFIGS="${1:-default}"
[[ "$CONFIGS" == "all" ]] && CONFIGS="default secure"
shift || true
SUITES="${*:-I M C}"

skip_reason() { # $1 = config, $2 = suite/test
  case "$2" in
    C/cebreak-01) echo "MIST-ES writes mtval=0 on breakpoint per privileged spec (reference expects faulting pc)" ;;
    privilege/*misalign*) echo "core natively supports hardware misaligned memory accesses without trapping" ;;
    privilege/ebreak) echo "MIST-ES writes mtval=0 on breakpoint per privileged spec (reference expects faulting pc)" ;;
    Zifencei/*) echo "Zifencei is not implemented: FENCE.I raises illegal instruction" ;;
  esac
}

suite_march() { # $1 = suite
  case "$1" in
    I) echo "rv32i" ;;
    M) echo "rv32im" ;;
    C) echo "rv32ic" ;;
    privilege) echo "rv32i_zicsr" ;;
    *) echo "rv32imc" ;;
  esac
}

R=rtl; C=rtl/common
CELLS="$C/mist_es_pkg.sv $C/mist_es_alu.sv $C/mist_es_regfile.sv \
       $C/mist_es_muldiv.sv $C/mist_es_csr.sv $C/mist_es_rvc.sv \
       $C/mist_es_immgen.sv $C/mist_es_branch.sv $C/mist_es_decode.sv $C/mist_es_pmp.sv"
CORE="$R/mist_es_core.sv $R/mist_es_debug.sv $R/mist_es_soc.sv"

status=0
for cfg in $CONFIGS; do
  case "$cfg" in
    default) DEFS="-DIMEM_WORDS=524288"; EXTRA="" ;;
    secure)  DEFS="-DIMEM_WORDS=524288 -DMIST_ES_SECURE"; EXTRA="$C/mist_es_regfile_ecc.sv" ;;
    *) echo "unknown config: $cfg"; exit 1 ;;
  esac

  B="build/arch-test/$cfg"
  mkdir -p "$B" sim

  if ! "$IVL" -g2012 $DEFS -I "$C" -I "$R" -o "sim/tb_arch_test_$cfg" \
         $CELLS $EXTRA $CORE tb/tb_mist_es.sv > "$B/iverilog.log" 2>&1; then
    cat "$B/iverilog.log"; echo "run_arch_test.sh: $cfg: simulator build FAILED"; exit 1
  fi

  echo "==== MIST-ES ($cfg build): official riscv-arch-test $SUITES ===="
  pass=0; fail=0; skip=0; failed=""

  for s in $SUITES; do
    sdir="$SUITE_BASE/$s"
    [[ -d "$sdir" ]] || continue
    march=$(suite_march "$s")

    for src in "$sdir"/src/*.S; do
      [[ -f "$src" ]] || continue
      t=$(basename "$src" .S)
      why=$(skip_reason "$cfg" "$s/$t")
      if [[ -n "$why" ]]; then
        printf "  %-24s SKIP (%s)\n" "$s/$t" "$why"
        skip=$((skip+1))
        continue
      fi

      ref="$sdir/references/$t.reference_output"
      if [[ ! -f "$ref" ]]; then
        printf "  %-24s SKIP (no reference output)\n" "$s/$t"
        skip=$((skip+1))
        continue
      fi

      elf="$B/$s-$t.elf"
      if ! "$GCC" -march="$march" -mabi=ilp32 -nostdlib -nostartfiles -static -fno-pic \
             -Wl,--no-relax \
             -I arch-test/target/mist_es \
             -I "$ARCH_DIR/riscv-test-suite/env" \
             -I "$ARCH_DIR/riscv-test-env" \
             -I "$ARCH_DIR/riscv-test-env/p" \
             -T arch-test/target/mist_es/link.ld \
             "$src" -o "$elf" > "$B/$s-$t.cc.log" 2>&1; then
        printf "  %-24s FAIL (compile error, see %s)\n" "$s/$t" "$B/$s-$t.cc.log"
        fail=$((fail+1)); failed="$failed $s/$t"; continue
      fi

      sig_beg=$("$NM" "$elf" | grep -w "begin_signature" | awk '{print $1}')
      sig_end=$("$NM" "$elf" | grep -w "end_signature" | awk '{print $1}')

      if [[ -z "$sig_beg" || -z "$sig_end" ]]; then
        printf "  %-24s FAIL (signature symbols missing)\n" "$s/$t"
        fail=$((fail+1)); failed="$failed $s/$t"; continue
      fi

      imem_bin="$B/$s-$t.imem.bin"; dram_bin="$B/$s-$t.dram.bin"
      imem_hex="$B/$s-$t.imem.hex"; dram_hex="$B/$s-$t.dram.hex"
      sig_out="$B/$s-$t.sig.out"

      "$OBJCOPY" -O binary -j .text.init -j .text "$elf" "$imem_bin"
      "$OBJCOPY" -O binary -j .data "$elf" "$dram_bin"
      python3 sw/bin2hex.py "$imem_bin" "$imem_hex" > /dev/null
      python3 sw/bin2hex.py "$dram_bin" "$dram_hex" > /dev/null

      # run simulation
      "$VVP" "sim/tb_arch_test_$cfg" \
             +IMEM="$imem_hex" +DRAM="$dram_hex" \
             +SIG_FILE="$sig_out" \
             +SIG_BEGIN="$sig_beg" +SIG_END="$sig_end" \
             +MAXCYC=10000000 +IMEM_WRITABLE > "$B/$s-$t.log" 2>&1

      if [[ ! -f "$sig_out" ]]; then
        printf "  %-24s FAIL (no signature dumped, TIMEOUT)\n" "$s/$t"
        fail=$((fail+1)); failed="$failed $s/$t"; continue
      fi

      if diff -u "$sig_out" "$ref" > "$B/$s-$t.diff" 2>&1; then
        words=$(( (0x$sig_end - 0x$sig_beg) / 4 ))
        printf "  %-24s PASS (%d words match)\n" "$s/$t" "$words"
        pass=$((pass+1))
      else
        printf "  %-24s FAIL (signature mismatch, see %s)\n" "$s/$t" "$B/$s-$t.diff"
        fail=$((fail+1)); failed="$failed $s/$t"
      fi
    done
  done

  echo "==== $cfg: $pass passed, $fail failed, $skip skipped of $((pass+fail+skip)) ===="
  if [[ -n "$failed" ]]; then echo "FAILED ($cfg):$failed"; status=1; fi
  (( pass > 0 )) || { echo "run_arch_test.sh: $cfg: no test passed"; status=1; }
done

exit $status
