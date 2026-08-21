#!/bin/bash
set -u
cd /home/toast/scr1_sber/scr1
H=src/includes/scr1_arch_description.svh
cp "$H" /tmp/arch_desc2.bak
trap 'cp /tmp/arch_desc2.bak "$H"; echo "[header restored]"' EXIT

set_flag () {
  if [ "$2" = on ]; then sed -i "s|^//\s*\`define $1\s*$|\`define $1|" "$H"
  else sed -i "s|^\`define $1\s*$|//\`define $1|" "$H"; fi
}

: > /tmp/bpstat_results.txt
run_cfg () {
  set_flag SCR1_BPRED_EN "$2"; set_flag SCR1_BP_RAS_EN "$3"; set_flag SCR1_BP_DYNAMIC "$4"
  echo "=== $1 (BPRED=$2 RAS=$3 DYN=$4) ==="
  LC_ALL=C make run_verilator CFG=MAX BUS=AHB TARGETS="dhrystone21 coremark" > /tmp/bp_$1.log 2>&1
  # BPSTAT печатается по одному разу на тест, в порядке запуска
  mapfile -t stats < <(grep -oP 'BPSTAT \K.*' /tmp/bp_$1.log)
  d=$(grep -oP 'Microseconds for one run through Dhrystone:\s*\K[0-9]+' /tmp/bp_$1.log | head -1)
  c=$(grep -oP 'Total ticks\s*:\s*\K[0-9]+' /tmp/bp_$1.log | head -1)
  echo "   dhrystone=${d:-?}  coremark=${c:-?}"
  for i in "${!stats[@]}"; do echo "   BPSTAT[$i] ${stats[$i]}"; done
  {
    echo "CONFIG $1 dhry=${d:-?} cm=${c:-?}"
    for i in "${!stats[@]}"; do echo "   stat$i ${stats[$i]}"; done
  } >> /tmp/bpstat_results.txt
}

run_cfg OFF      off off off
run_cfg BTFN     on  off off
run_cfg BTFN_RAS on  on  off
run_cfg FULL     on  on  on

echo ""; echo "=== ALL ==="; cat /tmp/bpstat_results.txt
