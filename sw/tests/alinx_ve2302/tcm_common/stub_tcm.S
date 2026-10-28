// stub_tcm.S - boot-BRAM reset-vector stub for the TCM benchmark path.
// The PS devmem-loads a TCM-linked image into boot BRAM (0xFFFF0000), then writes THIS
// stub at the reset vector (0xFFFFFF00). On reset release the SCR1 runs it FROM boot BRAM:
// it copies the image boot-BRAM -> internal TCM (single-cycle), then jumps to _start@0xF0000200.
// Copies 8192 words (32 KiB) - covers any CoreMark PROGBITS; .bss is cleared by crt in TCM.
.section .text
.globl _stub
_stub:
    lui  t0, 0xFFFF0        // src = 0xFFFF0000 (boot BRAM, image base)
    lui  t1, 0xF0000        // dst = 0xF0000000 (TCM base)
    li   t2, 8192           // words to copy (32 KiB)
1:
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -1
    bnez t2, 1b
    lui  t0, 0xF0000
    jalr x0, 0x200(t0)      // jump to _start @ 0xF0000200 (runs from TCM)
