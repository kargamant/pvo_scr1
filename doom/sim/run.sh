#!/usr/bin/env bash
# Simulate the DOOM pixel framebuffer. Expects "RESULT: ALL PASS".
set -e
cd "$(dirname "$0")"
iverilog -g2012 -o tb_fb.vvp -I../rtl ../rtl/vga_timing.sv ../rtl/vga_fb.sv tb_vga_fb.sv
vvp tb_fb.vvp 2>/dev/null | grep -E "ok|FAIL|RESULT|pixels"
