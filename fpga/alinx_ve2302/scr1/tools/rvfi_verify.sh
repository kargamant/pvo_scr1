#!/bin/sh
# rvfi_verify.sh - fully self-hosted on-chip RVFI co-verification (Stage 4). Runs ON THE PS.
#
# Assumes the RVFI bitstream is loaded and a test has already been run on the SCR1 so the
# trace BRAM is populated (e.g. via ./scr1load.sh <img> then release reset). This step reads
# the captured retire stream straight out of PL memory (mmap /dev/mem, via rvfi_dump) and diffs
# it, instruction by instruction, against the ISA reference model executing the SAME image -
# entirely on the board, no laptop, no python.
#
# Usage (on the board, as root):
#   ./rvfi_verify.sh <image.bin> <reset_hex> <mem_bytes> [max_records]
# Example (CoreMark baked into boot BRAM, board reset vector):
#   ./rvfi_verify.sh cm_bram.bin 0xFFFFFF00 65536
#
# Needs in the same dir (shipped once by tools/rvfi_ship.py): rvfi_dump, refmodel, <image.bin>.
set -e
HERE=$(dirname "$0")
IMG=${1:?image.bin}; RESET=${2:?reset vector hex}; MEM=${3:?mem bytes}; MAXREC=${4:-0}

DUMP="$HERE/rvfi_dump"; MODEL="$HERE/refmodel"; TRACE=/tmp/hw.rvfi
[ -x "$DUMP" ]  || { echo "missing $DUMP (ship it first)"; exit 1; }
[ -x "$MODEL" ] || { echo "missing $MODEL (ship it first)"; exit 1; }
[ -f "$IMG" ]   || { echo "missing image $IMG"; exit 1; }

CNT=$("$DUMP" -c)
echo "[board] captured records: $CNT"
[ "$CNT" -gt 0 ] || { echo "trace empty - run a test on the SCR1 first (scr1load.sh)"; exit 1; }

if [ "$MAXREC" -gt 0 ]; then "$DUMP" -n "$MAXREC" -o "$TRACE"; else "$DUMP" -o "$TRACE"; fi

echo "[board] comparing DUT trace vs ISA model ..."
"$MODEL" "$IMG" --reset "$RESET" --mem-bytes "$MEM" --compare "$TRACE"
rc=$?
[ $rc -eq 0 ] && echo "[board] RVFI CO-VERIFICATION: PASS" || echo "[board] RVFI CO-VERIFICATION: FAIL (rc=$rc)"
exit $rc
