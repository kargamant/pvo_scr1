/* tcm.ld - link a bare-metal SCR1 program to run from the internal single-cycle TCM.
 * SCR1 DDR window is identity-mapped to physical DDR (create_sopc_ps.tcl); Linux is
 * booted with mem=1792M so 0x70000000..0x80000000 (256MB) is free for SCR1.
 * Entry _start @ 0x70000000 (the boot-BRAM stub jumps here: lui t0,0x70000; jr t0).
 * Mailbox output stays in boot BRAM @0xFFFFE000 (mbox_syscalls.c) -> PS-visible/coherent
 * (SCR1 dcache is write-back for DDR, so DON'T put the mailbox in DDR).
 */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY {
  TCM (rwx) : ORIGIN = 0xF0000000, LENGTH = 64K
}

STACK_SIZE = 16384;

SECTIONS {

  .text.crt ORIGIN(TCM) : {
    FILL(0);
    . = 0x100;
    *(.text.crt*)
  } >TCM

  . = ALIGN(4);

  .text : {
    PROVIDE(__TEXT_START__ = .);
    *(.text .text.*)
    PROVIDE(__TEXT_END__ = .);
  } >TCM

  .rodata : {
    _gp = . + 0x800;
    *(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2) *(.srodata*)
    *(.rodata .rodata.*)
  } >TCM

  .data : {
    PROVIDE(__DATA_START__ = .);
    *(.data .data.*)
  } >TCM

  .sdata : {
    *(.sdata .sdata.* .gnu.linkonce.s.*)
    . = ALIGN(4);
    PROVIDE(__DATA_END__ = .);
  } >TCM

  .tdata : {
    PROVIDE(_tls_data = .);
    PROVIDE(_tdata_begin = .);
    *(.tdata .tdata.*)
    . = ALIGN(4);
    PROVIDE(_tdata_end = .);
  } >TCM

  .tbss : {
    PROVIDE(_tbss_begin = .);
    *(.tbss .tbss.*)
    . = ALIGN(4);
    PROVIDE(_tbss_end = .);
  } >TCM

  .sbss : {
    PROVIDE(__BSS_START__ = .);
    *(.sbss .sbss.* .gnu.linkonce.sb.*)
    *(.scommon)
  } >TCM

  .bss : {
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    PROVIDE(__BSS_END__ = .);
  } >TCM

  _end = .;
  PROVIDE(__end = .);
  PROVIDE(__heap_start = .);

  .stack ORIGIN(TCM) + LENGTH(TCM) - STACK_SIZE : {
    PROVIDE(__STACK_START__ = .);
    . += STACK_SIZE;
    PROVIDE(__C_STACK_TOP__ = .);
    PROVIDE(__STACK_END__ = .);
  } >TCM

  /DISCARD/ : {
    *(.eh_frame .eh_frame.*)
  }
}
