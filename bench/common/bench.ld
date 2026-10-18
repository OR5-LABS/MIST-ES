/* ============================================================================
 * bench.ld — Unified linker script for MIST-ES benchmark targets.
 *
 * Memory map:
 *   IMEM  0x00000000 – 0x0000FFFF  (64 KB) — code + rodata + .data image
 *   DRAM  0x80000000 – 0x8000FFFF  (64 KB) — .data VMA + .bss + stack
 *
 * The .data section has its LMA (load address) in IMEM immediately after
 * .rodata.  crt0.S copies it word-by-word to its VMA in DRAM at startup.
 *
 * Stack grows down from the top of DRAM (_stack_top).
 * ============================================================================ */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS {

    /* ---- code + read-only data in IMEM ----------------------------------- */
    .text : {
        KEEP(*(.text.init))     /* crt0 must be first */
        *(.text*)
        . = ALIGN(4);
    } > IMEM

    .rodata : {
        *(.rodata*)
        *(.srodata*)
        . = ALIGN(4);
    } > IMEM

    /* ---- initialised data — stored in IMEM (LMA), run from DRAM (VMA) --- */
    _data_lma = LOADADDR(.data);

    .data : {
        _data_start = .;
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        _data_end = .;
    } > DRAM AT > IMEM

    /* ---- zero-initialised data in DRAM (NOLOAD) ------------------------- */
    .bss (NOLOAD) : {
        _bss_start = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DRAM

    /* ---- heap starts immediately after BSS ------------------------------ */
    _end = _bss_end;

    /* ---- stack top: 16 bytes below the top of DRAM ---------------------- */
    _stack_top = ORIGIN(DRAM) + LENGTH(DRAM) - 16;

    /* ---- discard unwanted sections -------------------------------------- */
    /DISCARD/ : {
        *(.riscv.attributes)
        *(.comment)
        *(.eh_frame)
        *(.note*)
    }
}
