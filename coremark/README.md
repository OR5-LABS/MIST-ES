# CoreMark Evaluation Suite for MIST-ES

This document details the toolchain, compiler options, execution parameters, score calculations, and benchmark results for the **MIST-ES** RISC-V (RV32IMC) processor core running **EEMBC CoreMark**.

---

## Toolchain & Environment

CoreMark is built using the project's bundled GNU RISC-V toolchain with strict bare-metal freestanding flags:

| Setting | Value |
|---------|-------|
| **Primary Toolchain** | `xPack GNU RISC-V Embedded GCC 13.2.0` (`riscv-none-elf-gcc`) |
| **Fallback Toolchain** | `riscv64-elf-gcc` / `riscv64-unknown-elf-gcc` (GCC 13+ / 15+) |
| **Target Architecture** | `-march=rv32imc_zicsr` |
| **Target ABI** | `-mabi=ilp32` |
| **Optimization Level** | `-O2` |
| **Simulation Engine** | `Verilator 5.018+` (cycle-accurate C++ RTL model) |
| **Memory Strategy** | Static allocation (`MEM_METHOD = MEM_STATIC`) |

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
-nostartfiles
```

### Preprocessor Defines

```bash
-DPERFORMANCE_RUN=1 \
-DMAIN_HAS_NOARGC=1 \
-DHAS_STDINT_H=1 \
-DHAS_FLOAT=0 \
-DITERATIONS=1000 \
-DMEM_LOCATION="STATIC"
```

### Linker Flags & Linker Script

```bash
-T bench/common/bench.ld -Wl,--gc-sections -Wl,-Map=coremark.map
```

---

## CoreMark Performance Results

All CoreMark performance runs execute 1,000 iterations (the EEMBC minimum required workload for valid scoring).

| Environment | Target | Iterations | Total Ticks (Cycles) | Cycles / Iteration | CoreMark / MHz | Status |
|-------------|--------|:----------:|:--------------------:|:------------------:|:--------------:|:------:|
| **Verilator Simulation** | Cycle-Accurate Model | 1,000 | **847,547,135** | **847,547.1** | **1.18** | PASS |
| **Verilator Simulation** | Quick Verification | 10 | **8,475,505** | **847,550.5** | **1.18** | PASS |

---

## Score Calculation Methodology

CoreMark scores measure normalized throughput per MHz ($\text{CoreMark/MHz}$).

1. **Cycles Per Iteration (CPI)**:
   $$\text{Cycles / Iteration} = \frac{\text{Total Benchmark Ticks}}{\text{Total Iterations}}$$

2. **CoreMark / MHz**:
   $$\text{CoreMark / MHz} = \frac{1,000,000}{\text{Cycles / Iteration}}$$

### Sample Calculation (1,000 Iterations):
$$\text{Cycles / Iteration} = \frac{847,547,135}{1,000} = 847,547.135$$

$$\text{CoreMark / MHz} = \frac{1,000,000}{847,547.135} = 1.1799 \approx \mathbf{1.18 \text{ CoreMark/MHz}}$$

*Note: Benchmark loop ticks are captured directly via RISC-V 64-bit `mcycle` CSR reads around `ee_main()`, excluding boot initialization (`crt0.S`) and stack setup.*

---

## Available Runner Scripts

The `coremark/` directory provides shell drivers for running and reproducing CoreMark:

- **`./run_coremark_sim.sh`**:
  Compiles CoreMark with `riscv-none-elf-gcc` (GCC 13.2.0), runs 1,000 iterations on the Verilator cycle-accurate model, and prints formatted metrics.
  
- **`./run_coremark_10.sh`**:
  Sanity check driver running 10 iterations (~2 to 5 seconds) for quick verification of RTL or toolchain changes.

---

## Execution Screenshot

![CoreMark Simulation Output](coremark_sim.png)
