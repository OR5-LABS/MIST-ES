<div align="center">

# MIST-ES

<p align="center">
  <img src="https://img.shields.io/badge/ISA-RV32IMC-green" alt="ISA"/>
  <img src="https://img.shields.io/badge/Extensions-Zicsr-blue" alt="Extensions"/>
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License"/>
  <a href="https://www.linkedin.com/company/open-risc-v/"><img src="https://img.shields.io/badge/LinkedIn-Follow-0077B5" alt="LinkedIn Follow"/></a>
  <a href="https://or5.org"><img src="https://img.shields.io/badge/Visit-or5.org-brightgreen?logo=google-chrome" alt="Visit or5.org"/></a>
</p>

</div>

A compact, area-optimized, and fully verified **RV32IMC** processor core in synthesizable SystemVerilog. It executes instructions one at a time through a clean, deterministic multi-cycle finite state machine — no pipeline, no hazard logic, and no branch misprediction penalties — keeping the design tiny, area-efficient, and straightforward to verify. It targets embedded control-plane state machines, secure boot ROMs, safety-critical subsystems, and resource-constrained FPGA soft-cores.

---

## Overview

| | |
| :--- | :--- |
| **ISA** | `RV32IMC_Zicsr` |
| **Microarchitecture** | Multi-cycle FSM, non-pipelined, deterministic |
| **Privilege Modes** | Machine (M); optional User (U) in `SECURE` configuration |
| **Security & Memory Protection** | 8-region PMP + Smepmp (`mseccfg`: MML, MMWP, RLB) |
| **Reliability** | SECDED (39, 32) ECC-protected register file (`SECURE` build) |
| **Bus Interfaces** | Native memory port + AXI4-Lite master/slave bridge |
| **Debug** | RISC-V External Debug via JTAG (debug spec 0.13, DTM + DM) |
| **Arch Compliance** | Official RISC-V Architectural Test Suite (`riscv-arch-test`) + `riscv-tests` |
| **Target FPGA** | Artix-7 100T (Digilent Arty A7) |

---

## Features

- **Predictable, Zero-Hazard Execution:** Single instruction walks a short FSM (`FETCH` → `EXEC` → `{LOAD | MD}` → `FETCH`) with zero pipeline hazards and no forwarding complexity
- **Full Standard Extension Coverage:** Complete support for `I` (base integer), `M` (hardware multiply/divide), `C` (16-bit compressed instructions with transparent decompression), and `Zicsr` (CSR access)
- **Two-Tier Trust Model (`SECURE` Build):** Optional `SECURE` build adds User privilege mode and an 8-region Physical Memory Protection (PMP) unit with **Smepmp** rules: Machine Mode Lockdown (`MML`), Machine Mode Whitelist Policy (`MMWP`), and Rule Locking Bypass (`RLB`)
- **Register File ECC:** `SECURE` configuration includes a single-error-correct, double-error-detect (**SECDED 39, 32**) Hamming-code protected register file for high-reliability and radiation-tolerant environments
- **Hardware-Resolved Misalignment:** Unaligned loads and stores are handled natively in hardware as two memory beats without raising exceptions
- **RISC-V External Debug over JTAG:** JTAG Debug Transport Module (DTM) and RISC-V Debug Module (0.13 spec) supporting halt, register/CSR inspection, system-bus memory read/write, resume, and single-step
- **Dual Bus Interfaces:** Zero-latency native memory port for tightly-coupled memory integration, plus drop-in **AXI4-Lite master/slave** bridge for standard SoC fabrics
- **Clean Synthesizable RTL:** Pure SystemVerilog with no proprietary IP, tested on Artix-7 and verified across Icarus Verilog, Verilator, and Vivado

---

## Resource Utilization

Synthesized and implemented with **AMD Vivado 2023.2** targeting the **Xilinx Artix-7 100T** (`xc7a100tcsg324-1`) on the Digilent Arty A7 evaluation board.

| Configuration | Slice LUTs | Registers (FF) | DSP48E1 | BRAM | Target Platform |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Core — Default (M-mode only) | 2,491 | 749 | 4 | 0 | — |
| Core — SECURE (M+U, PMP, ECC) | 4,362 | 1,400 | 4 | 0 | — |
| Full SoC — Default (128 KB BRAM) | 2,816 | 1,335 | 4 | 32 | Digilent Arty A7 |
| Full SoC — SECURE (128 KB BRAM) | 5,226 | 1,980 | 4 | 32 | Digilent Arty A7 |

Enable the secure configuration via the `SECURE` RTL parameter or compile-time define `-DMIST_ES_SECURE`.

### Core Hierarchical Utilization Breakdown

| Sub-Module / Unit | Description | Default LUTs (FFs) | SECURE LUTs (FFs) |
| :--- | :--- | :---: | :---: |
| `mist_es_regfile` | GPR File (32×32-bit, plain vs SECDED ECC) | 1,403 (0 FFs) | 1,596 (0 FFs) |
| `mist_es_csr` | CSR File (Zicsr, Machine/User, 8-region PMP/ePMP) | 389 (320 FFs) | 2,054 (965 FFs) |
| `mist_es_muldiv` | 32-bit Iterative Multiply & Divide Engine | 437 (237 FFs) | 458 (237 FFs) |
| `mist_es_pmp` | Physical Memory Protection Checker | — | 21 (0 FFs) |
| Control & Exec | FSM, 32-bit ALU, Decoder, RVC Expander, ImmGen | 262 (192 FFs) | 269 (198 FFs) |

---

## Benchmark Metrics

Measured in cycle-accurate Verilator simulation compiled with `riscv-none-elf-gcc -O2 -march=rv32imc_zicsr -mabi=ilp32`.

| Benchmark | Result | Details |
| :--- | :--- | :--- |
| **CoreMark** (1,000 iterations) | **1.18 CoreMark/MHz** | 847,547.1 cycles/iter, CRCs validated |
| **Dhrystone 2.1** (100,000 runs) | **0.388 DMIPS/MHz** | 683 Dhrystones/sec/MHz, 2.973 CPI |

```bash
# Run CoreMark simulation
cd bench && make verilator-mist-es && make run-mist-es-coremark ITERATIONS=1000

# Run Dhrystone simulation
cd dhrystone && ./run_dhrystone.sh
```

Detailed results, compiler flags, and methodology: **[benchmark.md](benchmark.md)**

---

## Requirements

| Tool | Version | Purpose |
| :--- | :--- | :--- |
| **Verilator** | 5.018 or later | Cycle-accurate RTL simulation for benchmarks |
| **Icarus Verilog** | 12.0 or later | Core simulation (`iverilog` / `vvp`) |
| **Python** | 3.10 or later | Test-program builders, co-simulation, report generation |
| **RISC-V GCC** | 13.0 or later (`riscv-none-elf-*` or `riscv64-unknown-elf-*`) | Compiling firmware, test suites, and benchmarks |
| **Vivado** | 2023.2 *(optional)* | FPGA synthesis and implementation for Arty A7 |

Set `RISCV_TC=/path/to/toolchain/bin` to point at a non-`PATH` toolchain.

---

## Build & Test

A single top-level **Makefile** covers the most common workflows. For fine-grained control every action is also available directly through `build.sh`.

### Makefile targets

```bash
make              # compile RTL + run self-checking smoke test
make arch         # run official RISC-V Architectural Compliance suite (I, M, C)
make isa          # run official riscv-tests ISA suites across both configs
make test         # run full regression battery against tests/expected.txt
make cosim        # lockstep co-simulation against golden Python ISA model
make rvfi         # RISC-V Formal Interface trace self-check
make debug        # JTAG DTM + RISC-V Debug Module verification
make pmp          # SECURE config: User mode + PMP enforcement
make epmp         # SECURE config: Smepmp (mseccfg) rules
make upriv        # SECURE config: U-mode privilege isolation
make mml          # SECURE config: Smepmp Machine Mode Lockdown
make ecc          # Register file SECDED ECC unit test
make axil         # AXI4-Lite master/slave adapter test
make fpga         # FPGA SoC simulation (UART banner + LED blink)
make clean        # remove simulation and build artifacts
make help         # list all targets
```

### All `build.sh` actions

```bash
./build.sh            # smoke test (halting at cycle 431 with tohost = 1)
./build.sh cosim      # co-simulate against the golden RV32IM ISA model
./build.sh rvfi       # RISC-V Formal Interface trace self-check
./build.sh debug      # JTAG DTM + Debug Module bit-bang verification
./build.sh pmp        # SECURE config: User mode + PMP test program
./build.sh epmp       # SECURE config: Smepmp (mseccfg) rules test
./build.sh upriv      # SECURE config: U-mode CSR / MRET privilege checks
./build.sh mml        # SECURE config: Smepmp Machine Mode Lockdown rules
./build.sh ecc        # Register-file SECDED ECC unit test
./build.sh axil       # AXI4-Lite bridge protocol validation
./build.sh fpga       # FPGA SoC simulation (UART banner + LED blink)
./build.sh clean      # remove build artifacts
./run_tests.sh        # full regression battery checked against tests/expected.txt
```

Every action exits non-zero if the testbench reports `FAIL`, `TIMEOUT`, `MISMATCH`, or does not print its `PASS` verdict.

### What each test covers

| Test | Target | What it covers |
| :--- | :--- | :--- |
| `sim` | Smoke test | Executes ALU operations, multiply/divide, branches, loads/stores, and CSR access to completion |
| `cosim` | Golden co-simulation | Every retired instruction verified against a golden Python RV32IM model retire-for-retire |
| `rvfi` | Formal interface | Instruction-level trace conforms to the RISC-V Formal Interface without protocol violations |
| `debug` | Hardware debug | JTAG DTM (0.13) + Debug Module: halt, inspect registers/CSRs, system bus memory access, resume, step |
| `pmp` | PMP & User isolation | 8-region PMP enforcement with User mode (`mstatus.MPP = 0`); illegal accesses trap |
| `epmp` | ePMP MMWP test | Enhanced PMP Machine Mode Whitelist Policy (`mseccfg.MMWP`); default-deny enforcement |
| `upriv` | Privilege isolation | Machine CSR & `MRET` access from U-mode raise illegal instruction traps |
| `mml` | Smepmp lockdown | Machine Mode Lockdown (`mseccfg.MML`) full rule set, pmpcfg and RLB write rules |
| `ecc` | Register file ECC | SECDED (39, 32) single-bit error auto-correction and double-bit error detection |
| `axil` | AXI4-Lite adapter | Multi-cycle memory to AXI4-Lite protocol conversion with synthetic wait states |
| `fpga` | FPGA SoC simulation | Full board-level SoC simulation with 115200 baud UART banner transmission and LED blink |
| `arch` | Architectural tests | Official RISC-V Architectural Test Suite (`riscv-arch-test`) with in-memory signature extraction |
| `isa` | ISA compliance | Official `riscv-tests` suites (rv32ui, rv32um, rv32uc, rv32mi) on both configurations |

Full pass/fail results, logs, and per-test details: **[tests_report.md](tests_report.md)**.

---

## RISC-V Architectural Compliance

MIST-ES is verified against both the official **RISC-V Architecture Test suite** (`riscv-arch-test`) and the official **Berkeley ISA suites** (`riscv-tests`).

### 1. Official RISC-V Architecture Tests (`riscv-arch-test`)

Tested via in-memory signature extraction and automated bit-for-bit `diff` comparison against official golden reference signatures (`.reference_output`) curated by RISC-V International.

```bash
./run_arch_test.sh                   # runs I, M, C suites on default build
./run_arch_test.sh all               # runs all suites on both default and SECURE builds

# Run individual suites:
./run_arch_test.sh default I         # RV32I Base Integer (38 tests)
./run_arch_test.sh default M         # RV32M Multiply & Divide (8 tests)
./run_arch_test.sh default C         # RV32C Compressed Instructions (27 tests)
./run_arch_test.sh secure            # SECURE build (U-mode + PMP + ECC)
```

| Suite | Tests | Default Build | SECURE Build | Status |
| :--- | :---: | :---: | :---: | :---: |
| **RV32I — Base Integer** | 38 | 38 PASS | 38 PASS | **PASS (100%)** |
| **RV32M — Multiply & Divide** | 8 | 8 PASS | 8 PASS | **PASS (100%)** |
| **RV32C — Compressed Instructions** | 27 | 26 PASS (1 skip*) | 26 PASS (1 skip*) | **PASS (100%)** |
| **Total** | **73** | **72 passed (1 skip)** | **72 passed (1 skip)** | **PASS (100%)** |

> [!NOTE]  
> *`cebreak-01` skip note: MIST-ES writes `mtval = 0` on breakpoint traps per §3.1.20 of the RISC-V Privileged Architecture Specification ("*When a breakpoint exception is generated, mtval is written with the address of the faulting instruction, or zero*"), whereas the reference signature model expects `mtval = faulting_pc`.

### 2. Official ISA Tests (`riscv-tests`)

```bash
./run_isa.sh all                     # run rv32ui, rv32um, rv32uc, rv32mi on both builds
```

| Suite | Default Build | SECURE Build (U-mode) |
| :--- | :---: | :---: |
| `rv32ui` | 41 / 41 pass, 1 skipped* | 41 / 41 pass, 1 skipped* |
| `rv32um` | 8 / 8 pass | 8 / 8 pass |
| `rv32uc` | 1 / 1 pass | 1 / 1 pass |
| `rv32mi` | 15 / 15 pass, 1 skipped* | 16 / 16 pass |
| **Total** | **65 passed, 0 failed, 2 skipped** | **66 passed, 0 failed, 1 skipped** |

*`rv32ui/fence_i` skipped (Zifencei is omitted by architectural design; raises illegal instruction trap); `rv32mi/pmpaddr` skipped on default build (PMP is implemented exclusively on the SECURE build, where it passes).

---

## Configuration Options

MIST-ES ships in two build-time configurations, selected by the `SECURE` RTL parameter or compile-time define `-DMIST_ES_SECURE`:

| Property / Feature | Default | SECURE |
| :--- | :--- | :--- |
| **Privilege Modes** | Machine (M) only | Machine (M) + User (U) |
| **Memory Protection** | — | 8-region PMP + Smepmp (`mseccfg`: MML, MMWP, RLB) |
| **Register File** | Plain 32×32-bit GPR | SECDED (39, 32) ECC protected |
| **Target Use Case** | Smallest area footprint | Isolation, security, high reliability |
| **`misa` U-bit** | Not set | Set (bit 20 = 1) |
| **Locked PMP Regions** | — | Enforced on Machine mode as well |

---

## Repository Layout

```
MISt-ES/
├── Makefile                    top-level build & test entry point
├── build.sh                    fine-grained simulation & test driver
├── run_tests.sh                automated regression runner (checks against tests/expected.txt)
├── run_isa.sh                  official riscv-tests ISA suite runner
├── run_arch_test.sh            official riscv-arch-test suite runner
├── tests_report.md             comprehensive verification & test report
├── benchmark.md                detailed performance benchmarks (CoreMark, Dhrystone)
├── rtl/
│   ├── mist_es_core.sv         multi-cycle datapath & control FSM
│   ├── mist_es_soc.sv          minimal SoC wrapper (IMEM, DRAM, CLINT, tohost)
│   ├── mist_es_debug.sv        JTAG DTM + RISC-V Debug Module (0.13 spec)
│   ├── mist_es_axil.sv         AXI4-Lite master/slave adapter & SoC wrapper
│   └── common/                 shared leaf cells (ALU, MulDiv, RegFile, RegFile ECC,
│                               CSR, RVC, ImmGen, Branch, Decode, PMP)
├── tb/                         testbenches (tb_mist_es.sv, RVFI, debug, ECC, AXI)
├── arch-test/                  RISC-V architectural compliance test port (target/mist_es/)
├── third_party/
│   ├── riscv-arch-test/        official RISC-V International Architecture Tests
│   └── riscv-tests/            official Berkeley RISC-V ISA tests
├── coremark/                   bare-metal CoreMark port & cycle-accurate runner
├── dhrystone/                  bare-metal Dhrystone 2.1 port & cycle-accurate runner
├── fpga/                       FPGA top-level SoC wrapper + Arty A7 XDC constraints
├── bench/                      benchmarking automation scripts & reporting
├── programs/                   assembly smoke test builders
├── sw/                         firmware, binary-to-hex utilities, bring-up tests
├── tools/                      golden Python ISA model + co-simulation driver
└── tests/                      regression baselines (expected.txt)
```

---

## License

Released under the [MIT License](LICENSE) — free for commercial, research, and academic use.
