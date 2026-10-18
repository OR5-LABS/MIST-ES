/* ============================================================================
 * crt0_fpga.S — Bare-metal startup for FPGA Hardware-in-the-Loop benchmarks.
 *
 * Differences from bench/common/crt0.S:
 *   - No IMEM/DRAM split: VMA == LMA, so NO .data copy is needed.
 *   - Stack pointer set to _stack_top (top of 16 KB unified RAM).
 *   - .bss zeroing is still required.
 *   - On exit: print "\nEXIT:<code>\r\n" over UART, blink LEDs, then spin.
 *     This allows the host Python script to detect completion even if tohost
 *     is not connected.
 *
 * Memory layout (fpga_bench.ld):
 *   RAM  0x00000000 – 0x00003FFF  unified code + data + stack
 *
 * UART address: 0x10000000
 *   Write byte → TX register (byte goes out at 115200 baud)
 *   Read  word → status (bit0 = tx_busy)
 * ============================================================================ */

/* ---- MMIO addresses ------------------------------------------------------- */
#define UART_BASE    0x10000000
#define LED_REG      0x20001000
#define TOHOST_ADDR  0x20000000

    .section .text.init, "ax", @progbits
    .globl  _start
    .type   _start, @function
_start:
    /* ---- set trap handler ------------------------------------------------- */
    la      t0, _trap_handler
    csrw    mtvec, t0

    /* ---- set stack pointer ------------------------------------------------ */
    la      sp, _stack_top

    /* ---- zero .bss -------------------------------------------------------- */
    la      a0, _bss_start
    la      a1, _bss_end
    beq     a0, a1, .Lwait_trigger
.Lbss_loop:
    sw      zero, 0(a0)
    addi    a0, a0, 4
    blt     a0, a1, .Lbss_loop

    /* ---- wait for UART RX trigger ----------------------------------------
     * The benchmark completes in ~170ms at 100 MHz — faster than the host
     * script can open the serial port.  Print a ready banner, then block on
     * RX until the host sends any character (run_hil_bench.py sends '\r').
     * UART register map (mist_es_uart.sv):
     *   0x10000000 R : status — bit0=tx_busy, bit1=rx_ready
     *   0x10000004 R : rx data byte (reading clears rx_ready)
     * -------------------------------------------------------------------- */
.Lwait_trigger:
    li      s1, UART_BASE           /* s1 = UART base (used by _fpga_puts) */
    la      a0, _ready_msg          /* print "READY\r\n" */
    call    _fpga_puts

.Lwait_rx:
    lw      t0, 0(s1)               /* read UART status */
    andi    t0, t0, 2               /* bit1 = rx_ready */
    beqz    t0, .Lwait_rx           /* loop until a byte arrives */
    lw      t0, 4(s1)               /* consume the RX byte (clears rx_ready) */

    /* ---- call main -------------------------------------------------------- */
.Lcall_main:
    li      a0, 0               /* argc = 0 */
    li      a1, 0               /* argv = NULL */
    call    main

    /* ---- _exit ------------------------------------------------------------ */
    /* a0 holds the return code from main(). */
    .globl  _exit
_exit:
    /* Write tohost for any attached simulation harness */
    li      t0, TOHOST_ADDR
    sw      a0, 0(t0)

    /* Print "\nEXIT:<decimal_code>\r\n" over UART so the host script can parse it */
    mv      s0, a0              /* save exit code */
    li      s1, UART_BASE

    la      a0, _exit_prefix    /* "\nEXIT:" */
    call    _fpga_puts

    mv      a0, s0              /* code */
    call    _fpga_print_dec

    la      a0, _exit_suffix    /* "\r\n" */
    call    _fpga_puts

    /* Blink LEDs with exit code */
    li      t0, LED_REG
    sw      s0, 0(t0)

.Lspin:
    j       .Lspin

/* ---- _trap_handler ------------------------------------------------------- */
    .globl  _trap_handler
    .align  2
_trap_handler:
    li      a0, 2
    j       _exit

/* ---- _fpga_puts(a0 = char*) - poll-TX UART output ------------------------ */
    .globl  _fpga_puts
_fpga_puts:
    mv      t1, a0
.Lputs_loop:
    lbu     t2, 0(t1)
    beqz    t2, .Lputs_done
.Lputs_wait:
    lw      t3, 0(s1)           /* read UART status */
    andi    t3, t3, 1           /* bit0 = tx_busy */
    bnez    t3, .Lputs_wait
    sw      t2, 0(s1)           /* write TX byte */
    addi    t1, t1, 1
    j       .Lputs_loop
.Lputs_done:
    ret

/* ---- _fpga_putchar(a0 = char) - single char UART TX ---------------------- */
    .globl  _fpga_putchar
_fpga_putchar:
.Lputchar_wait:
    lw      t0, 0(s1)
    andi    t0, t0, 1
    bnez    t0, .Lputchar_wait
    sw      a0, 0(s1)
    ret

/* ---- _fpga_print_dec(a0 = uint32) - print decimal number ------------------ */
    .globl  _fpga_print_dec
_fpga_print_dec:
    /* Stack frame: save ra, s2, s3 */
    addi    sp, sp, -16
    sw      ra,  12(sp)
    sw      s2,   8(sp)
    sw      s3,   4(sp)

    mv      s2, a0              /* number to convert */
    li      s3, 0               /* digit count */

    /* Special case: zero */
    bnez    s2, .Ldec_nonzero
    li      a0, '0'
    call    _fpga_putchar
    j       .Ldec_done

.Ldec_nonzero:
    /* Push digits onto stack (will be 10 digits max for 32-bit) */
    addi    sp, sp, -40         /* up to 10 digits × 4 bytes */
    mv      t4, sp              /* base of digit buffer */

.Ldec_extract:
    beqz    s2, .Ldec_print
    li      t0, 10
    /* Use RV32M divu/remu — single-cycle, avoids iterative loop for large numbers */
    remu    t1, s2, t0          /* t1 = s2 % 10 (remainder = digit) */
    divu    s2, s2, t0          /* s2 = s2 / 10 (quotient, next iteration) */
    addi    t1, t1, '0'         /* ASCII digit */
    sw      t1, 0(sp)
    addi    sp, sp, 4
    addi    s3, s3, 1
    j       .Ldec_extract

.Ldec_print:
    /* Print digits in reverse (stack is LIFO) */
    beqz    s3, .Ldec_buf_done
    addi    sp, sp, -4
    lw      a0, 0(sp)
    addi    s3, s3, -1
    call    _fpga_putchar
    j       .Ldec_print

.Ldec_buf_done:
    mv      sp, t4              /* restore digit buffer base */
    addi    sp, sp, 40          /* release digit buffer */

.Ldec_done:
    lw      ra,  12(sp)
    lw      s2,   8(sp)
    lw      s3,   4(sp)
    addi    sp, sp, 16
    ret

/* ---- String constants ----------------------------------------------------- */
    .section .rodata
_ready_msg:
    .asciz "READY\r\n"
_exit_prefix:
    .asciz "\nEXIT:"
_exit_suffix:
    .asciz "\r\n"
