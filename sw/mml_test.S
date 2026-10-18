// mml_test.S — Smepmp Machine Mode Lockdown (mseccfg.MML) on MIST-ES SECURE.
// With MML set, L=1 rules are M-mode-only, L=0 rules are U-mode-only, M-mode may
// not execute from memory that matches no rule, new executable M-mode rules
// cannot be added, and RLB cannot be set while any rule is locked.
//   T1  M-mode load from an L=0 (U-only) RW region        -> load fault (cause 5)
//   T2  M-mode store to an address matching no rule        -> allowed (no MMWP)
//   T3  M-mode jump into an address matching no rule       -> fetch fault (cause 1)
//   T4  write an executable M-only rule (pmp4cfg = L|X|R)  -> write ignored
//   T5  set mseccfg.RLB while locked rules exist           -> stays 0
// gp collects one bit per passing check; tohost=1 when gp == 0x1F.
    .section .text.init, "ax"
    .globl _start
_start:
    la   t0, mtrap
    csrw mtvec, t0
    li   gp, 0

    // region0: NAPOT [0, 64 KB) code, L|X|R  (M-only execute under MML)
    li   t0, 0x00001FFF
    csrw pmpaddr0, t0
    // region1: NA4 @ 0x2000_0000 (tohost), L|W|R (M-only read/write)
    li   t0, 0x08000000
    csrw pmpaddr1, t0
    // region2: NA4 @ 0x8000_4000, L=0 W|R (U-only read/write under MML)
    li   t0, 0x20001000
    csrw pmpaddr2, t0
    // pmpcfg0 = {cfg3=0, cfg2=0x13, cfg1=0x93, cfg0=0x9D}
    li   t0, 0x0013939D
    csrw pmpcfg0, t0

    li   t0, 0x1                      // mseccfg.MML
    csrw 0x747, t0

    // T1: M-mode load from U-only region -> cause 5
    li   t2, 0x80004000
    lw   t1, 0(t2)                    // EXPECT load access fault

    // T2: M-mode store/load to an unmatched address -> allowed
    li   t2, 0x80006000
    li   t1, 0x12345678
    sw   t1, 0(t2)
    lw   t3, 0(t2)
    bne  t3, t1, t2_done
    ori  gp, gp, 0x2
t2_done:

    // T3: M-mode jump to an unmatched address -> instruction access fault
    la   s0, t3_back
    li   t2, 0x80006000
    jr   t2                           // EXPECT fetch fault
t3_back:

    // T4: new executable M-only rule must be ignored under MML (RLB=0)
    li   t0, 0x00000FFF
    csrw pmpaddr4, t0
    li   t0, 0x0000009D               // pmp4cfg = L | NAPOT | X | R
    csrw pmpcfg1, t0
    csrr t1, pmpcfg1
    bnez t1, t4_done
    ori  gp, gp, 0x8
t4_done:

    // T5: RLB cannot be set while any rule is locked
    li   t0, 0x4
    csrs 0x747, t0
    csrr t1, 0x747
    andi t1, t1, 0x4
    bnez t1, t5_done
    ori  gp, gp, 0x10
t5_done:
    j    finish

    .align 2
mtrap:
    csrr t4, mcause
    li   t5, 5
    beq  t4, t5, got_load
    li   t5, 1
    beq  t4, t5, got_fetch
    j    bad_cause
got_load:
    ori  gp, gp, 0x1
    csrr t4, mepc
    addi t4, t4, 4
    csrw mepc, t4
    mret
got_fetch:
    csrr t4, mtval
    li   t5, 0x80006000
    bne  t4, t5, bad_cause
    ori  gp, gp, 0x4
    csrw mepc, s0                     // resume after the jump
    mret

finish:
    li   t6, 0x20000000               // tohost (region1, M read/write)
    li   t5, 0x1F
    bne  gp, t5, fail
    li   t0, 1
    sw   t0, 0(t6)                    // PASS
1:  j    1b
fail:
    addi t0, gp, 0x100                // report which checks passed
    sw   t0, 0(t6)
2:  j    2b
bad_cause:
    li   t6, 0x20000000
    li   t0, 0x200
    sw   t0, 0(t6)
3:  j    3b
