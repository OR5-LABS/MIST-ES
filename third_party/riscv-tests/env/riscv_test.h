// riscv_test.h -- MIST-ES bare-metal environment for the official riscv-tests.
//
// Modeled on the riscv-test-env "p" environment (physical memory, no virtual
// memory, one hart): the test starts at _start, a reset sequence initializes
// the machine and MRETs into the test in the mode its RVTEST_RV32x selector
// asks for (U for rv32u*, M for rv32mi; a core without U-mode stays in M).
// ECALL from any mode ends the test and writes TESTNUM to tohost:
//   1 = PASS, (n << 1) | 1 = test case n failed,
//   TESTNUM | 1337 = unexpected trap and the test has no mtvec_handler.
//
// MIST-ES-specific adaptation (see link.ld):
//   * code (.text.init/.text) is linked at 0x0000_0000 (MIST-ES IMEM: fetch
//     port plus a read-only data port); data (.data/.rodata/.bss) is linked
//     at 0x8000_0000 (DRAM).
//   * tohost is the MIST-ES SoC exit register at 0x2000_0000 (linker symbol).
// The riscv-tests LICENSE (BSD-3-Clause) is in ../LICENSE.
#ifndef _ENV_MIST_ES_RISCV_TEST_H
#define _ENV_MIST_ES_RISCV_TEST_H

#include "encoding.h"

#define TESTNUM gp

//-----------------------------------------------------------------------
// Test mode selectors
//-----------------------------------------------------------------------
#define RVTEST_RV64U  .macro init; .endm
#define RVTEST_RV32U  .macro init; .endm
#define RVTEST_RV64UF .macro init; .endm
#define RVTEST_RV32UF .macro init; .endm

#define RVTEST_ENABLE_MACHINE      \
  li a0, MSTATUS_MPP;              \
  csrs mstatus, a0;

#define RVTEST_ENABLE_SUPERVISOR               \
  li a0, MSTATUS_MPP & (MSTATUS_MPP >> 1);     \
  csrs mstatus, a0;

#define RVTEST_RV64M .macro init; RVTEST_ENABLE_MACHINE; .endm
#define RVTEST_RV32M .macro init; RVTEST_ENABLE_MACHINE; .endm
#define RVTEST_RV64S .macro init; RVTEST_ENABLE_SUPERVISOR; .endm
#define RVTEST_RV32S .macro init; RVTEST_ENABLE_SUPERVISOR; .endm

//-----------------------------------------------------------------------
// Reset-sequence helpers
//-----------------------------------------------------------------------
#define INIT_XREG                                                       \
  li x1, 0;  li x2, 0;  li x3, 0;  li x4, 0;  li x5, 0;  li x6, 0;      \
  li x7, 0;  li x8, 0;  li x9, 0;  li x10, 0; li x11, 0; li x12, 0;     \
  li x13, 0; li x14, 0; li x15, 0; li x16, 0; li x17, 0; li x18, 0;     \
  li x19, 0; li x20, 0; li x21, 0; li x22, 0; li x23, 0; li x24, 0;     \
  li x25, 0; li x26, 0; li x27, 0; li x28, 0; li x29, 0; li x30, 0;     \
  li x31, 0;

// Each optional-CSR write runs with mtvec pointing just past it, so a core
// that traps on the CSR simply continues.
#define INIT_SATP                                                       \
  la t0, 1f;                                                            \
  csrw mtvec, t0;                                                       \
  csrwi satp, 0;                                                        \
  .align 2;                                                             \
1:

// One NAPOT PMP region covering all memory with R/W/X (needed for U-mode
// tests on a core that implements PMP).
#define INIT_PMP                                                        \
  la t0, 1f;                                                            \
  csrw mtvec, t0;                                                       \
  li t0, (1 << (31 + (__riscv_xlen / 64) * (53 - 31))) - 1;             \
  csrw pmpaddr0, t0;                                                    \
  li t0, PMP_NAPOT | PMP_R | PMP_W | PMP_X;                             \
  csrw pmpcfg0, t0;                                                     \
  .align 2;                                                             \
1:

#define DELEGATE_NO_TRAPS                                               \
  csrwi mie, 0;                                                         \
  la t0, 1f;                                                            \
  csrw mtvec, t0;                                                       \
  csrwi medeleg, 0;                                                     \
  csrwi mideleg, 0;                                                     \
  .align 2;                                                             \
1:

#define RISCV_MULTICORE_DISABLE                                         \
  csrr a0, mhartid;                                                     \
  1: bnez a0, 1b

#define EXTRA_TVEC_USER
#define EXTRA_TVEC_MACHINE
#define EXTRA_INIT
#define EXTRA_INIT_TIMER
#define FILTER_TRAP
#define FILTER_PAGE_FAULT

#define INTERRUPT_HANDLER j other_exception /* No interrupts should occur */

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  6;                                                      \
        .weak stvec_handler;                                            \
        .weak mtvec_handler;                                            \
        .globl _start;                                                  \
_start:                                                                 \
        /* reset vector */                                              \
        j reset_vector;                                                 \
        .align 2;                                                       \
trap_vector:                                                            \
        /* test whether the test came from pass/fail */                 \
        csrr t5, mcause;                                                \
        li t6, CAUSE_USER_ECALL;                                        \
        beq t5, t6, write_tohost;                                       \
        li t6, CAUSE_SUPERVISOR_ECALL;                                  \
        beq t5, t6, write_tohost;                                       \
        li t6, CAUSE_MACHINE_ECALL;                                     \
        beq t5, t6, write_tohost;                                       \
        /* if an mtvec_handler is defined, jump to it */                \
        la t5, mtvec_handler;                                           \
        beqz t5, 1f;                                                    \
        jr t5;                                                          \
        /* was it an interrupt or an exception? */                      \
  1:    csrr t5, mcause;                                                \
        bgez t5, handle_exception;                                      \
        INTERRUPT_HANDLER;                                              \
handle_exception:                                                       \
        /* an exception the test does not handle */                     \
  other_exception:                                                      \
  1:    ori TESTNUM, TESTNUM, 1337;                                     \
  write_tohost:                                                         \
        sw TESTNUM, tohost, t5;                                         \
        j write_tohost;                                                 \
reset_vector:                                                           \
        INIT_XREG;                                                      \
        RISCV_MULTICORE_DISABLE;                                        \
        INIT_SATP;                                                      \
        INIT_PMP;                                                       \
        DELEGATE_NO_TRAPS;                                              \
        li TESTNUM, 0;                                                  \
        la t0, trap_vector;                                             \
        csrw mtvec, t0;                                                 \
        /* if an stvec_handler is defined, delegate exceptions to it */ \
        la t0, stvec_handler;                                           \
        beqz t0, 1f;                                                    \
        csrw stvec, t0;                                                 \
        li t0, (1 << CAUSE_LOAD_PAGE_FAULT) |                           \
               (1 << CAUSE_STORE_PAGE_FAULT) |                          \
               (1 << CAUSE_FETCH_PAGE_FAULT) |                          \
               (1 << CAUSE_MISALIGNED_FETCH) |                          \
               (1 << CAUSE_USER_ECALL) |                                \
               (1 << CAUSE_BREAKPOINT);                                 \
        csrw medeleg, t0;                                               \
1:      csrwi mstatus, 0;                                               \
        init;                                                           \
        EXTRA_INIT;                                                     \
        EXTRA_INIT_TIMER;                                               \
        la t0, 1f;                                                      \
        csrw mepc, t0;                                                  \
        csrr a0, mhartid;                                               \
        mret;                                                           \
1:

#define RVTEST_CODE_END                                                 \
        unimp

//-----------------------------------------------------------------------
// Pass/Fail macros
//-----------------------------------------------------------------------
#define RVTEST_PASS                                                     \
        fence;                                                          \
        li TESTNUM, 1;                                                  \
        li a7, 93;                                                      \
        li a0, 0;                                                       \
        ecall

#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz TESTNUM, 1b;                                               \
        sll TESTNUM, TESTNUM, 1;                                        \
        or TESTNUM, TESTNUM, 1;                                         \
        li a7, 93;                                                      \
        addi a0, TESTNUM, 0;                                            \
        ecall

//-----------------------------------------------------------------------
// Data section
//-----------------------------------------------------------------------
#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
