#!/usr/bin/env bash
# co_verify.sh - Stage 2 driver: build a rv32im test on the SCR1 DUT with the RVFI trace,
# run the reference model on the SAME image, and diff the two committed streams.
#
# Proves (in Verilator, no board) that the ISA reference model matches the DUT per-instruction.
# Usage: co_verify.sh <target>   e.g. co_verify.sh hello   /   co_verify.sh dhrystone21
set -euo pipefail
T="${1:-hello}"
S="$(cd "$(dirname "$0")/../.." && pwd)"                   # <repo>/scr1
W=$S/sim/rvfi_coverif
cd "$S"

echo ">>> [1/4] build refmodel"
gcc -O2 -o "$W/refmodel" "$W/refmodel.c"

echo ">>> [2/4] build DUT (rv32imc, real MAX cfg) + run with RVFI file trace: $T"
rm -rf build/verilator_AHB_* 2>/dev/null || true
LC_ALL=C make run_verilator CFG=MAX BUS=AHB \
     TARGETS="$T" SIM_BUILD_OPTS="-DSCR1_RVFI_EN -DSCR1_RVFI_TRACE" > /tmp/coverif_$T.log 2>&1
grep -E "PASS|FAIL" /tmp/coverif_$T.log | tail -1 || true
dutf=$(find build -name 'rvfi_dut.log' | head -1)
hex=$(find build -name "$T.hex" | head -1)
[ -f "$dutf" ] && [ -f "$hex" ] || { echo "ERROR: missing trace/hex (build failed?)"; tail -20 /tmp/coverif_$T.log; exit 1; }
echo "    DUT trace: $dutf ($(wc -l < "$dutf") records) ; image: $hex"

echo ">>> [3/4] run reference model on the same image (+CSR injection for self-timing tests)"
"$W/refmodel" "$hex" --reset 0x200 --mem-bytes 16777216 --max 200000000 --dut-trace "$dutf" > "$W/model.rvfi"
echo "    model: $(wc -l < "$W/model.rvfi") records"

echo ">>> [4/4] compare committed streams"
cp "$dutf" "$W/dut.rvfi"
python3 "$W/rvfi_compare.py" "$W/dut.rvfi" "$W/model.rvfi" --image "$hex"
