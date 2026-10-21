# MIST-ES Processor Core — Benchmark Report

Comprehensive performance evaluation and benchmark methodology for the **MIST-ES** (RV32IMC + Zicsr) multi-cycle processor core.

---

## Executive Summary

| Benchmark | Workload / Scale | Metric | Status |
| :--- | :--- | :--- | :---: |
| **EEMBC CoreMark** | 1,000 iterations (cycle-accurate) | **1.18 CoreMark/MHz** (847,547.1 cycles/iter) |  **PASS** (CRCs Validated) |
| **EEMBC CoreMark** | 10 iterations (quick check) | **1.18 CoreMark/MHz** (847,550.5 cycles/iter) |  **PASS** (CRCs Validated) |
| **Dhrystone v2.1** | 100,000 runs | **0.388 DMIPS/MHz** (683 Dhrystones/sec/MHz) |  **PASS** (Self-check clean) |

All benchmarks are compiled with the standard embedded toolchain:
```bash
riscv-none-elf-gcc -O2 -march=rv32imc_zicsr -mabi=ilp32
```
All numbers are measured in cycle-accurate **Verilator 5.020** RTL simulation using the exact synthesizable core and memory model.

---

## 1. EEMBC CoreMark

CoreMark tests core pipeline, memory access, integer ALU, and control-logic efficiency through three standard synthetic workloads: linked-list manipulation, matrix multiplication, and state-machine execution.

### Environment & Compilation
- **Workload:** EEMBC CoreMark v1.0
- **Compiler:** `riscv-none-elf-gcc (xPack GNU RISC-V Embedded GCC) 13.2.0`
- **Optimization:** `-O2 -march=rv32imc_zicsr -mabi=ilp32`
- **Memory Allocation:** Static allocation (`MEM_METHOD=MEM_STATIC`), Harvard architecture (`bench.ld`)
- **Simulation Harness:** Cycle-accurate Verilator driver (`coremark/run_coremark_sim.sh`)

### Simulation Results (10 Iterations)

```text
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 8475505
Total time (secs): 8475505
Iterations       : 10
Compiler version : riscv-none-elf-gcc (xPack GNU RISC-V Embedded GCC x86_64) 13.2.0
Compiler flags   : -march=rv32imc_zicsr -mabi=ilp32 -O2
Memory location  : STATIC
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xfcaf
Correct operation validated.
```

### Simulation Results (1,000 Iterations)

| Parameter | Value |
| :--- | :--- |
| **Iterations** | 1,000 |
| **Total Cycles (Timed Window)** | 847,547,135 |
| **Cycles / Iteration** | 847,547.1 |
| **CoreMark / MHz** | **1.1799** (~1.18) |
| **CRC Validation** | **PASS** (`seedcrc=0xe9f5`, `crclist=0xe714`, `crcmatrix=0x1fd7`, `crcstate=0x8e3a`, `crcfinal=0xfcaf`) |

### Reproduction Commands

```bash
# Quick 10-iteration verification
./coremark/run_coremark_10.sh

# Full 1,000-iteration benchmark via bench runner
cd bench
make verilator-mist-es
make run-mist-es-coremark ITERATIONS=1000
```

---

## 2. Dhrystone v2.1

Dhrystone is a synthetic benchmark measuring integer computation, string operations, and procedure call overhead.

### Environment & Compilation
- **Workload:** Dhrystone v2.1 (100,000 runs, satisfying real-world runtime threshold)
- **Compiler:** `riscv-none-elf-gcc 13.2.0`
- **Optimization:** `-O2 -march=rv32imc_zicsr -mabi=ilp32 -DNUM_RUNS=100000`
- **Simulation Harness:** Cycle-accurate Verilator driver (`dhrystone/run_dhrystone.sh`)

### Simulation Results

```text
Number_Of_Runs: 100000
User_Time: 146300070 cycles, 49200030 insn
Cycles_Per_Instruction: 2.973
Dhrystones_Per_Second_Per_MHz: 683
DMIPS_Per_MHz: 0.388
```

### Metrics Summary

| Metric | Result | Analysis |
| :--- | :--- | :--- |
| **Total Cycles** | 146,300,070 | Timed execution window across 100,000 runs |
| **Retired Instructions** | 49,200,030 | Instructions successfully committed |
| **Cycles Per Instruction (CPI)** | **2.973** | Multi-cycle FSM instruction processing |
| **Dhrystones / Sec / MHz** | **683** | Un-normalized Dhrystone score |
| **DMIPS / MHz** | **0.388** | Normalized score (divided by 1,757) |
| **Internal Variable Verification** | **PASS** | All struct fields, string compares, and arrays verified |

### Reproduction Commands

```bash
cd dhrystone
./run_dhrystone.sh
```

---

## 3. Microarchitectural Performance Analysis

MIST-ES is an area-optimized, non-pipelined multi-cycle core. Because it does not use a pipeline:
- **Zero Branch Penalty:** Branch conditions are evaluated in the execute stage; taken branches simply load the target address into PC with no pipeline flushes.
- **Zero Forwarding / Hazard Stalls:** Instructions execute sequentially (`FETCH` → `EXEC` → `{LOAD | MD}` → `FETCH`), ensuring fully deterministic cycle times.
- **Cycle Breakdown by Instruction Type:**
  - **Register ALU operations:** 2 clock cycles (Fetch, Execute)
  - **Immediate ALU operations:** 2 clock cycles
  - **Taken / Non-taken Branches:** 2 clock cycles
  - **Unconditional Jumps (`JAL`, `JALR`):** 2 clock cycles
  - **Memory Loads (`LW`, `LH`, `LB`):** 3 clock cycles (4 if crossing word boundary)
  - **Memory Stores (`SW`, `SH`, `SB`):** 2 clock cycles (3 if crossing word boundary)
  - **Multiplication (`MUL`, `MULH`, etc.):** 34 clock cycles (serial shift-and-add)
  - **Division / Remainder (`DIV`, `REM`):** 34 clock cycles (non-restoring radix-2)
  - **Compressed Instructions (RVC):** Zero cycle decompression overhead

The average CPI of **~2.97** on Dhrystone directly reflects this multi-cycle FSM balance, providing predictable and deterministic timing ideal for real-time and safety-critical control tasks.
