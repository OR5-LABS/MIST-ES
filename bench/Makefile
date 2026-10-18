###############################################################################
# bench/Makefile — MIST-ES benchmark suite (CoreMark)
#
# ---- MIST-ES targets --------------------------------------------------------
#   make verilator-mist-es    — build MIST-ES Verilator model
#   make run-mist-es          — run all benchmarks on MIST-ES
#   make coremark             — compile CoreMark
#   make report               — generate benchmark report
#   make all                  — build & run everything
#
# Variables:
#   RISCV_GCC, ITERATIONS, SCALE, VERILATOR, CXX
###############################################################################

SHELL := /bin/bash
.DEFAULT_GOAL := all

# ---- Directories ------------------------------------------------------------
BENCH_DIR   := .
ROOT_DIR    := ..
RTL_DIR     := $(ROOT_DIR)/rtl
RTL_COMMON  := $(RTL_DIR)/common

BUILD_DIR   := $(BENCH_DIR)/build
V_BUILD_DIR := /tmp/mist_es_sim_$(USER)
WORKSPACE_LINK := /tmp/mist_es_workspace
SIM_DIR     := $(ROOT_DIR)/sim
RESULTS_DIR := $(BENCH_DIR)/results

COREMARK_SRC := $(BENCH_DIR)/coremark/upstream

# ---- Toolchain detection ----------------------------------------------------
VERILATOR ?= verilator
CXX       ?= g++

# Try to find a RISC-V GCC
ifeq ($(RISCV_GCC),)
  RISCV_GCC := $(firstword \
    $(wildcard $(RISCV_TC)/riscv-none-elf-gcc) \
    $(shell command -v riscv-none-elf-gcc      2>/dev/null) \
    $(shell command -v riscv64-unknown-elf-gcc 2>/dev/null) \
    $(shell command -v riscv32-unknown-elf-gcc 2>/dev/null) \
    $(shell command -v riscv64-elf-gcc         2>/dev/null) \
    $(shell command -v riscv32-elf-gcc         2>/dev/null) \
    NOTFOUND)
endif

ifneq ($(filter-out NOTFOUND,$(RISCV_GCC)),)
  GCC_PREFIX := $(patsubst %gcc,%,$(RISCV_GCC))
  OBJCOPY    := $(GCC_PREFIX)objcopy
  OBJDUMP    := $(GCC_PREFIX)objdump
  SIZE       := $(GCC_PREFIX)size
else
  $(error No RISC-V GCC found. Set RISCV_GCC= or add riscv64-unknown-elf-gcc to PATH)
endif

# ---- Compiler flags ---------------------------------------------------------
ARCH_FLAGS  := -march=rv32imc_zicsr -mabi=ilp32
COMMON_CFLAGS := $(ARCH_FLAGS) \
                 -O2 \
                 -ffreestanding \
                 -ffunction-sections \
                 -fdata-sections \
                 -fno-builtin \
                 -fno-common \
                 -Wall \
                 -nostdlib \
                 -nostartfiles

LDFLAGS     := -T $(BENCH_DIR)/common/bench.ld \
               -Wl,--gc-sections \
               -Wl,-Map=$(@:.elf=.map)

COMMON_SRCS := $(BENCH_DIR)/common/syscalls.c \
               $(BENCH_DIR)/common/printf.c

COMMON_INC  := -I$(BENCH_DIR)/common

# Default startup file
CRT0 := $(BENCH_DIR)/common/crt0.S

ITERATIONS  ?= 1000
SCALE       ?= 100


###############################################################################
# fetch — clone upstream sources
###############################################################################
.PHONY: fetch fetch-coremark
fetch: fetch-coremark

fetch-coremark: $(COREMARK_SRC)/.git

$(COREMARK_SRC)/.git:
	@if [ ! -d "$(COREMARK_SRC)" ] || [ -z "$$(ls -A $(COREMARK_SRC))" ]; then \
		echo "[FETCH] Cloning CoreMark..."; \
		git clone --depth=1 https://github.com/eembc/coremark $(COREMARK_SRC); \
	else \
		echo "[FETCH] CoreMark directory $(COREMARK_SRC) already exists, skipping clone."; \
	fi

###############################################################################
# verilator — build MIST-ES simulation model
###############################################################################
VERILATOR_SV := \
    rtl/common/mist_es_pkg.sv \
    rtl/common/mist_es_alu.sv \
    rtl/common/mist_es_regfile.sv \
    rtl/common/mist_es_muldiv.sv \
    rtl/common/mist_es_csr.sv \
    rtl/common/mist_es_rvc.sv \
    rtl/common/mist_es_immgen.sv \
    rtl/common/mist_es_branch.sv \
    rtl/common/mist_es_decode.sv \
    rtl/common/mist_es_pmp.sv \
    rtl/mist_es_core.sv \
    rtl/mist_es_debug.sv \
    bench/verilator/bench_top.sv

VERILATOR_CPP := bench/verilator/main.cpp

SIM_BIN := $(V_BUILD_DIR)/Vbench_obj/Vbench_top

.PHONY: verilator verilator-mist-es
verilator: $(SIM_BIN)
verilator-mist-es: $(SIM_BIN)

$(SIM_BIN): $(VERILATOR_SV:%=$(ROOT_DIR)/%) $(ROOT_DIR)/$(VERILATOR_CPP) | $(SIM_DIR)
	@echo "[VERILATOR] Creating workspace symlink to bypass space-in-path limits..."
	ln -sfn "$(realpath $(ROOT_DIR))" $(WORKSPACE_LINK)
	@echo "[VERILATOR] Building MIST-ES simulation model in safe temp directory..."
	mkdir -p $(V_BUILD_DIR)/Vbench_obj
	$(VERILATOR) --Mdir "$(V_BUILD_DIR)/Vbench_obj" -o Vbench_top \
	    -f $(WORKSPACE_LINK)/bench/verilator/mist_es.f \
	    $(VERILATOR_SV:%=$(WORKSPACE_LINK)/%) \
	    $(WORKSPACE_LINK)/$(VERILATOR_CPP)
	@echo "[VERILATOR] MIST-ES build complete: $@"

$(SIM_DIR):
	mkdir -p $@

###############################################################################
# coremark — compile CoreMark
###############################################################################
COREMARK_HEX := $(BUILD_DIR)/coremark.hex
COREMARK_ELF := $(BUILD_DIR)/coremark.elf

COREMARK_SRCS_UPSTREAM := \
    $(COREMARK_SRC)/core_list_join.c \
    $(COREMARK_SRC)/core_main.c \
    $(COREMARK_SRC)/core_matrix.c \
    $(COREMARK_SRC)/core_state.c \
    $(COREMARK_SRC)/core_util.c

COREMARK_PORT := \
    $(BENCH_DIR)/coremark/port/core_portme.c

COREMARK_ALL_SRCS := \
    $(COMMON_SRCS) \
    $(COREMARK_SRCS_UPSTREAM) \
    $(COREMARK_PORT)

COREMARK_CFLAGS := $(COMMON_CFLAGS) \
    $(COMMON_INC) \
    -I$(COREMARK_SRC) \
    -I$(BENCH_DIR)/coremark/port \
    -DITERATIONS=$(ITERATIONS) \
    -DMEM_METHOD=MEM_STATIC \
    -DMULTITHREAD=1 \
    -DUSE_FORK=0 \
    -DUSE_PTHREAD=0 \
    -DHAS_FLOAT=0 \
    -DHAS_TIME_H=0 \
    -DUSE_CLOCK=0 \
    -DHAS_STDIO=0 \
    -DHAS_PRINTF=1 \
    -DCOMPILER_FLAGS='"$(ARCH_FLAGS) -O2"' \
    -DCOMPILER_VERSION='"$(shell $(RISCV_GCC) --version | head -1)"' \
    -DPERFORMANCE_RUN=1

.PHONY: coremark
coremark: fetch-coremark $(COREMARK_HEX)

$(COREMARK_HEX): $(COREMARK_ELF) | $(BUILD_DIR)
	$(OBJCOPY) -O binary $< $(BUILD_DIR)/coremark.bin
	python3 $(ROOT_DIR)/sw/bin2hex.py $(BUILD_DIR)/coremark.bin $@
	$(SIZE) $<
	@echo "[COREMARK] Hex: $@"

$(COREMARK_ELF): $(COREMARK_ALL_SRCS) $(CRT0) | $(BUILD_DIR) $(COREMARK_SRC)/.git
	@echo "[COREMARK] Compiling (ITERATIONS=$(ITERATIONS))...."
	$(RISCV_GCC) $(COREMARK_CFLAGS) $(LDFLAGS) \
	    -Wl,-Map=$(BUILD_DIR)/coremark.map \
	    -o $@ $(filter %.c %.S,$^)

$(BUILD_DIR):
	mkdir -p $@


###############################################################################
# run targets
###############################################################################
TIMEOUT_CYCLES ?= 2000000000  # 2 Billion cycles

MIST_ES_RESULTS := $(RESULTS_DIR)/mist_es

.PHONY: run-coremark run-mist-es-coremark
run-coremark: run-mist-es-coremark
run-mist-es-coremark: $(SIM_BIN) $(COREMARK_HEX) | $(MIST_ES_RESULTS) $(RESULTS_DIR)
	@echo "[RUN/MIST-ES] CoreMark..."
	set -o pipefail; $(SIM_BIN) --hex $(COREMARK_HEX) --name coremark \
	    --max-cycles $(TIMEOUT_CYCLES) \
	    | tee $(MIST_ES_RESULTS)/coremark.log

DHRYSTONE_HEX ?= $(ROOT_DIR)/dhrystone/build/dhrystone.hex

.PHONY: run-dhrystone run-mist-es-dhrystone
run-dhrystone: run-mist-es-dhrystone
run-mist-es-dhrystone: $(SIM_BIN) | $(MIST_ES_RESULTS) $(RESULTS_DIR)
	@set -o pipefail; HEX=$${HEX_FILE:-$(DHRYSTONE_HEX)}; \
	echo "[RUN/MIST-ES] Dhrystone ($$HEX)..."; \
	$(SIM_BIN) --hex "$$HEX" --name dhrystone \
	    --max-cycles $(TIMEOUT_CYCLES) \
	    | tee $(MIST_ES_RESULTS)/dhrystone.log


.PHONY: run-mist-es run-all
run-mist-es: run-mist-es-coremark
run-all: run-mist-es

$(RESULTS_DIR):
	mkdir -p $@

$(MIST_ES_RESULTS):
	mkdir -p $@

###############################################################################
# report — benchmark report (MIST-ES)
###############################################################################
.PHONY: report
report: run-mist-es | $(RESULTS_DIR)
	python3 $(BENCH_DIR)/run_bench.py \
	    --results-dir $(MIST_ES_RESULTS) \
	    --iterations $(ITERATIONS)

###############################################################################
# all
###############################################################################
.PHONY: all
all: fetch verilator-mist-es coremark run-mist-es report

###############################################################################
# clean / distclean / help
###############################################################################
.PHONY: clean distclean help
clean:
	rm -rf $(BUILD_DIR) $(RESULTS_DIR)
	rm -rf $(V_BUILD_DIR)/Vbench_obj

distclean: clean
	rm -rf $(COREMARK_SRC)

help:
	@echo "MIST-ES Benchmark Suite (CoreMark)"
	@echo ""
	@echo "  make all              — fetch + build + run + report"
	@echo "  make fetch            — clone CoreMark source"
	@echo "  make verilator-mist-es — build MIST-ES Verilator simulation model"
	@echo "  make coremark         — compile CoreMark (ITERATIONS=$(ITERATIONS))"
	@echo "  make run-mist-es      — run CoreMark on MIST-ES"
	@echo "  make report           — generate results report"
	@echo "  make clean            — remove build/ and results/"
	@echo "  make distclean        — also remove fetched sources"
	@echo ""
	@echo "Key variables:"
	@echo "  RISCV_GCC=$(RISCV_GCC)"
	@echo "  VERILATOR=$(VERILATOR)"
	@echo "  ITERATIONS=$(ITERATIONS)"
