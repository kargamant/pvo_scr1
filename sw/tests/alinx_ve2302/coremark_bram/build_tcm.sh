#!/usr/bin/env bash
# build_tcm.sh - CoreMark linked to run from internal single-cycle TCM (0xF0000000).
# The image is staged in boot BRAM; scr1load_tcm.sh installs a copy stub that moves it
# to TCM and jumps to _start. Output remains in the boot-BRAM mailbox @0xFFFFE000.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# Generic test sources are kept in this repository under sw/tests.
TESTS_ROOT=$(cd "$here/../.." && pwd)
H=$TESTS_ROOT/tests_common
SRC=$TESTS_ROOT/coremark/src
PORT=$TESTS_ROOT/coremark
LD=$here/../tcm_common/tcm.ld
CC=riscv64-unknown-elf-gcc; M=rv32im_zicsr_zifencei; ITER="${ITERATIONS:-4000}"
cd "$here"
INC="-I$here -I$SRC -I$H -I$PORT"
CF="-static --specs=picolibc.specs -Wa,-march=$M -march=$M -mabi=ilp32 -std=gnu99 \
 -mstrict-align -msmall-data-limit=8 -ffunction-sections -fdata-sections -fno-common \
 -fno-builtin-printf -fno-pic -fno-pie -O2 -DITERATIONS=$ITER -DTOTAL_DATA_SIZE=2000 \
 -DPERFORMANCE_RUN=1 -DRTC_HZ=80000000 -DSYS_CLK=80000000 -DFLAGS_STR='\"scr1-tcm\"' -DMEM_LOCATION='\"TCM\"'"
OPTS="-static --specs=picolibc.specs -no-pie -march=$M -mabi=ilp32 -nostartfiles -nostdlib -Wl,--gc-sections"
eval $CC $CF -D__ASSEMBLY__=1 $INC -c $H/crt-noreloc.S -o crt.o
eval $CC $CF $INC -c core_portme.c   -o core_portme.o
eval $CC $CF $INC -c mbox_syscalls.c -o mbox_syscalls.o
eval $CC $CF $INC -c $H/sc_print.c   -o sc_print.o
for f in core_list_join core_matrix core_main core_util core_state; do eval $CC $CF $INC -c $SRC/$f.c -o $f.o; done
$CC $OPTS crt.o core_portme.o mbox_syscalls.o sc_print.o \
    core_list_join.o core_matrix.o core_main.o core_state.o core_util.o \
    -T "$LD" -Wl,-Map=coremark_tcm.map -Wl,--start-group -lc -lgcc -Wl,--end-group \
    -o coremark_tcm.elf
riscv64-unknown-elf-size coremark_tcm.elf
riscv64-unknown-elf-objcopy -O binary coremark_tcm.elf coremark_tcm.bin
echo "coremark_tcm.bin: $(wc -c < coremark_tcm.bin) B -> load at PS 0x70000000 (dd, fast)"
echo "run from repository root: python3 fpga/alinx_ve2302/scr1/tools/scr1run.py sw/tests/alinx_ve2302/coremark_bram/coremark_tcm.bin --tcm"
