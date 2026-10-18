/* ============================================================================
 * crt0.S — Bare-metal startup for MIST-ES benchmark targets (RV32IMC).
 *
 * Memory layout (bench.ld):
 *   IMEM  0x00000000  code + rodata + .data LMA (load image)
 *   DRAM  0x80000000  .data VMA + .bss + stack
 *
 * Startup sequence:
 *   1. Set stack pointer to top of DRAM.
 *   2. Copy .data from LMA (IMEM) to VMA (DRAM).
 *   3. Zero .bss.
 *   4. Call main().
 *   5. Write return value to tohost and spin.
 * ============================================================================ */

    .section .text.init,"ax",@progbits
    .globl  _start
    .type   _start, @function
_start:
    /* ---- set trap handler ------------------------------------------------- */
    la      t0, _trap_handler
    csrw    mtvec, t0

    /* ---- set stack pointer ------------------------------------------------ */
    la      sp, _stack_top

    /* ---- copy .data from LMA → VMA --------------------------------------- */
    la      a0, _data_lma       /* source: LMA in IMEM after .rodata */
    la      a1, _data_start     /* destination: VMA in DRAM */
    la      a2, _data_end
    beq     a1, a2, .Lbss_zero  /* skip if .data is empty */
.Ldata_copy:
    lw      t0, 0(a0)
    sw      t0, 0(a1)
    addi    a0, a0, 4
    addi    a1, a1, 4
    blt     a1, a2, .Ldata_copy

    /* ---- zero .bss -------------------------------------------------------- */
.Lbss_zero:
    la      a0, _bss_start
    la      a1, _bss_end
    beq     a0, a1, .Lcall_main
.Lbss_loop:
    sw      zero, 0(a0)
    addi    a0, a0, 4
    blt     a0, a1, .Lbss_loop

    /* ---- call main -------------------------------------------------------- */
.Lcall_main:
    li      a0, 0               /* argc = 0 */
    li      a1, 0               /* argv = NULL */
    call    main

    /* ---- _exit: write return value to tohost ------------------------------ */
    .globl  _exit
_exit:
    bnez    a0, 1f
    li      a0, 1               /* exit(0) -> tohost = 1 (PASS) */
1:
    li      t0, 0x20000000      /* TOHOST_ADDR */
    sw      a0, 0(t0)
.Lspin:
    j       .Lspin

    /* ---- _trap_handler: exit with FAIL code 2 ----------------------------- */
    .globl  _trap_handler
    .align  2
_trap_handler:
    li      a0, 2
    j       _exit

    .size   _start, . - _start
