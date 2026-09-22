open_hw_manager
disconnect_hw_server -quiet
connect_hw_server -quiet
set tgts [get_hw_targets]
puts "TARGETS: $tgts"
current_hw_target [lindex $tgts 0]
open_hw_target
set dev [lindex [get_hw_devices *xcve2302*] 0]
current_hw_device $dev
set_property PROGRAM.FILE /home/toast/pvo_scr1/fpga/alinx_ve2302/scr1/build/alinx_ve2302_scr1/alinx_ve2302_scr1.runs/impl_1/alinx_ve2302_scr1.pdi $dev
puts "PROGRAMMING..."
program_hw_devices $dev
puts "PROG_DONE"
