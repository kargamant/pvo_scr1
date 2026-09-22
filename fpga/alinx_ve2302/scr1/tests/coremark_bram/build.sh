#!/usr/bin/env bash
# build.sh - build CoreMark to run ENTIRELY from the SCR1 boot BRAM (0xFFFF0000, 64K),
# with output to a memory mailbox (0xFFFFE000) that the PS reads via devmem, and the
# timer on mcycle (the board top ties rtc_clk=0, so rdtime is dead).
# Produces coremark_bram.elf/.bin and a compact cm_code.bin (PROGBITS only) for loading.
#
# Load it from Linux on the board with the host driver:
#   tools/scr1run.py tests/coremark_bram/cm_code.bin
# (mailbox output is printed automatically).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# CoreMark sources live in the sibling scr1_sber checkout; override via SCR1_SBER if elsewhere
SBER="${SCR1_SBER:-$(cd "$here/../../../../../.." && pwd)/scr1_sber}"
H=$SBER/tests/tests_common
SRC=$SBER/tests/coremark/src
PORT=$SBER/tests/coremark          # core_portme.h / coremark.h search
CC=riscv64-unknown-elf-gcc
M=rv32im_zicsr_zifencei
ITER="${ITERATIONS:-2000}"
cd "$here"
INC="-I$here -I$SRC -I$H -I$PORT"
CF="-static --specs=picolibc.specs -Wa,-march=$M -march=$M -mabi=ilp32 -std=gnu99 \
 -mstrict-align -msmall-data-limit=8 -ffunction-sections -fdata-sections -fno-common \
 -fno-builtin-printf -fno-pic -fno-pie -O2 -DITERATIONS=$ITER -DTOTAL_DATA_SIZE=2000 \
 -DPERFORMANCE_RUN=1 -DRTC_HZ=80000000 -DSYS_CLK=80000000 -DFLAGS_STR='\"scr1-bram\"' -DMEM_LOCATION='\"BRAM\"'"
OPTS="-static --specs=picolibc.specs -no-pie -march=$M -mabi=ilp32 -nostartfiles -nostdlib -Wl,--gc-sections"

eval $CC $CF -D__ASSEMBLY__=1 $INC -c $H/crt-noreloc.S -o crt.o
eval $CC $CF -D__ASSEMBLY__=1 $INC -c resetvec.S       -o resetvec.o
eval $CC $CF $INC -c core_portme.c  -o core_portme.o
eval $CC $CF $INC -c mbox_syscalls.c -o mbox_syscalls.o
eval $CC $CF $INC -c $H/sc_print.c   -o sc_print.o
for f in core_list_join core_matrix core_main core_util core_state; do eval $CC $CF $INC -c $SRC/$f.c -o $f.o; done
$CC $OPTS crt.o resetvec.o core_portme.o mbox_syscalls.o sc_print.o \
    core_list_join.o core_matrix.o core_main.o core_state.o core_util.o \
    -T bram.ld -Wl,-Map=coremark_bram.map -Wl,--start-group -lc -lgcc -Wl,--end-group \
    -o coremark_bram.elf
riscv64-unknown-elf-size coremark_bram.elf
riscv64-unknown-elf-objcopy -O binary coremark_bram.elf coremark_bram.bin
# compact image = PROGBITS only (0xFFFF0000..__BSS_START__), padded to 4K; .bss cleared by crt
bstart=$(riscv64-unknown-elf-nm coremark_bram.elf | awk '/__BSS_START__/{print $1}')
bs=$(( 0x$bstart - 0xFFFF0000 ))
python3 - "$bs" <<'PY'
import sys
bs=int(sys.argv[1]); d=open('coremark_bram.bin','rb').read()[:bs]
d+=b'\x00'*((-len(d))%4096)
open('cm_code.bin','wb').write(d)
print("cm_code.bin:",len(d),"bytes (",len(d)//4096,"pages ) -> load at PS 0x80100000")
PY
echo "reset stub word = 0xB00F006F @ SCR1 0xFFFFFF00 (PS 0x8010FF00) — scr1load.sh writes it"
echo "DONE: coremark_bram.elf / cm_code.bin"
