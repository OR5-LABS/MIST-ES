/* ============================================================================
 * fpga_bench.ld — Linker script for FPGA hardware-in-the-loop benchmarks.
 *
 * Memory map (matches mist_es_fpga.sv with MEM_WORDS=4096):
 *   RAM  0x00000000 – 0x00003FFF  (16 KB, unified code + data + stack)
 *
 * Peripherals (outside RAM, not linked):
 *   0x02000000  CLINT  (mtime, mtimecmp, msip)
 *   0x10000000  UART   (tx/rx, 115200 8-N-1)
 *   0x20000000  tohost (sim/bring-up handshake)
 *   0x20001000  LEDs
 *
 * Unlike bench.ld (which uses separate IMEM/DRAM), the FPGA SoC has a single
 * block-RAM serving both instruction and data ports.  .data is therefore
 * loaded-in-place (VMA == LMA) and there is no copy needed in crt0.
 * Stack grows down from the top of RAM, leaving 16 bytes for alignment safety.
 * ============================================================================ */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 128K
}

SECTIONS {

    /* ---- code + read-only data ------------------------------------------- */
    .text : {
        KEEP(*(.text.init))     /* crt0_fpga must be first */
        *(.text*)
        . = ALIGN(4);
    } > RAM

    .rodata : {
        *(.rodata*)
        *(.srodata*)
        . = ALIGN(4);
    } > RAM

    /* ---- initialised data (VMA == LMA in unified RAM) -------------------- */
    .data : {
        _data_start = .;
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        _data_end = .;
    } > RAM

    /* ---- zero-initialised data (NOLOAD) ----------------------------------- */
    .bss (NOLOAD) : {
        _bss_start = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > RAM

    /* ---- heap starts after BSS ------------------------------------------- */
    _end = _bss_end;

    /* ---- stack top: 16 bytes below the top of RAM ------------------------- */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM) - 16;

    /DISCARD/ : {
        *(.riscv.attributes)
        *(.comment)
        *(.eh_frame)
        *(.note*)
    }
}
