# =============================================================================
# build_at_freq.tcl - build the SCR1 SoC at a parametrized cpu_clk frequency and
# report post-route timing. Used by fmax_search.sh to hunt the maximum achievable
# frequency. Derived from create_project.tcl; the ONLY functional difference is
# that the clk_wizard clk_out1 target is overridden by $env(FMAX_MHZ) and, by
# default, implementation stops at route_design (no PDI) to save time.
#
# Inputs (environment variables):
#   FMAX_MHZ   integer MHz for cpu_clk (clk_wizard clk_out1).      REQUIRED.
#   FMAX_FULL  "1" => run to write_device_image (produce a PDI);   optional.
#              anything else / unset => stop at route_design (timing only).
#   FMAX_PROJ  project directory. optional (default build/fmax/run).
#
# Output markers (parsed by the driver; grep-friendly, one per line):
#   FMAX_REQ_MHZ:  <int>
#   FMAX_WNS_NS:   <float setup slack, worst>      ("nan" if the build errored)
#   FMAX_WHS_NS:   <float hold slack, worst>
#   FMAX_STATUS:   MET | FAILED | BUILD_ERROR
#   FMAX_PDI:      <path>                           (only when FMAX_FULL=1 and MET)
#
# Usage (normally via fmax_search.sh, not by hand):
#   FMAX_MHZ=100 LC_ALL=C vivado -mode batch -source build_at_freq.tcl
# =============================================================================

set origin  [file dirname [file dirname [file normalize [info script]]]]
set scrsrc  [file normalize [file join $origin .. .. .. scr1 src]]
set part    xcve2302-sfva784-1LP-e-s
set coe     $origin/mem/scbl.coe

if {![info exists ::env(FMAX_MHZ)]} { error "FMAX_MHZ not set" }
set fmhz [expr {int($::env(FMAX_MHZ))}]
set full [expr {[info exists ::env(FMAX_FULL)] && $::env(FMAX_FULL) eq "1"}]
set proj [expr {[info exists ::env(FMAX_PROJ)] ? $::env(FMAX_PROJ) : "$origin/build/fmax/run"}]

puts "FMAX_REQ_MHZ: $fmhz"

create_project -force alinx_ve2302_scr1 $proj -part $part

# --- 1) SoPC block design, then OVERRIDE the clk_wizard clk_out1 target ---------------
source $origin/tcl/create_sopc.tcl          ;# leaves BD open, validated at 90 MHz
set freqlist [format "%d.000,100.000,100.000,100.000,100.000,100.000,100.000" $fmhz]
set_property CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY $freqlist [get_bd_cells clk_wizard_0]
validate_bd_design
# validate/propagation resets emb_mem_gen's init file (BD 41-2180) - re-apply, then save.
catch { set_property CONFIG.MEMORY_INIT_FILE $coe [get_bd_cells emb_mem_gen_0] }
save_bd_design

set bdf [get_files *alinx_ve2302_sopc.bd]
catch { set_property CONFIG.MEMORY_INIT_FILE $coe [get_bd_cells emb_mem_gen_0] }
generate_target all $bdf
add_files -norecurse [glob -nocomplain $proj/alinx_ve2302_scr1.gen/sources_1/bd/alinx_ve2302_sopc/hdl/*.v]

# --- 2) Real SCR1 core + peripherals + cache + board top -----------------------------
set files {}
foreach f [split [string trim [read [open $scrsrc/core.files]]] "\n"]   { lappend files $scrsrc/$f }
foreach f [split [string trim [read [open $scrsrc/axi_top.files]]] "\n"] { lappend files $scrsrc/$f }
lappend files $scrsrc/core/cache/scr1_icache.sv
lappend files $scrsrc/core/cache/scr1_dcache.sv
lappend files $scrsrc/core/cache/scr1_cache_wrapper.sv
lappend files $origin/src/alinx_ve2302_scr1.sv
add_files -norecurse $files
add_files -norecurse $coe

# --- 3) Constraints ------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse $origin/constrs/alinx_ve2302_scr1_physical.xdc

# --- 4) Defines + include dirs -------------------------------------------------------
set src_fs [get_filesets sources_1]
set_property include_dirs   [list $origin/src $scrsrc/includes] $src_fs
set_property verilog_define {SCR1_ARCH_CUSTOM=1}                 $src_fs
set_property top alinx_ve2302_scr1 $src_fs
update_compile_order -fileset sources_1

# --- 5) Synthesis --------------------------------------------------------------------
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "FMAX_WNS_NS: nan"
    puts "FMAX_STATUS: BUILD_ERROR"
    puts "SYNTH_FAILED: [get_property STATUS [get_runs synth_1]]"
    return
}

# --- 6) Implementation: route (search) or full device image (final) ------------------
set to_step [expr {$full ? "write_device_image" : "route_design"}]
launch_runs impl_1 -to_step $to_step -jobs 8
wait_on_run impl_1
set prog [get_property PROGRESS [get_runs impl_1]]
if {$prog != "100%"} {
    puts "FMAX_WNS_NS: nan"
    puts "FMAX_STATUS: BUILD_ERROR"
    puts "IMPL_FAILED: [get_property STATUS [get_runs impl_1]] ($prog)"
    return
}

# --- 7) Post-route timing ------------------------------------------------------------
open_run impl_1
set setup_path [lindex [get_timing_paths -delay_type max -max_paths 1 -nworst 1] 0]
set hold_path  [lindex [get_timing_paths -delay_type min -max_paths 1 -nworst 1] 0]
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
puts "FMAX_WNS_NS: $wns"
puts "FMAX_WHS_NS: $whs"
if {$wns >= 0 && $whs >= 0} {
    puts "FMAX_STATUS: MET"
} else {
    puts "FMAX_STATUS: FAILED"
}
if {$full} {
    set pdi [glob -nocomplain $proj/alinx_ve2302_scr1.runs/impl_1/*.pdi]
    puts "FMAX_PDI: $pdi"
}
