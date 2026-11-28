# Makefile -- top-level entry point for MIST-ES workflows

.PHONY: formal all sim cosim rvfi debug pmp epmp upriv mml ecc axil fpga test clean help arch

all: sim

sim:
	./build.sh sim

cosim:
	./build.sh cosim

rvfi:
	./build.sh rvfi

debug:
	./build.sh debug

pmp:
	./build.sh pmp

epmp:
	./build.sh epmp

upriv:
	./build.sh upriv

mml:
	./build.sh mml

ecc:
	./build.sh ecc

axil:
	./build.sh axil

fpga:
	./build.sh fpga

arch:
	$(MAKE) -C arch-test test

test:
	./tests/run_tests.sh

formal:
	./formal/run_formal.sh

clean:
	./build.sh clean
	$(MAKE) -C arch-test clean
	rm -rf build/

help:
	@echo "MIST-ES Build & Test Targets:"
	@echo "  make              compile RTL & run self-checking smoke test"
	@echo "  make cosim        run lockstep co-simulation against golden ISA model"
	@echo "  make rvfi         validate RISC-V Formal Interface trace"
	@echo "  make debug        test JTAG DTM & Debug Module"
	@echo "  make pmp          run User-mode & PMP test"
	@echo "  make epmp         run Smepmp MMWP test"
	@echo "  make upriv        run U-mode privilege isolation test"
	@echo "  make mml          run Smepmp Machine Mode Lockdown test"
	@echo "  make ecc          run register file SECDED ECC unit test"
	@echo "  make axil         run AXI4-Lite bridge self-check"
	@echo "  make fpga         simulate FPGA SoC (UART banner + LED)"
	@echo "  make arch         run the official riscv-arch-test suites (clones the suite on first use)"
	@echo "  make formal       run riscv-formal (RVFI) bounded model checks (needs OSS CAD Suite on PATH)"
	@echo "  make test         run full regression battery against tests/expected.txt"
	@echo "  make clean        clean simulation and build artifacts"
