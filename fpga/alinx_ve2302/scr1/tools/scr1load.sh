#!/bin/sh
# scr1load.sh - ON-BOARD (PetaLinux) loader: load a bare-metal image into the SCR1
# boot BRAM via /dev/mem and control the SCR1 reset, all from Linux on the PS.
#
# The combined VD100 bitstream exposes (M_AXI_LPD -> axi_smc):
#   boot BRAM (SCR1 0xFFFF0000, 64K)  <-> PS 0x80100000
#   scr1_reset_gpio (1 bit, 1=run)    <-> PS 0x80200000
# SCR1 resets to 0xFFFFFF00; a 1-word "reset stub" there jumps to _start.
#
# NOTE: /dev/mem write()/dd FAILS ("Bad address") on this PL device memory, so we
# load word-by-word with busybox `devmem` (mmap path). ~90s for 16K; fine for small
# tests. For big images use the DDR path (reserved region) instead.
#
# Usage:
#   scr1load.sh <image.bin> [--run] [--mbox]
#     <image.bin>  bare-metal image linked at 0xFFFF0000 (code/rodata/data only;
#                  .bss is cleared by crt). Loaded at PS 0x80100000.
#     --run        after loading, write the reset stub and release SCR1.
#     --mbox       after --run, poll the mailbox (0x80200000-scheme) and print output.
# Env overrides: LOAD_PHYS(0x80100000) STUB_PHYS(0x8010FF00) STUB_WORD(0xB00F006F)
#                RSTGPIO(0x80200000) MBOX(0x8010E000)
set -e
IMG="$1"; shift || true
: "${LOAD_PHYS:=0x80100000}"; : "${STUB_PHYS:=0x8010FF00}"; : "${STUB_WORD:=0xB00F006F}"
: "${RSTGPIO:=0x80200000}";   : "${MBOX:=0x8010E000}"
[ -f "$IMG" ] || { echo "usage: scr1load.sh <image.bin> [--run] [--mbox]"; exit 1; }

echo "[scr1load] hold SCR1 in reset"
devmem "$RSTGPIO" 32 0

echo "[scr1load] loading $(wc -c < "$IMG") bytes to $LOAD_PHYS (devmem word loop)..."
od -An -tx4 -v "$IMG" | tr -s ' ' '\n' | grep . > /tmp/_scr1w.txt
a=$(printf '%d' "$LOAD_PHYS")
while read w; do devmem $a 32 0x$w; a=$((a+4)); done < /tmp/_scr1w.txt
echo "[scr1load] loaded $(wc -l < /tmp/_scr1w.txt) words"

case " $* " in
  *" --run "*)
    echo "[scr1load] write reset stub $STUB_WORD @ $STUB_PHYS"
    devmem "$STUB_PHYS" 32 "$STUB_WORD"
    devmem $(($(printf '%d' "$MBOX")+0)) 32 0    # clear mbox len
    devmem $(($(printf '%d' "$MBOX")+4)) 32 0    # clear mbox done
    echo "[scr1load] release SCR1 reset"
    devmem "$RSTGPIO" 32 1
    ;;
esac

case " $* " in
  *" --mbox "*)
    echo "[scr1load] waiting for mailbox done (0xD09ED09E)..."
    i=0
    while [ $i -lt 400 ]; do
      d=$(devmem $(($(printf '%d' "$MBOX")+4)))
      [ "$d" = "0xD09ED09E" ] && break
      sleep 2; i=$((i+2))
    done
    len=$(printf '%d' "$(devmem $(($(printf '%d' "$MBOX")+0)))")
    echo "[scr1load] mailbox done=$d len=$len bytes:"
    echo "---------------------------------------------"
    o=0; base=$(($(printf '%d' "$MBOX")+8))
    while [ $o -lt $len ]; do
      w=$(devmem $((base+o))); w=${w#0x}
      # print 4 bytes little-endian
      printf "$(echo $w | sed 's/\(..\)\(..\)\(..\)\(..\)/\\x\4\\x\3\\x\2\\x\1/')"
      o=$((o+4))
    done
    echo ""; echo "---------------------------------------------"
    ;;
esac
echo "[scr1load] done"
