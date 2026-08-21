#!/usr/bin/env bash
# Simulate the snake peripherals (self-checking). Each expects "RESULT: ALL PASS".
set -e
cd "$(dirname "$0")"
RTL=../rtl

echo "### vga_timing ###"
iverilog -g2012 -o tb_timing.vvp -I$RTL $RTL/vga_timing.sv tb_vga_timing.sv
vvp tb_timing.vvp | grep -E "ok|FAIL|RESULT"

echo "### vga_ctrl ###"
iverilog -g2012 -o tb_ctrl.vvp -I$RTL $RTL/vga_timing.sv $RTL/vga_ctrl.sv tb_vga_ctrl.sv
vvp tb_ctrl.vvp 2>/dev/null | grep -E "ok|FAIL|RESULT|pixels"

if [ -f tb_ps2_kbd.sv ]; then
  echo "### ps2_kbd ###"
  iverilog -g2012 -o tb_ps2.vvp -I$RTL $RTL/ps2_rx.sv $RTL/ps2_kbd.sv tb_ps2_kbd.sv
  vvp tb_ps2.vvp 2>/dev/null | grep -E "ok|FAIL|RESULT"
fi
