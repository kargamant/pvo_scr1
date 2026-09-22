#!/bin/sh
# scr1load_ddr.sh - ON-BOARD loader for LARGE SCR1 programs that run from RESERVED DDR.
# Requires the combined bitstream built with the 2GB SCR1 DDR window AND Linux booted with
# mem=1792M (so 0x70000000..0x80000000 is free). Unlike the boot-BRAM path, DDR is RAM so
# `dd` to /dev/mem WORKS -> fast bulk load (no devmem word-loop).
#
# Program must be linked with tests/ddr_common/ddr70.ld (entry _start @ 0x70000000, mailbox
# output in boot BRAM @0xFFFFE000 -> PS reads 0x8010E000).
#
# Usage: scr1load_ddr.sh <image.bin> [--run] [--mbox]
set -e
IMG="$1"; shift || true
: "${DDR_PHYS:=0x70000000}"; : "${RSTGPIO:=0x80200000}"; : "${MBOX:=0x8010E000}"
# boot-BRAM reset stub: lui t0,0x70000 ; jr 0x200(t0) -> jumps to _start @0x70000200
# (_start is ORIGIN+0x200 for ddr70.ld+crt-noreloc.S; regenerate with tests/ddr_common/stub70.S
#  if crt changes: riscv64-unknown-elf-objdump -d coremark_ddr.elf | grep _start)
: "${STUB0:=0x700002B7}"; : "${STUB1:=0x20028067}"; : "${STUB_PHYS:=0x8010FF00}"
[ -f "$IMG" ] || { echo "usage: scr1load_ddr.sh <image.bin> [--run] [--mbox]"; exit 1; }

echo "[ddr] hold SCR1 in reset"; devmem "$RSTGPIO" 32 0
# NOTE: dd/write() to /dev/mem EFAULTs ("Bad address") on the mem=1792M-reserved DDR window
# (kernel has no linear map for it). Only mmap works -> load word-by-word via busybox devmem,
# same mechanism as the boot-BRAM path. Slower than bulk dd but the only path that lands.
echo "[ddr] loading $(wc -c < "$IMG") bytes -> $DDR_PHYS (devmem mmap word loop)..."
od -An -tx4 -v "$IMG" | tr -s ' ' '\n' | grep . > /tmp/_scr1dw.txt
a=$(printf '%d' "$DDR_PHYS")
while read w; do devmem $a 32 0x$w; a=$((a+4)); done < /tmp/_scr1dw.txt
echo "[ddr] loaded $(wc -l < /tmp/_scr1dw.txt) words"; sync

case " $* " in *" --run "*)
  echo "[ddr] write boot-BRAM stub -> jump 0x70000000"
  devmem "$STUB_PHYS" 32 "$STUB0"; devmem $(($(printf '%d' "$STUB_PHYS")+4)) 32 "$STUB1"
  devmem $(($(printf '%d' "$MBOX")+0)) 32 0; devmem $(($(printf '%d' "$MBOX")+4)) 32 0
  echo "[ddr] release SCR1"; devmem "$RSTGPIO" 32 1 ;;
esac

case " $* " in *" --mbox "*)
  echo "[ddr] waiting for mailbox done..."
  i=0; while [ $i -lt 400 ]; do
    d=$(devmem $(($(printf '%d' "$MBOX")+4))); [ "$d" = "0xD09ED09E" ] && break; sleep 2; i=$((i+2))
  done
  len=$(printf '%d' "$(devmem $(($(printf '%d' "$MBOX")+0)))")
  echo "[ddr] done=$d len=$len:"; echo "-----------------------------------"
  o=0; base=$(($(printf '%d' "$MBOX")+8))
  while [ $o -lt $len ]; do
    w=$(devmem $((base+o))); w=${w#0x}
    printf "$(echo $w | sed 's/\(..\)\(..\)\(..\)\(..\)/\\x\4\\x\3\\x\2\\x\1/')"; o=$((o+4))
  done; echo ""; echo "-----------------------------------" ;;
esac
echo "[ddr] done"
