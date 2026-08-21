##
## Copyright by Syntacore LLC © 2016, 2017, 2021. See LICENSE for details
## @file       <nexys4ddr_scr1_synth.xdc>
## @brief      Constraint file for Xilinx Vivado synthesis.
##

## Primary Clocks
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]

create_clock -period 10.000 -name CLK100MHZ -waveform {0.000 5.000} -add [get_ports CLK100MHZ]
create_clock -period 33.333 -name CPU_CLK_VIRT -waveform {0.000 16.666}
create_clock -period 100.000 -name JTAG_TCK -waveform {0.000 50.000} -add [get_ports {JC[3]}]
create_clock -period 100.000 -name JTAG_TCK_VIRT -waveform {0.000 50.000}



#ILA_DISABLED# create_debug_core u_ila_0 ila
#ILA_DISABLED# set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
#ILA_DISABLED# set_property ALL_PROBE_SAME_MU_CNT 4 [get_debug_cores u_ila_0]
#ILA_DISABLED# set_property C_ADV_TRIGGER true [get_debug_cores u_ila_0]
#ILA_DISABLED# set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_0]
#ILA_DISABLED# set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0]
#ILA_DISABLED# set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
#ILA_DISABLED# set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
#ILA_DISABLED# set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
#ILA_DISABLED# set_property port_width 1 [get_debug_ports u_ila_0/clk]
#ILA_DISABLED# connect_debug_port u_ila_0/clk [get_nets [list i_soc/clk_wiz_0/inst/clk_out1]]
#ILA_DISABLED# set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
#ILA_DISABLED# set_property port_width 32 [get_debug_ports u_ila_0/probe0]
#ILA_DISABLED# connect_debug_port u_ila_0/probe0 [get_nets [list {i_scr1/tcm_dmem_wdata[0]} {i_scr1/tcm_dmem_wdata[1]} {i_scr1/tcm_dmem_wdata[2]} {i_scr1/tcm_dmem_wdata[3]} {i_scr1/tcm_dmem_wdata[4]} {i_scr1/tcm_dmem_wdata[5]} {i_scr1/tcm_dmem_wdata[6]} {i_scr1/tcm_dmem_wdata[7]} {i_scr1/tcm_dmem_wdata[8]} {i_scr1/tcm_dmem_wdata[9]} {i_scr1/tcm_dmem_wdata[10]} {i_scr1/tcm_dmem_wdata[11]} {i_scr1/tcm_dmem_wdata[12]} {i_scr1/tcm_dmem_wdata[13]} {i_scr1/tcm_dmem_wdata[14]} {i_scr1/tcm_dmem_wdata[15]} {i_scr1/tcm_dmem_wdata[16]} {i_scr1/tcm_dmem_wdata[17]} {i_scr1/tcm_dmem_wdata[18]} {i_scr1/tcm_dmem_wdata[19]} {i_scr1/tcm_dmem_wdata[20]} {i_scr1/tcm_dmem_wdata[21]} {i_scr1/tcm_dmem_wdata[22]} {i_scr1/tcm_dmem_wdata[23]} {i_scr1/tcm_dmem_wdata[24]} {i_scr1/tcm_dmem_wdata[25]} {i_scr1/tcm_dmem_wdata[26]} {i_scr1/tcm_dmem_wdata[27]} {i_scr1/tcm_dmem_wdata[28]} {i_scr1/tcm_dmem_wdata[29]} {i_scr1/tcm_dmem_wdata[30]} {i_scr1/tcm_dmem_wdata[31]}]]
#ILA_DISABLED# create_debug_port u_ila_0 probe
#ILA_DISABLED# set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
#ILA_DISABLED# set_property port_width 32 [get_debug_ports u_ila_0/probe1]
#ILA_DISABLED# connect_debug_port u_ila_0/probe1 [get_nets [list {i_scr1/tcm_dmem_addr[0]} {i_scr1/tcm_dmem_addr[1]} {i_scr1/tcm_dmem_addr[2]} {i_scr1/tcm_dmem_addr[3]} {i_scr1/tcm_dmem_addr[4]} {i_scr1/tcm_dmem_addr[5]} {i_scr1/tcm_dmem_addr[6]} {i_scr1/tcm_dmem_addr[7]} {i_scr1/tcm_dmem_addr[8]} {i_scr1/tcm_dmem_addr[9]} {i_scr1/tcm_dmem_addr[10]} {i_scr1/tcm_dmem_addr[11]} {i_scr1/tcm_dmem_addr[12]} {i_scr1/tcm_dmem_addr[13]} {i_scr1/tcm_dmem_addr[14]} {i_scr1/tcm_dmem_addr[15]} {i_scr1/tcm_dmem_addr[16]} {i_scr1/tcm_dmem_addr[17]} {i_scr1/tcm_dmem_addr[18]} {i_scr1/tcm_dmem_addr[19]} {i_scr1/tcm_dmem_addr[20]} {i_scr1/tcm_dmem_addr[21]} {i_scr1/tcm_dmem_addr[22]} {i_scr1/tcm_dmem_addr[23]} {i_scr1/tcm_dmem_addr[24]} {i_scr1/tcm_dmem_addr[25]} {i_scr1/tcm_dmem_addr[26]} {i_scr1/tcm_dmem_addr[27]} {i_scr1/tcm_dmem_addr[28]} {i_scr1/tcm_dmem_addr[29]} {i_scr1/tcm_dmem_addr[30]} {i_scr1/tcm_dmem_addr[31]}]]
#ILA_DISABLED# create_debug_port u_ila_0 probe
#ILA_DISABLED# set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
#ILA_DISABLED# set_property port_width 32 [get_debug_ports u_ila_0/probe2]
#ILA_DISABLED# connect_debug_port u_ila_0/probe2 [get_nets [list {i_scr1/tcm_imem_rdata[0]} {i_scr1/tcm_imem_rdata[1]} {i_scr1/tcm_imem_rdata[2]} {i_scr1/tcm_imem_rdata[3]} {i_scr1/tcm_imem_rdata[4]} {i_scr1/tcm_imem_rdata[5]} {i_scr1/tcm_imem_rdata[6]} {i_scr1/tcm_imem_rdata[7]} {i_scr1/tcm_imem_rdata[8]} {i_scr1/tcm_imem_rdata[9]} {i_scr1/tcm_imem_rdata[10]} {i_scr1/tcm_imem_rdata[11]} {i_scr1/tcm_imem_rdata[12]} {i_scr1/tcm_imem_rdata[13]} {i_scr1/tcm_imem_rdata[14]} {i_scr1/tcm_imem_rdata[15]} {i_scr1/tcm_imem_rdata[16]} {i_scr1/tcm_imem_rdata[17]} {i_scr1/tcm_imem_rdata[18]} {i_scr1/tcm_imem_rdata[19]} {i_scr1/tcm_imem_rdata[20]} {i_scr1/tcm_imem_rdata[21]} {i_scr1/tcm_imem_rdata[22]} {i_scr1/tcm_imem_rdata[23]} {i_scr1/tcm_imem_rdata[24]} {i_scr1/tcm_imem_rdata[25]} {i_scr1/tcm_imem_rdata[26]} {i_scr1/tcm_imem_rdata[27]} {i_scr1/tcm_imem_rdata[28]} {i_scr1/tcm_imem_rdata[29]} {i_scr1/tcm_imem_rdata[30]} {i_scr1/tcm_imem_rdata[31]}]]
#ILA_DISABLED# create_debug_port u_ila_0 probe
#ILA_DISABLED# set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
#ILA_DISABLED# set_property port_width 2 [get_debug_ports u_ila_0/probe3]
#ILA_DISABLED# connect_debug_port u_ila_0/probe3 [get_nets [list {i_scr1/tcm_dmem_width[0]} {i_scr1/tcm_dmem_width[1]}]]
#ILA_DISABLED# create_debug_port u_ila_0 probe
#ILA_DISABLED# set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
#ILA_DISABLED# set_property port_width 32 [get_debug_ports u_ila_0/probe4]
#ILA_DISABLED# connect_debug_port u_ila_0/probe4 [get_nets [list {i_scr1/tcm_imem_addr[0]} {i_scr1/tcm_imem_addr[1]} {i_scr1/tcm_imem_addr[2]} {i_scr1/tcm_imem_addr[3]} {i_scr1/tcm_imem_addr[4]} {i_scr1/tcm_imem_addr[5]} {i_scr1/tcm_imem_addr[6]} {i_scr1/tcm_imem_addr[7]} {i_scr1/tcm_imem_addr[8]} {i_scr1/tcm_imem_addr[9]} {i_scr1/tcm_imem_addr[10]} {i_scr1/tcm_imem_addr[11]} {i_scr1/tcm_imem_addr[12]} {i_scr1/tcm_imem_addr[13]} {i_scr1/tcm_imem_addr[14]} {i_scr1/tcm_imem_addr[15]} {i_scr1/tcm_imem_addr[16]} {i_scr1/tcm_imem_addr[17]} {i_scr1/tcm_imem_addr[18]} {i_scr1/tcm_imem_addr[19]} {i_scr1/tcm_imem_addr[20]} {i_scr1/tcm_imem_addr[21]} {i_scr1/tcm_imem_addr[22]} {i_scr1/tcm_imem_addr[23]} {i_scr1/tcm_imem_addr[24]} {i_scr1/tcm_imem_addr[25]} {i_scr1/tcm_imem_addr[26]} {i_scr1/tcm_imem_addr[27]} {i_scr1/tcm_imem_addr[28]} {i_scr1/tcm_imem_addr[29]} {i_scr1/tcm_imem_addr[30]} {i_scr1/tcm_imem_addr[31]}]]
#ILA_DISABLED# create_debug_port u_ila_0 probe
#ILA_DISABLED# set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
#ILA_DISABLED# set_property port_width 1 [get_debug_ports u_ila_0/probe5]
#ILA_DISABLED# connect_debug_port u_ila_0/probe5 [get_nets [list i_scr1/tcm_dmem_req_ack]]
#ILA_DISABLED# create_debug_port u_ila_0 probe
#ILA_DISABLED# set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
#ILA_DISABLED# set_property port_width 1 [get_debug_ports u_ila_0/probe6]
#ILA_DISABLED# connect_debug_port u_ila_0/probe6 [get_nets [list i_scr1/tcm_imem_req_ack]]
#ILA_DISABLED# create_debug_port u_ila_0 probe
#ILA_DISABLED# set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
#ILA_DISABLED# set_property port_width 1 [get_debug_ports u_ila_0/probe7]
#ILA_DISABLED# connect_debug_port u_ila_0/probe7 [get_nets [list uart_irq]]
#ILA_DISABLED# create_debug_port u_ila_0 probe
#ILA_DISABLED# set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
#ILA_DISABLED# set_property port_width 1 [get_debug_ports u_ila_0/probe8]
#ILA_DISABLED# connect_debug_port u_ila_0/probe8 [get_nets [list uart_rxd]]
#ILA_DISABLED# create_debug_port u_ila_0 probe
#ILA_DISABLED# set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
#ILA_DISABLED# set_property port_width 1 [get_debug_ports u_ila_0/probe9]
#ILA_DISABLED# connect_debug_port u_ila_0/probe9 [get_nets [list uart_txd]]
#ILA_DISABLED# set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
#ILA_DISABLED# set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
#ILA_DISABLED# set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
#ILA_DISABLED# connect_debug_port dbg_hub/clk [get_nets cpu_clk]
