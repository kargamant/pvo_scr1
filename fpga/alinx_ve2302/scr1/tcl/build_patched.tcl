# Usage:
#   vivado -mode batch -source tcl/build_patched.tcl
#   vivado -mode batch -source tcl/build_patched.tcl -tclargs ps
#   vivado -mode batch -source tcl/build_patched.tcl -tclargs ps -j 16
#
# Accepted job-count forms: -j N, --jobs N, --jobs=N, or a positional N.
# Defaults: standalone project, 8 jobs.
set mode standalone
set jobs 8

set i 0
while {$i < [llength $argv]} {
    set arg [lindex $argv $i]

    if {[regexp {^--jobs=(.+)$} $arg -> value]} {
        set jobs $value
    } else {
        switch -- $arg {
            ps -
            --ps {
                set mode ps
            }
            -j -
            --jobs {
                incr i
                if {$i >= [llength $argv]} {
                    error "missing job count after $arg"
                }
                set jobs [lindex $argv $i]
            }
            default {
                if {[string is integer -strict $arg]} {
                    set jobs $arg
                } else {
                    error "unknown argument '$arg'; expected ps, --ps, -j N, --jobs N, --jobs=N, or N"
                }
            }
        }
    }

    incr i
}

if {![string is integer -strict $jobs] || $jobs < 1} {
    error "job count must be a positive integer, got '$jobs'"
}

set origin [file dirname [file dirname [file normalize [info script]]]]
if {$mode eq "ps"} {
    set project_name alinx_ve2302_scr1_ps
} else {
    set project_name alinx_ve2302_scr1
}
set proj [file normalize [file join $origin build $project_name]]
puts "MODE: $mode"
puts "PROJECT: $proj"
puts "JOBS: $jobs"
open_project [file join $proj ${project_name}.xpr]
# force re-synth of the (patched) emb_mem_gen wrapper; do NOT regenerate the BD (keeps patch)
reset_run alinx_ve2302_sopc_emb_mem_gen_0_0_synth_1
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "BUILD: SYNTH_FAILED"; return }
# VERIFY the emb_mem_gen OOC actually used the init file (not NONE)
set ooclog [file join $proj ${project_name}.runs alinx_ve2302_sopc_emb_mem_gen_0_0_synth_1 runme.log]
set fh [open $ooclog r]; set txt [read $fh]; close $fh
if {[regexp {XPM_MEMORY 20-2\] MEMORY_INIT_FILE \(NONE\)} $txt]} {
    puts "INIT_CLOBBERED: wrapper regenerated to NONE - aborting before impl"
    return
} elseif {[regexp {MEMORY_INIT_FILE \(([^)]*scbl[^)]*)\)} $txt m fn]} {
    puts "INIT_OK: emb_mem_gen loaded $fn"
} else {
    puts "INIT_UNKNOWN: check $ooclog"
}
launch_runs impl_1 -to_step write_device_image -jobs $jobs
wait_on_run impl_1
puts "IMPL: [get_property PROGRESS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "BUILD: IMPL_FAILED"; return }
open_run impl_1
write_debug_probes -force [file join $origin build ${project_name}.ltx]
puts "BUILD_DONE"
