.section .resetvec,"ax",@progbits
.globl _resetvec
_resetvec:
    j _start
