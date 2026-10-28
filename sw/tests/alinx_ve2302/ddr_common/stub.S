.section .text
.globl _stub
_stub:
    lui  t0, 0x70000      # t0 = 0x70000000
    jr   t0               # jump to DDR entry
