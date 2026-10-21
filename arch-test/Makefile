# Makefile for MIST-ES RISC-V Architectural Compliance Tests

SHELL := /usr/bin/env bash
REPO_ROOT := $(abspath $(CURDIR)/..)

.PHONY: all test clean

all: test

test:
	@cd $(REPO_ROOT) && ./run_arch_test.sh

clean:
	@rm -rf $(REPO_ROOT)/build/arch-test $(REPO_ROOT)/sim/tb_arch_test*
