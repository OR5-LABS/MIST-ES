# Dhrystone v2.1 Evaluation Suite for MIST-ES

This document details the toolchain, compiler options, execution parameters, score calculations, and benchmark results for the **MIST-ES** RISC-V (RV32IMC) processor core running the **Dhrystone v2.1** benchmark.

---

## Toolchain & Environment

Dhrystone is built using the project's bundled GNU RISC-V toolchain with bare-metal freestanding optimization flags:

| Setting | Value |
|---------|-------|
| **Primary Toolchain** | `xPack GNU RISC-V Embedded GCC 13.2.0` (`riscv-none-elf-gcc`) |
| **Fallback Toolchain** | `riscv64-elf-gcc` / `riscv64-unknown-elf-gcc` (GCC 13+ / 15+) |
| **Target Architecture** | `-march=rv32imc_zicsr` |
| **Target ABI** | `-mabi=ilp32` |
| **Optimization Level** | `-O2` |
| **Simulation Engine** | `Verilator 5.018+` (cycle-accurate C++ RTL model) |

### Compiler Flags

```bash
-march=rv32imc_zicsr -mabi=ilp32 \
-O2 \
-ffreestanding \
-ffunction-sections \
-fdata-sections \
-fno-builtin \
-fno-common \
-Wall \
-nostdlib \
-nostartfiles \
-std=gnu99 \
-DNUM_RUNS=100000 \
-DTIME \
-DRISCV \
-Wno-implicit-int \
-Wno-return-type \
-Wno-implicit-function-declaration
```

### Linker Flags

```bash
-T ../bench/common/bench.ld -Wl,--gc-sections -lgcc
```

---

## Execution Parameters

The industry-standard Dhrystone benchmark requires executing for at least 2 real-world seconds (≥ 100 million cycles for a 50 MHz core) to ensure statistically stable timing measurements:

- **Iterations (`NUM_RUNS`)**: **100,000** (executes for ~146M cycles on MIST-ES, clearing the 2-second threshold)
- **Timeout**: 300,000,000 simulation cycles in Verilator

---

## Benchmark Results

All benchmark metrics are measured across 100,000 runs in cycle-accurate Verilator simulation:

| Metric | Verilator Simulation (Cycle-Accurate) |
|--------|:-------------------------------------:|
| **Iterations** | 100,000 |
| **Benchmark Cycles (`User_Time`)** | **146,300,070** |
| **Retired Instructions** | **49,200,030** |
| **Cycles Per Instruction (CPI)** | **2.973** |
| **Dhrystones / sec / MHz** | **683.5** |
| **DMIPS / MHz** | **0.388** |
| **Status** | PASS |

---

## Score Calculation Methodology

1. **Cycles per Iteration**:
   $$\text{Cycles / Iteration} = \frac{\text{Benchmark Cycles}}{\text{Iterations}} = \frac{146,300,070}{100,000} = 1,463.0$$

2. **Dhrystones per Second per MHz**:
   $$\text{Dhrystones / sec / MHz} = \frac{\text{Iterations} \times 1,000,000}{\text{Benchmark Cycles}} = \frac{100,000 \times 1,000,000}{146,300,070} = 683.5$$

3. **DMIPS / MHz** (Normalized against the VAX 11/780 baseline of 1,757 Dhrystones/sec):
   $$\text{DMIPS / MHz} = \frac{\text{Dhrystones / sec / MHz}}{1,757} = \frac{683.5}{1,757} = \mathbf{0.388 \text{ DMIPS/MHz}}$$

---

## Available Runner Scripts

- **`./run_dhrystone.sh`**:
  Compiles Dhrystone with `riscv-none-elf-gcc` (GCC 13.2.0), runs 100,000 iterations in Verilator simulation, validates string/pointer self-check outputs, and prints DMIPS metrics.

---

## Execution Screenshot

![Dhrystone Simulation Output](dhry_sim.png)
