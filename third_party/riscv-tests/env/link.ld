/* link.ld -- riscv-tests on the MIST-ES SoC (Harvard memory map):
   code at 0x0000_0000 (IMEM, loaded from the .imem.hex image),
   data at 0x8000_0000 (DRAM, loaded from the .dram.hex image),
   tohost is the SoC exit register at 0x2000_0000. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
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
