.section .text
.globl _stub
_stub:
    lui  t0, 0x70000        # t0 = 0x70000000
    jalr x0, 0x200(t0)      # jump to _start @ 0x70000200
