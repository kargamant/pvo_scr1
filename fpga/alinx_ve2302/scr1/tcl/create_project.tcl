# =============================================================================
# create_project.tcl - full SCR1 SoC project for ALINX VD100 (Versal XCVE2302).
# Assembles: alinx_ve2302_sopc BD (CIPS+NoC+DDR4+peripherals) + the real SCR1 core
# and peripheral RTL (core.files + axi_top.files + cache) + the board top + XDC +
# boot .coe, then runs synth -> impl -> write_device_image (PDI).
#
# Usage:  cd <this dir>; LC_ALL=C vivado -mode batch -source create_project.tcl
# =============================================================================

set origin  /home/student_007/Documents/pvo_scr1/fpga/alinx_ve2302/scr1
set scrsrc  /home/student_007/Documents/pvo_scr1/scr1/src
set proj    $origin/build/alinx_ve2302_scr1
set part    xcve2302-sfva784-1LP-e-s
set coe     $origin/mem/scbl.coe

create_project -force alinx_ve2302_scr1 $proj -part $part

# --- 1) SoPC block design (CIPS+NoC+DDR4 + smartconnect + gpio x3 + boot BRAM) --------
source $origin/tcl/create_sopc.tcl          ;# leaves BD open, init set post-validate
set bdf [get_files *alinx_ve2302_sopc.bd]
# Belt-and-suspenders: re-apply boot init right before generating (propagation resets it).
catch { set_property CONFIG.MEMORY_INIT_FILE $coe [get_bd_cells emb_mem_gen_0] }
generate_target all $bdf
# Instantiate the BD by its module name (the top does `alinx_ve2302_sopc i_soc`).
add_files -norecurse [glob -nocomplain $proj/alinx_ve2302_scr1.gen/sources_1/bd/alinx_ve2302_sopc/hdl/*.v]

# --- 2) Real SCR1 core + peripherals + cache + board top -----------------------------
set files {}
foreach f [split [string trim [read [open $scrsrc/core.files]]] "\n"]   { lappend files $scrsrc/$f }
foreach f [split [string trim [read [open $scrsrc/axi_top.files]]] "\n"] { lappend files $scrsrc/$f }
#lappend files $scrsrc/core/cache/scr1_icache.sv
#lappend files $scrsrc/core/cache/scr1_dcache.sv
#lappend files $scrsrc/core/cache/scr1_cache_wrapper.sv
lappend files $origin/src/alinx_ve2302_scr1.sv
add_files -norecurse $files

# boot image (.coe) as a project source so emb_mem_gen resolves it by name too
add_files -norecurse $coe

# --- 3) Constraints ------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse $origin/constrs/alinx_ve2302_scr1_physical.xdc

# --- 4) Defines + include dirs (arch_custom dir MUST precede scr1/src/includes) -------
set src_fs [get_filesets sources_1]
set_property include_dirs   [list $origin/src $scrsrc/includes] $src_fs
set_property verilog_define {SCR1_ARCH_CUSTOM=1}                 $src_fs
set_property top alinx_ve2302_scr1 $src_fs
update_compile_order -fileset sources_1

# --- 5) Build: synthesis -> implementation -> PDI ------------------------------------
#launch_runs synth_1 -jobs 8
#wait_on_run synth_1
#if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
#    puts "BUILD_RESULT: SYNTH_FAILED ([get_property STATUS [get_runs synth_1]])"
#    return
#}
#launch_runs impl_1 -to_step write_device_image -jobs 8
#wait_on_run impl_1
#puts "IMPL_STATUS: [get_property STATUS [get_runs impl_1]]"
#puts "IMPL_PROGRESS: [get_property PROGRESS [get_runs impl_1]]"
#set pdi [glob -nocomplain $proj/alinx_ve2302_scr1.runs/impl_1/*.pdi]
#puts "PDI_FILE: $pdi"
#puts "BUILD_RESULT: DONE"
