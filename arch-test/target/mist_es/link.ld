OUTPUT_ARCH( "riscv" )
ENTRY(_start)

/* Harvard split: code in IMEM at 0x0, data (signature, tohost) in DRAM. */
SECTIONS
{
  . = 0x00000000;
  .text.trap : { *(.text.trap) }

  . = 0x00000080;
  .text.init : { *(.text.init) }

  . = ALIGN(0x1000);
  .text : { *(.text) }
  .rodata : { *(.rodata*) }

  . = 0x80000000;
  .data : { *(.data) }
  .data.string : { *(.data.string) }
  .tohost : { *(.tohost) }
  .bss : { *(.bss) }
  _end = .;
}
