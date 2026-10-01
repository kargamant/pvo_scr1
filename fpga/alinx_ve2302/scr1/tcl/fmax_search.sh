#!/usr/bin/env bash
# =============================================================================
# fmax_search.sh - find the maximum cpu_clk frequency the SCR1 SoC closes timing
# at on the VD100 (Versal XCVE2302), by driving build_at_freq.tcl.
#
# Strategy: start from a known-good frequency, bracket upward by STEP_UP until a
# build FAILS timing (establishes lo=last-met, hi=first-fail), then binary-search
# the [lo,hi) gap down to RES MHz. Each trial runs synth + impl-to-route_design
# (no PDI) and reads post-route WNS/WHS. Results are cached so re-runs skip work.
#
# NOTE: each trial is a full synth+place+route (~30-45 min). A typical search is
# ~6-10 trials => several hours. Run it detached (e.g. under nohup/tmux).
#
# WARNING (timing is placement-dependent): the "max" found holds for THIS design
# and these tools; a freq that meets by a few ps may fail on another placement.
# Raise --margin (require WNS >= margin) for a guardband you can trust on silicon.
#
# The critical path here is CORE-internal (EXU exu_queue -> MPRF), so peripherals
# (UART etc.) do not move the ceiling; this searches the core's real limit.
#
# Usage:
#   ./fmax_search.sh [--start 90] [--step 10] [--res 2] [--margin 0.000] [--best-pdi]
#     --start N     known-good starting MHz (default 90; the current shipping build)
#     --step  N     upward bracket step in MHz (default 10)
#     --res   N     final resolution in MHz; search stops when hi-lo <= res (default 2)
#     --margin F    min WNS(ns) to count as "met" for the search (default 0.000)
#     --best-pdi    after finding Fmax, run ONE more full build (write_device_image)
#                   at Fmax to leave a usable PDI in build/fmax/best/
# =============================================================================
set -u

# --- config / paths ----------------------------------------------------------
ORIGIN=/home/toast/pvo_scr1/fpga/alinx_ve2302/scr1
TCL=$ORIGIN/tcl/build_at_freq.tcl
VIVADO_SETTINGS=/home/toast/Vivado_2023/Vivado/2023.2/settings64.sh
OUTDIR=$ORIGIN/build/fmax
LOGDIR=$OUTDIR/logs
CSV=$OUTDIR/results.csv

START=90 ; STEP=10 ; RES=2 ; MARGIN=0.000 ; BEST_PDI=0
while [ $# -gt 0 ]; do
  case "$1" in
    --start)  START=$2 ; shift 2 ;;
    --step)   STEP=$2  ; shift 2 ;;
    --res)    RES=$2   ; shift 2 ;;
    --margin) MARGIN=$2; shift 2 ;;
    --best-pdi) BEST_PDI=1 ; shift ;;
    *) echo "unknown arg: $1" >&2 ; exit 2 ;;
  esac
done

mkdir -p "$LOGDIR"
[ -f "$CSV" ] || echo "freq_mhz,wns_ns,whs_ns,status,seconds,timestamp" > "$CSV"
# shellcheck disable=SC1090
source "$VIVADO_SETTINGS"

# globals set by build_freq()
R_STATUS="" ; R_WNS=""

# met_for_search: status==MET and WNS >= MARGIN (awk for float compare)
met_for_search() {  # $1=status $2=wns
  [ "$1" = "MET" ] || return 1
  awk -v w="$2" -v m="$MARGIN" 'BEGIN{ exit !(w+0 >= m+0) }'
}

# build_freq MHZ  -> sets R_STATUS,R_WNS; uses cache in CSV.
build_freq() {
  local f=$1
  # cache hit? (a definitive MET/FAILED row for this freq)
  local cached
  cached=$(awk -F, -v f="$f" '$1==f && ($4=="MET"||$4=="FAILED"){print $4","$2; exit}' "$CSV")
  if [ -n "$cached" ]; then
    R_STATUS=${cached%%,*} ; R_WNS=${cached##*,}
    echo ">> ${f} MHz: cached -> $R_STATUS (WNS=$R_WNS)"
    return
  fi

  echo ">> ${f} MHz: building (synth+route)... log: $LOGDIR/run_${f}.log"
  local t0 t1 log
  log=$LOGDIR/run_${f}.log
  t0=$(date +%s)
  FMAX_MHZ=$f FMAX_PROJ=$OUTDIR/run LC_ALL=C vivado -mode batch -source "$TCL" \
      > "$log" 2>&1
  t1=$(date +%s)

  R_STATUS=$(grep -oE 'FMAX_STATUS: [A-Z_]+' "$log" | tail -1 | awk '{print $2}')
  R_WNS=$(grep -oE 'FMAX_WNS_NS: [-0-9.naN]+' "$log" | tail -1 | awk '{print $2}')
  [ -n "$R_STATUS" ] || R_STATUS=BUILD_ERROR
  [ -n "$R_WNS" ]    || R_WNS=nan
  echo "$f,$R_WNS,$(grep -oE 'FMAX_WHS_NS: [-0-9.naN]+' "$log" | tail -1 | awk '{print $2}'),$R_STATUS,$((t1-t0)),$(date -Is)" >> "$CSV"
  echo ">> ${f} MHz: $R_STATUS (WNS=$R_WNS, $((t1-t0))s)"
  if [ "$R_STATUS" = "BUILD_ERROR" ]; then
    echo "!! build error at ${f} MHz - see $log ; aborting." >&2
    exit 1
  fi
}

echo "== Fmax search: start=$START step=$STEP res=$RES margin=$MARGIN =="

# --- phase 1: bracket --------------------------------------------------------
lo="" ; hi=""
build_freq "$START"
if met_for_search "$R_STATUS" "$R_WNS"; then
  lo=$START
  f=$((START+STEP))
  while :; do
    build_freq "$f"
    if met_for_search "$R_STATUS" "$R_WNS"; then lo=$f ; f=$((f+STEP)) ; else hi=$f ; break ; fi
  done
else
  hi=$START
  f=$((START-STEP))
  while [ "$f" -gt 0 ]; do
    build_freq "$f"
    if met_for_search "$R_STATUS" "$R_WNS"; then lo=$f ; break ; else hi=$f ; f=$((f-STEP)) ; fi
  done
  if [ -z "$lo" ]; then echo "!! nothing met down to ${f} MHz; lower --start." >&2 ; exit 1 ; fi
fi
echo "== bracket: lo(met)=$lo  hi(fail)=$hi =="

# --- phase 2: binary search --------------------------------------------------
while [ $((hi-lo)) -gt "$RES" ]; do
  mid=$(((lo+hi)/2))
  build_freq "$mid"
  if met_for_search "$R_STATUS" "$R_WNS"; then lo=$mid ; else hi=$mid ; fi
  echo "   narrowed: lo=$lo hi=$hi"
done

# --- report ------------------------------------------------------------------
echo
echo "=================================================================="
echo " Fmax (meets timing, margin>=${MARGIN}ns): ${lo} MHz"
awk -F, -v lo="$lo" '$1==lo{printf "   WNS=%s ns  WHS=%s ns  status=%s\n",$2,$3,$4}' "$CSV"
echo " Full results table: $CSV"
column -t -s, "$CSV" 2>/dev/null || cat "$CSV"
echo "=================================================================="
echo
echo "To produce a usable PDI at Fmax, also update the software constant and rebuild:"
echo "  1) set SCR1_PTFM_CORE_CLK_FREQ = 32'd${lo}000000 in src/scr1_arch_custom.svh"
echo "     and CLKOUT_REQUESTED_OUT_FREQUENCY clk_out1 = ${lo}.000 in tcl/create_sopc.tcl"
echo "     (or: FMAX_MHZ=${lo} FMAX_FULL=1 vivado -mode batch -source tcl/build_at_freq.tcl)"
echo "  2) rebuild the board test .bins with SYS_CLK=${lo}000000 (UART baud depends on it)."

if [ "$BEST_PDI" = "1" ]; then
  echo ">> building final PDI at ${lo} MHz (write_device_image)..."
  FMAX_MHZ=$lo FMAX_FULL=1 FMAX_PROJ=$OUTDIR/best LC_ALL=C vivado -mode batch \
      -source "$TCL" > "$LOGDIR/best_${lo}.log" 2>&1
  grep -E 'FMAX_(STATUS|PDI):' "$LOGDIR/best_${lo}.log" || true
fi
