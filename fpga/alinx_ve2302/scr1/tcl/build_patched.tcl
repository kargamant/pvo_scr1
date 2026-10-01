set proj /home/student_007/Documents/pvo_scr1/fpga/alinx_ve2302/scr1/build/alinx_ve2302_scr1
open_project $proj/alinx_ve2302_scr1.xpr
# force re-synth of the (patched) emb_mem_gen wrapper; do NOT regenerate the BD (keeps patch)
#reset_run alinx_ve2302_sopc_emb_mem_gen_0_0_synth_1
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 16
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "BUILD: SYNTH_FAILED"; return }
# VERIFY the emb_mem_gen OOC actually used the init file (not NONE)
set ooclog $proj/alinx_ve2302_scr1.runs/alinx_ve2302_sopc_emb_mem_gen_0_0_synth_1/runme.log
set fh [open $ooclog r]; set txt [read $fh]; close $fh
if {[regexp {XPM_MEMORY 20-2\] MEMORY_INIT_FILE \(NONE\)} $txt]} {
    puts "INIT_CLOBBERED: wrapper regenerated to NONE - aborting before impl"
    return
} elseif {[regexp {MEMORY_INIT_FILE \(([^)]*scbl[^)]*)\)} $txt m fn]} {
    puts "INIT_OK: emb_mem_gen loaded $fn"
} else {
    puts "INIT_UNKNOWN: check $ooclog"
}
launch_runs impl_1 -to_step write_device_image -jobs 16
wait_on_run impl_1
puts "IMPL: [get_property PROGRESS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "BUILD: IMPL_FAILED"; return }
open_run impl_1
write_debug_probes -force $proj/../alinx_ve2302_scr1.ltx
puts "BUILD_DONE"
