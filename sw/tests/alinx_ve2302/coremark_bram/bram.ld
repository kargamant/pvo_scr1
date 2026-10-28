OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY {
  BRAM (rwx) : ORIGIN = 0xFFFF0000, LENGTH = 64K
}

STACK_SIZE = 4096;

SECTIONS {

  .text.crt ORIGIN(BRAM) : {
    FILL(0);
    . = 0x100;
    *(.text.crt*)
  } >BRAM

  . = ALIGN(4);

  .text : {
    PROVIDE(__TEXT_START__ = .);
    *(.text .text.*)
    PROVIDE(__TEXT_END__ = .);
  } >BRAM

  .rodata : {
    _gp = . + 0x800;
    *(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2) *(.srodata*)
    *(.rodata .rodata.*)
  } >BRAM

  .data : {
    PROVIDE(__DATA_START__ = .);
    *(.data .data.*)
  } >BRAM

  .sdata : {
    *(.sdata .sdata.* .gnu.linkonce.s.*)
    . = ALIGN(4);
    PROVIDE(__DATA_END__ = .);
  } >BRAM

  .tdata : {
    PROVIDE(_tls_data = .);
    PROVIDE(_tdata_begin = .);
    *(.tdata .tdata.*)
    . = ALIGN(4);
    PROVIDE(_tdata_end = .);
  } >BRAM

  .tbss : {
    PROVIDE(_tbss_begin = .);
    *(.tbss .tbss.*)
    . = ALIGN(4);
    PROVIDE(_tbss_end = .);
  } >BRAM

  .sbss : {
    PROVIDE(__BSS_START__ = .);
    *(.sbss .sbss.* .gnu.linkonce.sb.*)
    *(.scommon)
  } >BRAM

  .bss : {
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    PROVIDE(__BSS_END__ = .);
  } >BRAM

  _end = .;
  PROVIDE(__end = .);
  PROVIDE(__heap_start = .);

  .stack ORIGIN(BRAM) + 0xC800 : {
    PROVIDE(__STACK_START__ = .);
    . += STACK_SIZE;
    PROVIDE(__C_STACK_TOP__ = .);
    PROVIDE(__STACK_END__ = .);
  } >BRAM

  .resetvec ORIGIN(BRAM) + 0xFF00 : {
    KEEP(*(.resetvec))
  } >BRAM

  /DISCARD/ : {
    *(.eh_frame .eh_frame.*)
  }
}
