OUTPUT_ARCH(riscv)
ENTRY(rvtest_entry_point)
tohost = 0x20000000;
SECTIONS {
  . = 0x00000000;
  .text.init : { *(.text.init) }
  .text      : { *(.text) *(.text.*) }
  . = 0x80000000;
  .data      : { *(.data) *(.data.*) *(.sdata) *(.sdata.*)
                 *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*) }
  .bss       : { *(.bss) *(.bss.*) *(.sbss) *(.sbss.*) *(COMMON) }
  _end = .;
}
