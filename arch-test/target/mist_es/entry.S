.section .text.trap, "ax", @progbits
.align 4
.globl _start
_start:
    /* Reset vector at 0x0000_0000 jumps to entry point */
    j rvtest_entry_point
