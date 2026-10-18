// epmp_test.S — directed test of ePMP (Smepmp) mseccfg.MMWP on MIST-ES SECURE.
// MMWP = "M-mode whitelist": with it set, an M-mode access that matches NO PMP
// region is DENIED (default-deny), instead of the normal M-mode allow. The test
// whitelists the code region (X|R) and the tohost word (R|W), enables MMWP, then
// an M-mode store to an unmapped address faults (cause 7). tohost=1 on PASS.
    .section .text.init, "ax"
    .globl _start
_start:
    li   sp, 0x80007000
    la   t0, mtrap
    csrw mtvec, t0
    li   gp, 0

    // region0: NAPOT [0, 64KB) X|R  -> code stays fetchable under MMWP
    li   t0, 0x00001FFF
    csrw pmpaddr0, t0
    // region1: NA4 @ 0x2000_0000 (tohost) R|W -> M can still signal under MMWP
    li   t0, 0x08000000
    csrw pmpaddr1, t0
    // pmpcfg0 = {cfg1=0x13 (NA4|R|W), cfg0=0x1D (NAPOT|X|R)}
    li   t0, 0x0000131D
    csrw pmpcfg0, t0

    // enable ePMP M-mode whitelist policy: mseccfg.MMWP (bit1), CSR 0x747
    li   t0, 0x00000002
    csrw 0x747, t0

    // M-mode store to an UNMAPPED address -> now DENIED by MMWP (cause 7)
    li   t2, 0x80005000
    li   t3, 0x00000BAD
    sw   t3, 0(t2)                   // EXPECT TRAP
    j    finish

    .align 2
mtrap:
    csrr t4, mcause
    li   t5, 7                       // store access fault
    bne  t4, t5, bad
    li   gp, 0x000000E7             // mark: MMWP denied the M store
    csrr t4, mepc
    addi t4, t4, 4
    csrw mepc, t4
    mret
bad:
    li   t6, 0x20000000
    sw   t4, 0(t6)                  // report raw cause
1:  j    1b
finish:
    li   t6, 0x20000000            // tohost (region1 -> allowed under MMWP)
    li   t5, 0x000000E7
    bne  gp, t5, ffail
    li   t0, 1
    sw   t0, 0(t6)                 // PASS
2:  j    2b
ffail:
    li   t0, 2
    sw   t0, 0(t6)
3:  j    3b
