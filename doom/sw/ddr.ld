/*
 * SCR1 bare-metal linker script for Nexys4DDR DDR2
 *
 * DDR2:
 *   base: 0x00000000
 *   size: 128 MiB
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    DDR (rwx) : ORIGIN = 0x00000000, LENGTH = 128M
}

STACK_SIZE = 16K;

SECTIONS
{

    .text.crt ORIGIN(DDR) :
    {
        FILL(0);
        . = 0x100;
        KEEP(*(.text.crt*))
    } > DDR

    . = ALIGN(4);

    .text :
    {
        PROVIDE(__TEXT_START__ = .);

        *(.text)
        *(.text.*)

        PROVIDE(__TEXT_END__ = .);
    } > DDR

    .rodata :
    {
        . = ALIGN(4);

        _gp = . + 0x800;
        PROVIDE(__global_pointer$ = . + 0x800);

        *(.srodata.cst16)
        *(.srodata.cst8)
        *(.srodata.cst4)
        *(.srodata.cst2)
        *(.srodata)
        *(.srodata.*)

        *(.rodata)
        *(.rodata.*)
    } > DDR

    .data :
    {
        . = ALIGN(4);

        PROVIDE(__DATA_START__ = .);

        *(.data)
        *(.data.*)
    } > DDR

    .sdata :
    {
        *(.sdata)
        *(.sdata.*)
        *(.gnu.linkonce.s.*)

        . = ALIGN(4);
        PROVIDE(__DATA_END__ = .);
    } > DDR

    .tdata :
    {
        PROVIDE(_tls_data = .);
        PROVIDE(_tdata_begin = .);

        *(.tdata)
        *(.tdata.*)

        . = ALIGN(4);
        PROVIDE(_tdata_end = .);
    } > DDR

    .tbss (NOLOAD) :
    {
        PROVIDE(_tbss_begin = .);

        *(.tbss)
        *(.tbss.*)

        . = ALIGN(4);
        PROVIDE(_tbss_end = .);
    } > DDR

    .sbss (NOLOAD) :
    {
        PROVIDE(__BSS_START__ = .);

        *(.sbss)
        *(.sbss.*)
        *(.gnu.linkonce.sb.*)
        *(.scommon)
    } > DDR

    .bss (NOLOAD) :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)

        . = ALIGN(4);
        PROVIDE(__BSS_END__ = .);
    } > DDR

    . = ALIGN(16);

    _end = .;
    PROVIDE(end = _end);
    PROVIDE(__end = _end);
    PROVIDE(__heap_start = _end);
    .stack ORIGIN(DDR) + LENGTH(DDR) - STACK_SIZE (NOLOAD) :
    {
        PROVIDE(__STACK_START__ = .);

        . += STACK_SIZE;

        PROVIDE(__C_STACK_TOP__ = .);
        PROVIDE(__STACK_END__ = .);
    } > DDR

    ASSERT(
        _end <= __STACK_START__,
        "DDR image overlaps the stack"
    )

    /DISCARD/ :
    {
        *(.eh_frame)
        *(.eh_frame.*)
        *(.comment)
    }
}