# =============================================================================
# create_project_ps.tcl - COMBINED build: full PS (boots PetaLinux) + SCR1 + PS bridge.
# Same as create_project.tcl but uses the combined BD (create_sopc_ps.tcl) and also
# exports an XSA (write_hw_platform) for the PetaLinux rebuild.
#
# Usage:  cd <this dir>; LC_ALL=C vivado -mode batch -source create_project_ps.tcl
# =============================================================================

set origin  /home/toast/pvo_scr1/fpga/alinx_ve2302/scr1
set scrsrc  /home/toast/pvo_scr1/scr1/src
set proj    $origin/build/alinx_ve2302_scr1_ps
set part    xcve2302-sfva784-1LP-e-s
set coe     $origin/mem/scbl.coe

create_project -force alinx_ve2302_scr1_ps $proj -part $part

# --- 1) Combined SoPC block design (full PS + NoC/DDR + SCR1 + PS bridge) -------------
source $origin/tcl/create_sopc_ps.tcl        ;# leaves BD open, init set post-validate
set bdf [get_files *alinx_ve2302_sopc.bd]
catch { set_property CONFIG.MEMORY_INIT_FILE $coe [get_bd_cells emb_mem_gen_0] }
generate_target all $bdf
# CRITICAL (BD 41-2180 + Versal): emb_mem_gen boot BRAM init is clobbered to NONE by
# axi_bram_ctrl propagation during generate_target; the ONLY init that sticks into OOC
# synth is patching the generated wrapper .v (tcl/patch_boot_bram.sh) then re-synth.
# See memory scr1-versal-vd100-port. Applied post-generate below on the .xci for record.
set_property CONFIG.MEMORY_INIT_FILE $coe [get_ips *emb_mem_gen_0_0]
puts "BOOT_BRAM_INIT: [get_property CONFIG.MEMORY_INIT_FILE [get_ips *emb_mem_gen_0_0]]"
add_files -norecurse [glob -nocomplain $proj/alinx_ve2302_scr1_ps.gen/sources_1/bd/alinx_ve2302_sopc/hdl/*.v]

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

# --- 5) Build: synth -> impl -> PDI + XSA --------------------------------------------
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "BUILD_RESULT: SYNTH_FAILED ([get_property STATUS [get_runs synth_1]])"
    return
}
puts "SYNTH_DONE"
launch_runs impl_1 -to_step write_device_image -jobs 8
wait_on_run impl_1
puts "IMPL_STATUS: [get_property STATUS [get_runs impl_1]]"
puts "IMPL_PROGRESS: [get_property PROGRESS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "BUILD_RESULT: IMPL_FAILED"; return
}
set pdi [glob -nocomplain $proj/alinx_ve2302_scr1_ps.runs/impl_1/*.pdi]
puts "PDI_FILE: $pdi"
# XSA for PetaLinux (needs the implemented design + PDI).
open_run impl_1
set xsa $origin/build/alinx_ve2302_scr1_ps.xsa
write_hw_platform -fixed -include_bit -force -file $xsa
puts "XSA_FILE: $xsa"
puts "BUILD_RESULT: DONE"
