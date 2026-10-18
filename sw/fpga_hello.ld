/* fpga_hello.ld — single unified RAM at 0x0 (matches mist_es_fpga).
   .text + .rodata + .data all live in the low RAM; stack grows down from the
   top (set in _start). No DRAM region — the FPGA demo SoC has one RAM. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS {
  .text : {
    KEEP(*(.text.init))
    *(.text*)
    *(.rodata*)
    *(.srodata*)
    . = ALIGN(4);
  } > RAM

  .data : {
    *(.data*)
    *(.sdata*)
    . = ALIGN(4);
  } > RAM

  .bss (NOLOAD) : {
    *(.sbss*)
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
  } > RAM

  _end = .;
}
