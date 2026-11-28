# ============================================================================
# Makefile for MIST-ES RISC-V architecture tests
#
# Clones official RISC-V International arch-test suite on demand and runs tests.
# ============================================================================

SHELL := /usr/bin/env bash
PYTHON ?= python3
REPO_ROOT := $(abspath $(CURDIR)/..)
ARCH_TEST_REPO ?= https://github.com/riscv-non-isa/riscv-arch-test.git
ARCH_TEST_TAG ?= 2.7.4
UPSTREAM_DIR := $(CURDIR)/riscv-arch-test

.PHONY: all test sim clone_suite clean distclean

all: test

clone_suite:
	@if [ ! -d "$(CURDIR)/riscv-test-suite" ] || [ ! -d "$(CURDIR)/riscv-test-env" ]; then \
		if [ ! -d "$(UPSTREAM_DIR)" ]; then \
			echo "==> Fetching official riscv-arch-test suite (shallow clone)..."; \
			git clone --depth 1 --branch $(ARCH_TEST_TAG) $(ARCH_TEST_REPO) $(UPSTREAM_DIR) || exit 1; \
		fi; \
		if [ ! -e "$(CURDIR)/riscv-test-suite" ]; then \
			ln -sfn riscv-arch-test/riscv-test-suite $(CURDIR)/riscv-test-suite; \
		fi; \
		if [ ! -e "$(CURDIR)/riscv-test-env" ]; then \
			ln -sfn riscv-arch-test/riscv-test-env $(CURDIR)/riscv-test-env; \
		fi; \
	fi

sim:
	@echo "==> Building MIST-ES architecture-test simulator..."
	@cd $(REPO_ROOT) && ./build.sh arch-sim

test: clone_suite sim
	@echo "==> Running RISC-V Architectural Compliance Tests..."
	@$(PYTHON) $(CURDIR)/run_arch_test.py $(ARGS)

clean:
	@rm -rf $(CURDIR)/build $(CURDIR)/__pycache__ $(REPO_ROOT)/sim/tb_mist_es_arch $(REPO_ROOT)/sim/arch_obj

distclean: clean
	@rm -rf $(CURDIR)/riscv-arch-test $(CURDIR)/riscv-test-suite $(CURDIR)/riscv-test-env
