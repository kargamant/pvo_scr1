#!/bin/sh
# scr1load_tcm.sh - ON-BOARD loader to benchmark from the SCR1 internal single-cycle TCM.
# The PS cannot reach the internal TCM (0xF0000000) directly, so: devmem-load a TCM-linked
# image into boot BRAM (0xFFFF0000 = PS 0x80100000), then install a COPY-STUB at the reset
# vector (0xFFFFFF00 = PS 0x8010FF00). On reset release the SCR1 runs the stub from boot BRAM,
# copies the image boot-BRAM -> TCM, and jumps to _start@0xF0000200 -> CoreMark runs from TCM.
#
# Image must be linked with tests/tcm_common/tcm.ld (ORIGIN 0xF0000000, entry 0xF0000200).
# Mailbox output stays in boot BRAM @0xFFFFE000 (mbox_syscalls.c) -> PS reads 0x8010E000.
#
# Usage: scr1load_tcm.sh <image.bin> [--run] [--mbox]
set -e
IMG="$1"; shift || true
: "${LOAD_PHYS:=0x80100000}"; : "${RSTGPIO:=0x80200000}"; : "${MBOX:=0x8010E000}"
: "${STUB_PHYS:=0x8010FF00}"   # boot-BRAM reset vector (SCR1 0xFFFFFF00)
# COPY-STUB machine words (tests/tcm_common/stub_tcm.S): copy 8192 words BRAM->TCM, jump 0xF0000200
STUB="0xFFFF02B7 0xF0000337 0x000023B7 0x0002AE03 0x01C32023 0x00428293 0x00430313 0xFFF38393 0xFE0396E3 0xF00002B7 0x20028067"
[ -f "$IMG" ] || { echo "usage: scr1load_tcm.sh <image.bin> [--run] [--mbox]"; exit 1; }

echo "[tcm] hold SCR1 in reset"; devmem "$RSTGPIO" 32 0
echo "[tcm] loading $(wc -c < "$IMG") bytes -> boot BRAM $LOAD_PHYS (devmem word loop)..."
od -An -tx4 -v "$IMG" | tr -s ' ' '\n' | grep . > /tmp/_scr1tw.txt
a=$(printf '%d' "$LOAD_PHYS")
while read w; do devmem $a 32 0x$w; a=$((a+4)); done < /tmp/_scr1tw.txt
echo "[tcm] loaded $(wc -l < /tmp/_scr1tw.txt) words"

case " $* " in *" --run "*)
  echo "[tcm] install copy-stub @ $STUB_PHYS (BRAM->TCM, jump 0xF0000200)"
  a=$(printf '%d' "$STUB_PHYS")
  for w in $STUB; do devmem $a 32 "$w"; a=$((a+4)); done
  devmem $(($(printf '%d' "$MBOX")+0)) 32 0; devmem $(($(printf '%d' "$MBOX")+4)) 32 0
  echo "[tcm] release SCR1 (stub copies to TCM, then runs from TCM)"; devmem "$RSTGPIO" 32 1 ;;
esac

case " $* " in *" --mbox "*)
  echo "[tcm] waiting for mailbox done..."
  i=0; while [ $i -lt 400 ]; do
    d=$(devmem $(($(printf '%d' "$MBOX")+4))); [ "$d" = "0xD09ED09E" ] && break; sleep 2; i=$((i+2))
  done
  len=$(printf '%d' "$(devmem $(($(printf '%d' "$MBOX")+0)))")
  echo "[tcm] done=$d len=$len:"; echo "-----------------------------------"
  o=0; base=$(($(printf '%d' "$MBOX")+8))
  while [ $o -lt $len ]; do
    w=$(devmem $((base+o))); w=${w#0x}
    printf "$(echo $w | sed 's/\(..\)\(..\)\(..\)\(..\)/\\x\4\\x\3\\x\2\\x\1/')"; o=$((o+4))
  done; echo ""; echo "-----------------------------------" ;;
esac
echo "[tcm] done"
