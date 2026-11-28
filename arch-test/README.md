# MIST-ES architecture tests

Runs the official RISC-V Architecture Test suite (riscv-arch-test 2.7.4, legacy
framework with in-repo reference signatures) on the MIST-ES SoC (RV32IMC, machine mode). Each test is compiled with
the target files in `target/`, simulated with Verilator, and the memory
signature is compared word for word against the upstream
`.reference_output`.

    ./build.sh arch            # or: make arch
    ./build.sh arch --suite M  # one suite (I, M, C, privilege)
    ./build.sh arch --test cebreak -v

The suite is fetched on demand (`git clone --branch 2.7.4`) into the
git-ignored `arch-test/riscv-arch-test`; set it up as a symlink to an existing
checkout to avoid the clone.

## Layout

- `target/mist_es/` — `model_test.h`, `link.ld`, `entry.S`. Code links into IMEM at
  0x0 (reset vector), data/signature/tohost into DRAM at 0x8000_0000; the halt
  macro stores 1 to tohost (0x2000_0000).
- `run_arch_test.py` — builds, runs and compares each test.
- `../tb/tb_mist_es_arch.sv` — testbench: loads the IMEM/DRAM images, dumps the
  signature on the tohost store.

## Suites

| Suite | Tests | Notes |
| :--- | :---: | :--- |
| I | 38 | |
| M | 8 | |
| C | 27 | |
| privilege | 16 | the 5 misaligned load/store tests accept the hardware-misaligned result (see below) |

Not run:

- Zifencei: FENCE.I is not implemented (illegal-instruction trap), so the suite does not apply.
- A (atomics), B / Zb*: riscv-arch-test 2.7.4 contains no such suite; not covered by this suite version.

## Misaligned accesses

The core performs misaligned loads and stores in hardware (two bus beats, see
the `S_LOAD2` / `S_STORE2` states), so the upstream trap-based expectation
for `misalign-{lw,lh,lhu,sh,sw}-01` does not apply. For exactly those five
tests the runner also accepts the signature a hardware-misaligned
implementation must produce (`HW_MISALIGNED_GOLDEN`, fully spelled out in the
runner, no wildcards); a signature that matches neither is a failure. Run with
`--no-hw-misaligned` to require the upstream trap-based result only.

## Known failures

- `privilege/ebreak`, `C/cebreak-01`: signature word 5 (mtval after EBREAK).
  The reference expects mtval = address of the EBREAK; the core writes
  mtval = 0 (`ex_tval` in `rtl/mist_es_core.sv` is 0 for breakpoints). The
  privileged spec allows either, but the reference signature does not, so the
  tests are counted as failures.
