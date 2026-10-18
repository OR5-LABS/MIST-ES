// upriv_test.S — User mode must not touch Machine-level CSRs or execute MRET.
// Runs on MIST-ES SECURE. PMP region0 gives U full RWX so only the privilege
// checks under test can fault. In U-mode the program attempts:
//   1. csrr  mstatus       -> illegal instruction (cause 2)
//   2. csrw  mscratch      -> illegal instruction, mscratch must be unchanged
//   3. mret                -> illegal instruction
// then ECALLs back to M-mode (cause 8). tohost=1 only if all three trapped
// with cause 2, mtval held the faulting instruction, and mscratch kept its
// sentinel. tohost=2+ encodes which check failed.
    .section .text.init, "ax"
    .globl _start
_start:
    la   t0, mtrap
    csrw mtvec, t0
    li   gp, 0                        // count of illegal-instruction traps
    li   t0, 0x5EC0DE00
    csrw mscratch, t0                 // sentinel U-mode must not overwrite

    // region0: NAPOT over the whole 34-bit space, U may R/W/X everything
    li   t0, 0xFFFFFFFF
    csrw pmpaddr0, t0
    li   t0, 0x1F                     // NAPOT | X | W | R, L=0
    csrw pmpcfg0, t0

    // drop to U-mode at user_code: mstatus.MPP = 00, mepc = user_code
    li   t0, 0x1800
    csrc mstatus, t0
    la   t0, user_code
    csrw mepc, t0
    mret

    .align 2
user_code:
    csrr t1, mstatus                  // EXPECT illegal
    li   t2, 0x0BADBAD0
    csrw mscratch, t2                 // EXPECT illegal, no write
    mret                              // EXPECT illegal
    ecall                             // back to M-mode

    .align 2
mtrap:
    csrr t3, mcause
    li   t4, 8                        // ECALL from U: finish in M-mode
    beq  t3, t4, finish
    li   t4, 2                        // illegal instruction
    bne  t3, t4, bad_cause
    csrr t5, mtval                    // must be the faulting 32-bit instruction
    csrr t6, mepc
    lw   t4, 0(t6)
    bne  t4, t5, bad_tval
    addi gp, gp, 1
    addi t6, t6, 4
    csrw mepc, t6
    mret                              // MPP=U, so this returns to user_code

finish:
    li   t6, 0x20000000               // tohost
    li   t4, 3
    bne  gp, t4, fail_count
    csrr t4, mscratch
    li   t5, 0x5EC0DE00
    bne  t4, t5, fail_scratch
    li   t0, 1
    sw   t0, 0(t6)                    // PASS
1:  j    1b
fail_count:
    li   t0, 2
    sw   t0, 0(t6)
2:  j    2b
fail_scratch:
    li   t0, 3
    sw   t0, 0(t6)
3:  j    3b
bad_cause:
    li   t6, 0x20000000
    li   t0, 4
    sw   t0, 0(t6)
4:  j    4b
bad_tval:
    li   t6, 0x20000000
    li   t0, 5
    sw   t0, 0(t6)
5:  j    5b
