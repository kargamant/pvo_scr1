# scr1_ila_debug.tcl
# ------------------------------------------------------------------------------
# Inserts one ILA (u_ila_0) that probes the SCR1 AXI imem/dmem buses and the
# UART serial lines, all sampled on cpu_clk. Study how a test is loaded over
# UART into TCM and then executed.
#
# Requires the (* mark_debug="true" *) attributes already added to
# nexys4ddr_scr1.sv, so the probed nets survive synthesis with their names.
#
# Run on the SYNTHESIZED netlist, e.g.:
#     open_run synth_1
#     source scr1_ila_debug.tcl
# then implement (see the step-by-step notes accompanying this file).
# ------------------------------------------------------------------------------

set ila    u_ila_0
set clknet cpu_clk
set depth  4096      ;# capture samples; raise to 8192 if BRAM allows

# probe table:  {net_base_name  width}
set probes {
    axi_imem_araddr  32
    axi_imem_arvalid  1
    axi_imem_arready  1
    axi_imem_arlen    8
    axi_imem_rdata   32
    axi_imem_rvalid   1
    axi_imem_rready   1
    axi_imem_rlast    1
    axi_imem_rresp    2
    axi_dmem_awaddr  32
    axi_dmem_awvalid  1
    axi_dmem_awready  1
    axi_dmem_wdata   32
    axi_dmem_wstrb    4
    axi_dmem_wvalid   1
    axi_dmem_wlast    1
    axi_dmem_bvalid   1
    axi_dmem_araddr  32
    axi_dmem_arvalid  1
    axi_dmem_rdata   32
    axi_dmem_rvalid   1
    uart_rxd          1
    uart_txd          1
    uart_irq          1
    tcm_dmem_addr    32
    tcm_dmem_wdata   32
    tcm_dmem_req      1
    tcm_dmem_req_ack  1
    tcm_dmem_cmd      1
    tcm_dmem_width    2
    tcm_imem_addr    32
    tcm_imem_rdata   32
    tcm_imem_req      1
    tcm_imem_req_ack  1
}

if {[llength [get_debug_cores -quiet $ila]]} {
    delete_debug_core [get_debug_cores $ila]
}

create_debug_core $ila ila
set_property C_DATA_DEPTH        $depth [get_debug_cores $ila]
set_property C_TRIGIN_EN         false  [get_debug_cores $ila]
set_property C_TRIGOUT_EN        false  [get_debug_cores $ila]
set_property C_ADV_TRIGGER       true   [get_debug_cores $ila]  ;# advanced (address-match) triggers
set_property C_EN_STRG_QUAL      true   [get_debug_cores $ila]  ;# capture-control (storage qualification)
set_property C_INPUT_PIPE_STAGES 1      [get_debug_cores $ila]  ;# help timing on the probe fan-in
set_property ALL_PROBE_SAME_MU     true [get_debug_cores $ila]
set_property ALL_PROBE_SAME_MU_CNT 4    [get_debug_cores $ila]  ;# 4 match units / probe

# ---- debug clock -------------------------------------------------------------
set_property port_width 1 [get_debug_ports $ila/clk]
connect_debug_port $ila/clk [get_nets [list $clknet]]

# ---- probes ------------------------------------------------------------------
set idx 0
foreach {name width} $probes {
    if {$idx > 0} { create_debug_port $ila probe }
    set port $ila/probe$idx
    set_property port_width $width [get_debug_ports $port]
    set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports $port]
    if {$width == 1} {
        set nets [get_nets -quiet $name]
    } else {
        set nets {}
        for {set b 0} {$b < $width} {incr b} { lappend nets ${name}\[$b\] }
        set nets [get_nets -quiet $nets]
    }
    if {[llength $nets] != $width} {
        puts "WARNING: probe$idx ($name): expected $width nets, found [llength $nets] - check mark_debug / net name"
    }
    connect_debug_port $port $nets
    puts [format "  probe%-2d <- %-18s \[%2d\]" $idx $name $width]
    incr idx
}

puts "ILA '$ila' inserted: $idx probes, depth $depth, clock '$clknet'."
puts "Next: opt_design; place_design; route_design; write_bitstream (see instructions)."
