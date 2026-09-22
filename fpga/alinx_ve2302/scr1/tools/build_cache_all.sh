#!/usr/bin/env bash
# build_cache_all.sh - one-shot: rebuild combined PS+SCR1 PDI (with updated cache + DDR
# cacheable-region fix), wrap into BOOT.BIN, stage into build/sdcard_cache/ (leaves the
# known-good build/sdcard_ready/ untouched). Detached-friendly; logs phases to build/build_cache.log.
set -uo pipefail
# Paths derived from this script's location; machine-specific inputs come from env:
#   REF             = ALINX base BOOT.BIN (source of the APU firmware bl31/u-boot)
#   VIVADO_SETTINGS = path to Vivado settings64.sh (or have `vivado` already in PATH)
O="$(cd "$(dirname "$0")/.." && pwd)"                      # fpga/alinx_ve2302/scr1
REF="${REF:?set REF=<path to ALINX base BOOT.BIN>}"
VSET="${VIVADO_SETTINGS:-}"
LOG=$O/build/build_cache.log
mkdir -p "$O/build"
exec > "$LOG" 2>&1

echo "=== PHASE env $(date) ==="
[ -n "$VSET" ] && source "$VSET"; export LC_ALL=C
command -v vivado; command -v bootgen
cd "$O"

echo "=== PHASE vivado-build $(date) ==="
vivado -mode batch -source tcl/create_project_ps.tcl
rc=$?
echo "=== vivado exit rc=$rc $(date) ==="

PDI=$(ls -t build/alinx_ve2302_scr1_ps/alinx_ve2302_scr1_ps.runs/impl_1/*.pdi 2>/dev/null | head -1)
echo "=== PDI=$PDI ==="
if [ -z "$PDI" ] || [ ! -f "$PDI" ]; then echo "=== RESULT BUILD_FAILED (no PDI) ==="; exit 1; fi

# grab timing (WNS) if a routed timing summary exists
TRPT=$(ls -t build/alinx_ve2302_scr1_ps/alinx_ve2302_scr1_ps.runs/impl_1/*timing_summary*routed*.rpt 2>/dev/null | head -1)
[ -n "$TRPT" ] && { echo "=== TIMING (WNS) ==="; grep -iE 'WNS|Slack|Timing constraints are' "$TRPT" | head -5; }

echo "=== PHASE make-bootbin $(date) ==="
mkdir -p build/sdcard_cache
tools/make_bootbin.sh "$PDI" "$REF" "$O/build/sdcard_cache/BOOT.BIN"
cp build/sdcard_ready/image.ub build/sdcard_cache/image.ub
cp build/sdcard_ready/boot.scr build/sdcard_cache/boot.scr
echo "=== staged build/sdcard_cache/ ==="; ls -la build/sdcard_cache/
echo "=== RESULT ALL_DONE $(date) ==="
