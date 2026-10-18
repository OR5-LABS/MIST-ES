// pmp_test.S — directed, self-checking test of MIST-ES's PMP + M/U privilege.
// Proves memory isolation: an M-mode monitor grants User mode R/W to one DRAM
// region and X|R to the code region, then runs U-mode code that (1) legally
// reads+writes the granted region and (2) is DENIED a store outside any region
// (→ store access-fault, cause 7). The trap handler confirms the fault, and the
// monitor finally checks the legal write landed. Writes 1 to tohost (0x2000_0000)
// on PASS, 2 on FAIL, or the raw mcause on an unexpected trap.
    .section .text.init, "ax"
    .globl _start
_start:
    li   sp, 0x80007000
    la   t0, mtrap
    csrw mtvec, t0
    li   gp, 0                       // fault marker

    // PMP region0: NAPOT [0, 64KB) with X|R   -> U may fetch/read code
    li   t0, 0x00001FFF
    csrw pmpaddr0, t0
    // PMP region1: NAPOT [0x8000_0000, 4KB) with R|W -> U data window
    li   t0, 0x200001FF
    csrw pmpaddr1, t0
    // pmpcfg0 = {cfg1=0x1B (NAPOT|R|W), cfg0=0x1D (NAPOT|X|R)}
    li   t0, 0x00001B1D
    csrw pmpcfg0, t0

    // seed the granted window with a known value (from M-mode)
    li   t0, 0x80000000
    li   t1, 0x00001234
    sw   t1, 0(t0)

    // drop to U-mode at u_entry (mstatus.MPP = 00)
    li   t0, 0x00001800             // MPP field
    csrc mstatus, t0
    la   t0, u_entry
    csrw mepc, t0
    mret

u_entry:
    // (1) legal read of the granted window, then legal write to +4
    li   t0, 0x80000000
    lw   t1, 0(t0)                   // R  (region1)
    sw   t1, 4(t0)                   // W  (region1)  -> 0x80000004 = 0x1234
    // (2) illegal store outside any PMP region -> U denied (store access fault)
    li   t2, 0x80002000
    li   t3, 0x0BAD
    sw   t3, 0(t2)                   // EXPECT TRAP (cause 7)
    ecall                           // U-ecall (cause 8) -> monitor finishes
1:  j    1b

    .align 2
mtrap:
    csrr t4, mcause
    li   t5, 7
    beq  t4, t5, store_fault
    li   t5, 8
    beq  t4, t5, u_done
    // unexpected -> report raw cause
    li   t6, 0x20000000
    sw   t4, 0(t6)
2:  j    2b
store_fault:
    li   gp, 0x000000F7             // mark: PMP denied the U store
    csrr t4, mepc
    addi t4, t4, 4                  // skip the faulting sw
    csrw mepc, t4
    mret
u_done:
    li   t6, 0x20000000
    // require both: fault was taken AND the legal U write landed
    li   t5, 0x000000F7
    bne  gp, t5, fail
    li   t0, 0x80000004
    lw   t1, 0(t0)
    li   t2, 0x00001234
    bne  t1, t2, fail
    li   t0, 1
    sw   t0, 0(t6)                  // tohost = 1  PASS
3:  j    3b
fail:
    li   t0, 2
    sw   t0, 0(t6)                  // tohost = 2  FAIL
4:  j    4b
