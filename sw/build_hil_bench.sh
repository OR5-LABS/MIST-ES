#!/usr/bin/env bash
# =============================================================================
# build_hil_bench.sh — Build CoreMark and Dhrystone firmware images for
#   Hardware-in-the-Loop (HIL) testing on the MIST-ES SoC / Arty A7-100T.
#
# Usage:
#   cd mist-es/          (repo root)
#   ./sw/build_hil_bench.sh [BENCH]
#
#   BENCH (optional):
#     coremark          — build only CoreMark
#     dhrystone         — build only Dhrystone
#     all  (default)    — build CoreMark + Dhrystone
#
# Output (sw/hil_build/):
#   coremark.mem          — $readmemh hex image for Vivado / openFPGALoader
#   coremark.elf          — ELF (for objdump / GDB)
#   dhrystone.mem
#   dhrystone.elf
#
# The SoC is parameterised as MEM_WORDS=4096 (16 KB unified RAM).
# Each image is checked that it fits inside 16 KB; the script will error if it
# overflows.
#
# Prerequisites:
#   riscv64-unknown-elf-gcc (or riscv-none-elf-gcc) on PATH
#   CoreMark cloned at bench/coremark/upstream/
#   (run `make -C bench fetch-coremark` first if not already present)
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCH_CMD="${1:-all}"

# ---------------------------------------------------------------------------
# Toolchain detection (same logic as bench/Makefile)
# ---------------------------------------------------------------------------
TC="${RISCV_TC:-/opt/riscv/bin}"
if [[ -n "$TC" && -x "$TC/riscv-none-elf-gcc" ]]; then
    GCC="$TC/riscv-none-elf-gcc"
    OBJCOPY="$TC/riscv-none-elf-objcopy"
elif command -v riscv-none-elf-gcc &>/dev/null; then
    GCC="riscv-none-elf-gcc"
    OBJCOPY="riscv-none-elf-objcopy"
elif command -v riscv64-unknown-elf-gcc &>/dev/null; then
    GCC="riscv64-unknown-elf-gcc"
    OBJCOPY="riscv64-unknown-elf-objcopy"
elif command -v riscv64-elf-gcc &>/dev/null; then
    GCC="riscv64-elf-gcc"
    OBJCOPY="riscv64-elf-objcopy"
elif command -v riscv32-unknown-elf-gcc &>/dev/null; then
    GCC="riscv32-unknown-elf-gcc"
    OBJCOPY="riscv32-unknown-elf-objcopy"
else
    echo "ERROR: No RISC-V GCC found. Set RISCV_TC or ensure riscv-none-elf-gcc / riscv64-unknown-elf-gcc is in your PATH."
    exit 1
fi

echo "[HIL] Toolchain: $GCC"

# ---------------------------------------------------------------------------
# Directories
# ---------------------------------------------------------------------------
SW_DIR="$ROOT/sw"
BENCH_DIR="$ROOT/bench"
OUT_DIR="$SW_DIR/hil_build"
COREMARK_SRC="$BENCH_DIR/coremark/upstream"

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# Base compiler flags — stored as an ARRAY to avoid word-splitting issues.
# Each flag is a separate element; no concatenation tricks needed.
# ---------------------------------------------------------------------------
BASE_CFLAGS=(
    -march=rv32imc_zicsr
    -mabi=ilp32
    -O2
    -ffreestanding
    -ffunction-sections
    -fdata-sections
    -fno-builtin
    -fno-common
    -Wall
    -nostdlib
    -nostartfiles
)



# Use the FPGA-specific linker script and startup
LD_SCRIPT="$SW_DIR/fpga_bench.ld"
CRT0="$SW_DIR/crt0_fpga.S"

# FPGA-specific syscalls (UART-backed _write)
SYSCALLS_FPGA="$SW_DIR/syscalls_fpga.c"

# printf implementation (shared with simulation build)
PRINTF_C="$BENCH_DIR/common/printf.c"

BASE_LDFLAGS=(
    -T "$LD_SCRIPT"
    -Wl,--gc-sections
)

# Max image size: 128 KB (matches MEM_WORDS=32768 in mist_es_fpga.sv)
MAX_BYTES=$(( 128 * 1024 ))

# ---------------------------------------------------------------------------
# Helper: compile → ELF → BIN → MEM, check size
#   build_image <name> <extra_cflags_array_name> <srcs...>
#   build_image <name> <extra_cflags_array_name> --libs <lib...> -- <srcs...>
# ---------------------------------------------------------------------------
build_image() {
    local name="$1"
    local -n _extra_flags="$2"   # nameref to caller's extra-flags array
    shift 2

    # Optional: parse --libs <lib...> -- <srcs...>
    local link_libs=()
    if [[ "${1:-}" == "--libs" ]]; then
        shift
        while [[ $# -gt 0 && "$1" != "--" ]]; do
            link_libs+=("$1")
            shift
        done
        [[ "${1:-}" == "--" ]] && shift
    fi

    local srcs=("$@")

    local elf="$OUT_DIR/${name}.elf"
    local bin="$OUT_DIR/${name}.bin"
    local mem="$OUT_DIR/${name}.mem"

    echo "[HIL] Compiling ${name}..."
    "$GCC" \
        "${BASE_CFLAGS[@]}" \
        "${_extra_flags[@]}" \
        "${BASE_LDFLAGS[@]}" \
        -Wl,-Map="$OUT_DIR/${name}.map" \
        -o "$elf" \
        "${srcs[@]}" \
        "${link_libs[@]+${link_libs[@]}}"

    "$OBJCOPY" -O binary "$elf" "$bin"
    python3 "$SW_DIR/bin2hex.py" "$bin" "$mem"

    local sz
    sz=$(wc -c < "$bin")
    if (( sz > MAX_BYTES )); then
        echo "ERROR: ${name}.bin is ${sz} bytes — exceeds 16 KB FPGA RAM!"
        exit 1
    fi
    echo "[HIL] ${name}: ${sz} bytes / ${MAX_BYTES} bytes  →  $mem"
}

# ---------------------------------------------------------------------------
# CoreMark
# ---------------------------------------------------------------------------
build_coremark() {
    if [[ ! -d "$COREMARK_SRC" ]]; then
        echo "ERROR: CoreMark not found at $COREMARK_SRC"
        echo "       Run:  make -C bench fetch-coremark"
        exit 1
    fi

    local ITERATIONS="${ITERATIONS:-1000}"

    local srcs=(
        "$CRT0"
        "$SYSCALLS_FPGA"
        "$PRINTF_C"
        "$COREMARK_SRC/core_list_join.c"
        "$COREMARK_SRC/core_main.c"
        "$COREMARK_SRC/core_matrix.c"
        "$COREMARK_SRC/core_state.c"
        "$COREMARK_SRC/core_util.c"
        "$BENCH_DIR/coremark/port/core_portme_fpga.c"
    )

    # Each flag is a separate array element — no escaping, no quoting tricks
    local extra_flags=(
        -I"$BENCH_DIR/common"
        -I"$COREMARK_SRC"
        -I"$BENCH_DIR/coremark/port"
        "-DITERATIONS=$ITERATIONS"
        -DMEM_METHOD=MEM_STATIC
        -DMULTITHREAD=1
        -DUSE_FORK=0
        -DUSE_PTHREAD=0
        -DHAS_FLOAT=0
        -DHAS_TIME_H=0
        -DUSE_CLOCK=0
        -DHAS_STDIO=0
        -DHAS_PRINTF=1
        -DPERFORMANCE_RUN=1
        -DFPGA_HIL=1
        # Note: COMPILER_FLAGS define intentionally omitted here to avoid
        # quoting issues. CoreMark prints it via COMPILER_FLAGS macro if set.
    )

    build_image "coremark" extra_flags "${srcs[@]}"
}

# ---------------------------------------------------------------------------
# Dhrystone
# ---------------------------------------------------------------------------
build_dhrystone() {
    local DHRY_SRC="$ROOT/dhrystone"
    if [[ ! -d "$DHRY_SRC" ]]; then
        echo "ERROR: Dhrystone source not found at $DHRY_SRC"
        exit 1
    fi

    local NUM_RUNS="${NUM_RUNS:-100000}"

    local srcs=(
        "$CRT0"
        "$SYSCALLS_FPGA"
        "$PRINTF_C"
        "$DHRY_SRC/dhrystone_support.c"
        "$DHRY_SRC/dhry_1.c"
        "$DHRY_SRC/dhry_2.c"
    )

    local extra_flags=(
        -I"$BENCH_DIR/common"
        -I"$DHRY_SRC"
        "-DNUM_RUNS=$NUM_RUNS"
        -DTIME
        -DRISCV
        -std=gnu99
        -Wno-implicit-int
        -Wno-return-type
        -Wno-implicit-function-declaration
    )

    # Pass -lgcc AFTER sources so the linker can resolve __divdi3
    # (used for 64-bit integer division in the metric output)
    build_image "dhrystone" extra_flags --libs -lgcc -- "${srcs[@]}"
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
case "$BENCH_CMD" in
    coremark)
        build_coremark
        ;;
    dhrystone)
        build_dhrystone
        ;;
    all)
        build_coremark
        build_dhrystone
        ;;
    *)
        echo "ERROR: Unknown bench '$BENCH_CMD'. Valid options: coremark | dhrystone | all"
        exit 1
        ;;
esac

echo ""
echo "==================================================================="
echo " HIL firmware images written to: $OUT_DIR"
echo ""
echo " Next steps:"
echo "   1. Copy CoreMark image as firmware.mem for Vivado:"
echo "      cp $OUT_DIR/coremark.mem $ROOT/sw/firmware.mem"
echo ""
echo "   2. Build bitstream (from fpga/arty_a7/):"
echo "      vivado -mode batch -source mist_es_arty_a7.tcl"
echo ""
echo "   3. Flash to Arty A7-100T:"
echo "      openFPGALoader -b arty_a7_100t $ROOT/fpga/arty_a7/build/mist_es_arty_a7.bit"
echo ""
echo "   4. Capture results (115200 baud):"
echo "      python3 sw/run_hil_bench.py --port /dev/ttyUSB1 --bench coremark"
echo "==================================================================="
