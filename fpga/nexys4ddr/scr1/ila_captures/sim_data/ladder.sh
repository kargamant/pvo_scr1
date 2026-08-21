#!/bin/bash
# Лесенка конфигураций предсказателя: измеряет вклад каждой части.
# Правит только 3 define в scr1_arch_description.svh, в конце восстанавливает файл.
set -u
cd /home/toast/scr1_sber/scr1
H=src/includes/scr1_arch_description.svh
BAK=/tmp/arch_desc.bak
cp "$H" "$BAK"
trap 'cp "$BAK" "$H"; echo "[файл восстановлен]"' EXIT

set_flag () {  # $1=имя  $2=on|off
  if [ "$2" = on ]; then
    sed -i "s|^//\s*\`define $1\s*$|\`define $1|" "$H"
  else
    sed -i "s|^\`define $1\s*$|//\`define $1|" "$H"
  fi
}

run_cfg () {  # $1=метка $2=BPRED $3=RAS $4=DYN
  set_flag SCR1_BPRED_EN   "$2"
  set_flag SCR1_BP_RAS_EN  "$3"
  set_flag SCR1_BP_DYNAMIC "$4"
  echo "=================================================="
  echo "КОНФИГ: $1   (BPRED=$2 RAS=$3 DYNAMIC=$4)"
  grep -nE "define SCR1_BPRED_EN|define SCR1_BP_RAS_EN|define SCR1_BP_DYNAMIC" "$H" | sed 's/^/   /'
  LC_ALL=C make run_verilator CFG=MAX BUS=AHB TARGETS="dhrystone21 coremark" > /tmp/lad_$1.log 2>&1
  d=$(grep -oP 'Microseconds for one run through Dhrystone:\s*\K[0-9]+' /tmp/lad_$1.log | head -1)
  c=$(grep -oP 'Total ticks\s*:\s*\K[0-9]+' /tmp/lad_$1.log | head -1)
  echo "   РЕЗУЛЬТАТ  dhrystone=${d:-?} тактов   coremark=${c:-?} тактов"
  echo "$1 ${d:-?} ${c:-?}" >> /tmp/ladder_results.txt
}

: > /tmp/ladder_results.txt
run_cfg OFF        off off off
run_cfg BTFN       on  off off
run_cfg BTFN_RAS   on  on  off
run_cfg BTFN_RAS_BHT on on on

echo ""
echo "=== ИТОГ (метка dhrystone coremark) ==="
cat /tmp/ladder_results.txt
