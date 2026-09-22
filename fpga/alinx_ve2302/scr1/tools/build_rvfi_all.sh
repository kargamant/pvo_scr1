#!/usr/bin/env bash
# build_rvfi_all.sh - build the RVFI co-verification bitstream (SCR1_RVFI_EN=1): the tested
# design PLUS the observation tap + trace BRAM + PS bridge. Purely additive; the normal build
# (no env) is untouched. Stages into build/sdcard_rvfi/ so build/sdcard_cache/ (tested) is kept.
set -uo pipefail
# Paths derived from this script's location; machine-specific inputs come from env:
#   REF             = ALINX base BOOT.BIN (source of the APU firmware bl31/u-boot)
#   VIVADO_SETTINGS = path to Vivado settings64.sh (or have `vivado` already in PATH)
O="$(cd "$(dirname "$0")/.." && pwd)"                      # fpga/alinx_ve2302/scr1
REF="${REF:?set REF=<path to ALINX base BOOT.BIN>}"
VSET="${VIVADO_SETTINGS:-}"
LOG=$O/build/build_rvfi.log
mkdir -p "$O/build"
exec > "$LOG" 2>&1

echo "=== PHASE env $(date) ==="
[ -n "$VSET" ] && source "$VSET"; export LC_ALL=C
export SCR1_RVFI_EN=1               # single switch: RTL define + BD RVFI_EN
command -v vivado; command -v bootgen
cd "$O"

echo "=== PHASE vivado-build (RVFI) $(date) ==="
vivado -mode batch -source tcl/create_project_ps.tcl
echo "=== vivado exit rc=$? $(date) ==="

PDI=$(ls -t build/alinx_ve2302_scr1_ps/alinx_ve2302_scr1_ps.runs/impl_1/*.pdi 2>/dev/null | head -1)
echo "=== PDI=$PDI ==="
if [ -z "$PDI" ] || [ ! -f "$PDI" ]; then echo "=== RESULT BUILD_FAILED (no PDI) ==="; exit 1; fi

TRPT=$(ls -t build/alinx_ve2302_scr1_ps/alinx_ve2302_scr1_ps.runs/impl_1/*timing_summary*routed*.rpt 2>/dev/null | head -1)
[ -n "$TRPT" ] && { echo "=== TIMING (WNS) — RVFI adds logic, verify still met ==="; grep -iE 'WNS|Timing constraints are' "$TRPT" | head -5; }

echo "=== PHASE make-bootbin $(date) ==="
mkdir -p build/sdcard_rvfi
tools/make_bootbin.sh "$PDI" "$REF" "$O/build/sdcard_rvfi/BOOT.BIN"
cp build/sdcard_cache/image.ub build/sdcard_rvfi/image.ub
cp build/sdcard_cache/boot.scr build/sdcard_rvfi/boot.scr
echo "=== staged build/sdcard_rvfi/ ==="; ls -la build/sdcard_rvfi/
echo "=== RESULT ALL_DONE $(date) ==="
