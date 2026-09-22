# Arm the ILA to trigger on uart_txd FALLING (start bit of any TX char).
# Runs in background; while armed, the shell sends bytes into the board RX.
# If the core ever drives TX (echo/banner/response), this triggers and dumps CSV.
set proj /home/toast/pvo_scr1/fpga/alinx_ve2302/scr1/build/alinx_ve2302_scr1
set ltx  $proj/../alinx_ve2302_scr1.ltx
set csv  /tmp/claude-1000/-home-toast-scr1-sber/c255b7f4-3a70-45b6-a933-7da30028cd54/scratchpad/ila_txfall.csv
open_hw_manager
connect_hw_server -quiet
open_hw_target
set dev [lindex [get_hw_devices *xcve2302*] 0]
current_hw_device $dev
set_property PROBES.FILE $ltx $dev
refresh_hw_device $dev
set ila [lindex [get_hw_ilas -of_objects $dev] 0]
puts "ILA: $ila"
# Find the uart_txd probe by name.
set txp ""
foreach p [get_hw_probes -of_objects $ila] {
    if {[string match -nocase *uart_txd* $p]} { set txp $p }
}
puts "TXPROBE: $txp"
# Trigger: uart_txd == 0 (falling into start bit). Capture some pre/post.
set_property CONTROL.TRIGGER_POSITION 256  $ila
set_property CONTROL.DATA_DEPTH        8192 $ila
set_property TRIGGER_COMPARE_VALUE eq1'b0 [get_hw_probes $txp -of_objects $ila]
run_hw_ila $ila
puts "ARMED"
# Wait up to ~40s for a trigger.
if {[catch { wait_on_hw_ila -timeout 1 $ila } e]} { puts "WAIT_ERR: $e" }
set data [upload_hw_ila_data $ila]
write_hw_ila_data -csv_file -force $csv $data
puts "CSV_WRITTEN: $csv"
puts "DONE"
