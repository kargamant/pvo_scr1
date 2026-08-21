# ============================================================================
# build_pattern.tcl -- Phase-1 standalone VGA colour-bar bitstream (non-project)
# Usage:  LC_ALL=C vivado -mode batch -source snake/build_pattern.tcl
# Output: snake/build/vga_pattern_top.bit
# ============================================================================
set root   [file normalize [file dirname [info script]]]
set outdir  $root/build
file mkdir $outdir

read_verilog -sv $root/rtl/vga_timing.sv
read_verilog -sv $root/rtl/vga_pattern_top.sv
read_xdc         $root/constraints/nexys_a7_vga.xdc

synth_design -top vga_pattern_top -part xc7a100tcsg324-1
opt_design
place_design
route_design

report_timing_summary -file $outdir/timing.rpt
write_bitstream -force $outdir/vga_pattern_top.bit
puts "DONE: $outdir/vga_pattern_top.bit"
