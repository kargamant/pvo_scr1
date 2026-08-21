create_debug_core u_ila_0 ila
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list i_soc/clk_wiz_0/inst/clk_out1]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 32 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {axi_imem_araddr[0]} {axi_imem_araddr[1]} {axi_imem_araddr[2]} {axi_imem_araddr[3]} {axi_imem_araddr[4]} {axi_imem_araddr[5]} {axi_imem_araddr[6]} {axi_imem_araddr[7]} {axi_imem_araddr[8]} {axi_imem_araddr[9]} {axi_imem_araddr[10]} {axi_imem_araddr[11]} {axi_imem_araddr[12]} {axi_imem_araddr[13]} {axi_imem_araddr[14]} {axi_imem_araddr[15]} {axi_imem_araddr[16]} {axi_imem_araddr[17]} {axi_imem_araddr[18]} {axi_imem_araddr[19]} {axi_imem_araddr[20]} {axi_imem_araddr[21]} {axi_imem_araddr[22]} {axi_imem_araddr[23]} {axi_imem_araddr[24]} {axi_imem_araddr[25]} {axi_imem_araddr[26]} {axi_imem_araddr[27]} {axi_imem_araddr[28]} {axi_imem_araddr[29]} {axi_imem_araddr[30]} {axi_imem_araddr[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 1 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {axi_imem_arvalid}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {axi_imem_arready}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 8 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {axi_imem_arlen[0]} {axi_imem_arlen[1]} {axi_imem_arlen[2]} {axi_imem_arlen[3]} {axi_imem_arlen[4]} {axi_imem_arlen[5]} {axi_imem_arlen[6]} {axi_imem_arlen[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 32 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {axi_imem_rdata[0]} {axi_imem_rdata[1]} {axi_imem_rdata[2]} {axi_imem_rdata[3]} {axi_imem_rdata[4]} {axi_imem_rdata[5]} {axi_imem_rdata[6]} {axi_imem_rdata[7]} {axi_imem_rdata[8]} {axi_imem_rdata[9]} {axi_imem_rdata[10]} {axi_imem_rdata[11]} {axi_imem_rdata[12]} {axi_imem_rdata[13]} {axi_imem_rdata[14]} {axi_imem_rdata[15]} {axi_imem_rdata[16]} {axi_imem_rdata[17]} {axi_imem_rdata[18]} {axi_imem_rdata[19]} {axi_imem_rdata[20]} {axi_imem_rdata[21]} {axi_imem_rdata[22]} {axi_imem_rdata[23]} {axi_imem_rdata[24]} {axi_imem_rdata[25]} {axi_imem_rdata[26]} {axi_imem_rdata[27]} {axi_imem_rdata[28]} {axi_imem_rdata[29]} {axi_imem_rdata[30]} {axi_imem_rdata[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {axi_imem_rvalid}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 1 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {axi_imem_rready}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 1 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {axi_imem_rlast}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 2 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {axi_imem_rresp[0]} {axi_imem_rresp[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 32 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list {axi_dmem_awaddr[0]} {axi_dmem_awaddr[1]} {axi_dmem_awaddr[2]} {axi_dmem_awaddr[3]} {axi_dmem_awaddr[4]} {axi_dmem_awaddr[5]} {axi_dmem_awaddr[6]} {axi_dmem_awaddr[7]} {axi_dmem_awaddr[8]} {axi_dmem_awaddr[9]} {axi_dmem_awaddr[10]} {axi_dmem_awaddr[11]} {axi_dmem_awaddr[12]} {axi_dmem_awaddr[13]} {axi_dmem_awaddr[14]} {axi_dmem_awaddr[15]} {axi_dmem_awaddr[16]} {axi_dmem_awaddr[17]} {axi_dmem_awaddr[18]} {axi_dmem_awaddr[19]} {axi_dmem_awaddr[20]} {axi_dmem_awaddr[21]} {axi_dmem_awaddr[22]} {axi_dmem_awaddr[23]} {axi_dmem_awaddr[24]} {axi_dmem_awaddr[25]} {axi_dmem_awaddr[26]} {axi_dmem_awaddr[27]} {axi_dmem_awaddr[28]} {axi_dmem_awaddr[29]} {axi_dmem_awaddr[30]} {axi_dmem_awaddr[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list {axi_dmem_awvalid}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list {axi_dmem_awready}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 32 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list {axi_dmem_wdata[0]} {axi_dmem_wdata[1]} {axi_dmem_wdata[2]} {axi_dmem_wdata[3]} {axi_dmem_wdata[4]} {axi_dmem_wdata[5]} {axi_dmem_wdata[6]} {axi_dmem_wdata[7]} {axi_dmem_wdata[8]} {axi_dmem_wdata[9]} {axi_dmem_wdata[10]} {axi_dmem_wdata[11]} {axi_dmem_wdata[12]} {axi_dmem_wdata[13]} {axi_dmem_wdata[14]} {axi_dmem_wdata[15]} {axi_dmem_wdata[16]} {axi_dmem_wdata[17]} {axi_dmem_wdata[18]} {axi_dmem_wdata[19]} {axi_dmem_wdata[20]} {axi_dmem_wdata[21]} {axi_dmem_wdata[22]} {axi_dmem_wdata[23]} {axi_dmem_wdata[24]} {axi_dmem_wdata[25]} {axi_dmem_wdata[26]} {axi_dmem_wdata[27]} {axi_dmem_wdata[28]} {axi_dmem_wdata[29]} {axi_dmem_wdata[30]} {axi_dmem_wdata[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 4 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list {axi_dmem_wstrb[0]} {axi_dmem_wstrb[1]} {axi_dmem_wstrb[2]} {axi_dmem_wstrb[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 1 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list {axi_dmem_wvalid}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 1 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list {axi_dmem_wlast}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe16]
set_property port_width 1 [get_debug_ports u_ila_0/probe16]
connect_debug_port u_ila_0/probe16 [get_nets [list {axi_dmem_bvalid}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe17]
set_property port_width 32 [get_debug_ports u_ila_0/probe17]
connect_debug_port u_ila_0/probe17 [get_nets [list {axi_dmem_araddr[0]} {axi_dmem_araddr[1]} {axi_dmem_araddr[2]} {axi_dmem_araddr[3]} {axi_dmem_araddr[4]} {axi_dmem_araddr[5]} {axi_dmem_araddr[6]} {axi_dmem_araddr[7]} {axi_dmem_araddr[8]} {axi_dmem_araddr[9]} {axi_dmem_araddr[10]} {axi_dmem_araddr[11]} {axi_dmem_araddr[12]} {axi_dmem_araddr[13]} {axi_dmem_araddr[14]} {axi_dmem_araddr[15]} {axi_dmem_araddr[16]} {axi_dmem_araddr[17]} {axi_dmem_araddr[18]} {axi_dmem_araddr[19]} {axi_dmem_araddr[20]} {axi_dmem_araddr[21]} {axi_dmem_araddr[22]} {axi_dmem_araddr[23]} {axi_dmem_araddr[24]} {axi_dmem_araddr[25]} {axi_dmem_araddr[26]} {axi_dmem_araddr[27]} {axi_dmem_araddr[28]} {axi_dmem_araddr[29]} {axi_dmem_araddr[30]} {axi_dmem_araddr[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe18]
set_property port_width 1 [get_debug_ports u_ila_0/probe18]
connect_debug_port u_ila_0/probe18 [get_nets [list {axi_dmem_arvalid}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe19]
set_property port_width 32 [get_debug_ports u_ila_0/probe19]
connect_debug_port u_ila_0/probe19 [get_nets [list {axi_dmem_rdata[0]} {axi_dmem_rdata[1]} {axi_dmem_rdata[2]} {axi_dmem_rdata[3]} {axi_dmem_rdata[4]} {axi_dmem_rdata[5]} {axi_dmem_rdata[6]} {axi_dmem_rdata[7]} {axi_dmem_rdata[8]} {axi_dmem_rdata[9]} {axi_dmem_rdata[10]} {axi_dmem_rdata[11]} {axi_dmem_rdata[12]} {axi_dmem_rdata[13]} {axi_dmem_rdata[14]} {axi_dmem_rdata[15]} {axi_dmem_rdata[16]} {axi_dmem_rdata[17]} {axi_dmem_rdata[18]} {axi_dmem_rdata[19]} {axi_dmem_rdata[20]} {axi_dmem_rdata[21]} {axi_dmem_rdata[22]} {axi_dmem_rdata[23]} {axi_dmem_rdata[24]} {axi_dmem_rdata[25]} {axi_dmem_rdata[26]} {axi_dmem_rdata[27]} {axi_dmem_rdata[28]} {axi_dmem_rdata[29]} {axi_dmem_rdata[30]} {axi_dmem_rdata[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe20]
set_property port_width 1 [get_debug_ports u_ila_0/probe20]
connect_debug_port u_ila_0/probe20 [get_nets [list {axi_dmem_rvalid}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe21]
set_property port_width 1 [get_debug_ports u_ila_0/probe21]
connect_debug_port u_ila_0/probe21 [get_nets [list {uart_rxd}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe22]
set_property port_width 1 [get_debug_ports u_ila_0/probe22]
connect_debug_port u_ila_0/probe22 [get_nets [list {uart_txd}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe23]
set_property port_width 1 [get_debug_ports u_ila_0/probe23]
connect_debug_port u_ila_0/probe23 [get_nets [list {uart_irq}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe24]
set_property port_width 32 [get_debug_ports u_ila_0/probe24]
connect_debug_port u_ila_0/probe24 [get_nets [list {i_scr1/tcm_dmem_addr[0]} {i_scr1/tcm_dmem_addr[1]} {i_scr1/tcm_dmem_addr[2]} {i_scr1/tcm_dmem_addr[3]} {i_scr1/tcm_dmem_addr[4]} {i_scr1/tcm_dmem_addr[5]} {i_scr1/tcm_dmem_addr[6]} {i_scr1/tcm_dmem_addr[7]} {i_scr1/tcm_dmem_addr[8]} {i_scr1/tcm_dmem_addr[9]} {i_scr1/tcm_dmem_addr[10]} {i_scr1/tcm_dmem_addr[11]} {i_scr1/tcm_dmem_addr[12]} {i_scr1/tcm_dmem_addr[13]} {i_scr1/tcm_dmem_addr[14]} {i_scr1/tcm_dmem_addr[15]} {i_scr1/tcm_dmem_addr[16]} {i_scr1/tcm_dmem_addr[17]} {i_scr1/tcm_dmem_addr[18]} {i_scr1/tcm_dmem_addr[19]} {i_scr1/tcm_dmem_addr[20]} {i_scr1/tcm_dmem_addr[21]} {i_scr1/tcm_dmem_addr[22]} {i_scr1/tcm_dmem_addr[23]} {i_scr1/tcm_dmem_addr[24]} {i_scr1/tcm_dmem_addr[25]} {i_scr1/tcm_dmem_addr[26]} {i_scr1/tcm_dmem_addr[27]} {i_scr1/tcm_dmem_addr[28]} {i_scr1/tcm_dmem_addr[29]} {i_scr1/tcm_dmem_addr[30]} {i_scr1/tcm_dmem_addr[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe25]
set_property port_width 32 [get_debug_ports u_ila_0/probe25]
connect_debug_port u_ila_0/probe25 [get_nets [list {i_scr1/tcm_dmem_wdata[0]} {i_scr1/tcm_dmem_wdata[1]} {i_scr1/tcm_dmem_wdata[2]} {i_scr1/tcm_dmem_wdata[3]} {i_scr1/tcm_dmem_wdata[4]} {i_scr1/tcm_dmem_wdata[5]} {i_scr1/tcm_dmem_wdata[6]} {i_scr1/tcm_dmem_wdata[7]} {i_scr1/tcm_dmem_wdata[8]} {i_scr1/tcm_dmem_wdata[9]} {i_scr1/tcm_dmem_wdata[10]} {i_scr1/tcm_dmem_wdata[11]} {i_scr1/tcm_dmem_wdata[12]} {i_scr1/tcm_dmem_wdata[13]} {i_scr1/tcm_dmem_wdata[14]} {i_scr1/tcm_dmem_wdata[15]} {i_scr1/tcm_dmem_wdata[16]} {i_scr1/tcm_dmem_wdata[17]} {i_scr1/tcm_dmem_wdata[18]} {i_scr1/tcm_dmem_wdata[19]} {i_scr1/tcm_dmem_wdata[20]} {i_scr1/tcm_dmem_wdata[21]} {i_scr1/tcm_dmem_wdata[22]} {i_scr1/tcm_dmem_wdata[23]} {i_scr1/tcm_dmem_wdata[24]} {i_scr1/tcm_dmem_wdata[25]} {i_scr1/tcm_dmem_wdata[26]} {i_scr1/tcm_dmem_wdata[27]} {i_scr1/tcm_dmem_wdata[28]} {i_scr1/tcm_dmem_wdata[29]} {i_scr1/tcm_dmem_wdata[30]} {i_scr1/tcm_dmem_wdata[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe26]
set_property port_width 1 [get_debug_ports u_ila_0/probe26]
connect_debug_port u_ila_0/probe26 [get_nets [list {i_scr1/tcm_dmem_req}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe27]
set_property port_width 1 [get_debug_ports u_ila_0/probe27]
connect_debug_port u_ila_0/probe27 [get_nets [list {i_scr1/tcm_dmem_req_ack}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe28]
set_property port_width 1 [get_debug_ports u_ila_0/probe28]
connect_debug_port u_ila_0/probe28 [get_nets [list {i_scr1/tcm_dmem_cmd}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe29]
set_property port_width 2 [get_debug_ports u_ila_0/probe29]
connect_debug_port u_ila_0/probe29 [get_nets [list {i_scr1/tcm_dmem_width[0]} {i_scr1/tcm_dmem_width[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe30]
set_property port_width 32 [get_debug_ports u_ila_0/probe30]
connect_debug_port u_ila_0/probe30 [get_nets [list {i_scr1/tcm_imem_addr[0]} {i_scr1/tcm_imem_addr[1]} {i_scr1/tcm_imem_addr[2]} {i_scr1/tcm_imem_addr[3]} {i_scr1/tcm_imem_addr[4]} {i_scr1/tcm_imem_addr[5]} {i_scr1/tcm_imem_addr[6]} {i_scr1/tcm_imem_addr[7]} {i_scr1/tcm_imem_addr[8]} {i_scr1/tcm_imem_addr[9]} {i_scr1/tcm_imem_addr[10]} {i_scr1/tcm_imem_addr[11]} {i_scr1/tcm_imem_addr[12]} {i_scr1/tcm_imem_addr[13]} {i_scr1/tcm_imem_addr[14]} {i_scr1/tcm_imem_addr[15]} {i_scr1/tcm_imem_addr[16]} {i_scr1/tcm_imem_addr[17]} {i_scr1/tcm_imem_addr[18]} {i_scr1/tcm_imem_addr[19]} {i_scr1/tcm_imem_addr[20]} {i_scr1/tcm_imem_addr[21]} {i_scr1/tcm_imem_addr[22]} {i_scr1/tcm_imem_addr[23]} {i_scr1/tcm_imem_addr[24]} {i_scr1/tcm_imem_addr[25]} {i_scr1/tcm_imem_addr[26]} {i_scr1/tcm_imem_addr[27]} {i_scr1/tcm_imem_addr[28]} {i_scr1/tcm_imem_addr[29]} {i_scr1/tcm_imem_addr[30]} {i_scr1/tcm_imem_addr[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe31]
set_property port_width 32 [get_debug_ports u_ila_0/probe31]
connect_debug_port u_ila_0/probe31 [get_nets [list {i_scr1/tcm_imem_rdata[0]} {i_scr1/tcm_imem_rdata[1]} {i_scr1/tcm_imem_rdata[2]} {i_scr1/tcm_imem_rdata[3]} {i_scr1/tcm_imem_rdata[4]} {i_scr1/tcm_imem_rdata[5]} {i_scr1/tcm_imem_rdata[6]} {i_scr1/tcm_imem_rdata[7]} {i_scr1/tcm_imem_rdata[8]} {i_scr1/tcm_imem_rdata[9]} {i_scr1/tcm_imem_rdata[10]} {i_scr1/tcm_imem_rdata[11]} {i_scr1/tcm_imem_rdata[12]} {i_scr1/tcm_imem_rdata[13]} {i_scr1/tcm_imem_rdata[14]} {i_scr1/tcm_imem_rdata[15]} {i_scr1/tcm_imem_rdata[16]} {i_scr1/tcm_imem_rdata[17]} {i_scr1/tcm_imem_rdata[18]} {i_scr1/tcm_imem_rdata[19]} {i_scr1/tcm_imem_rdata[20]} {i_scr1/tcm_imem_rdata[21]} {i_scr1/tcm_imem_rdata[22]} {i_scr1/tcm_imem_rdata[23]} {i_scr1/tcm_imem_rdata[24]} {i_scr1/tcm_imem_rdata[25]} {i_scr1/tcm_imem_rdata[26]} {i_scr1/tcm_imem_rdata[27]} {i_scr1/tcm_imem_rdata[28]} {i_scr1/tcm_imem_rdata[29]} {i_scr1/tcm_imem_rdata[30]} {i_scr1/tcm_imem_rdata[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe32]
set_property port_width 1 [get_debug_ports u_ila_0/probe32]
connect_debug_port u_ila_0/probe32 [get_nets [list {i_scr1/tcm_imem_req}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe33]
set_property port_width 1 [get_debug_ports u_ila_0/probe33]
connect_debug_port u_ila_0/probe33 [get_nets [list {i_scr1/tcm_imem_req_ack}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe34]
set_property port_width 1 [get_debug_ports u_ila_0/probe34]
connect_debug_port u_ila_0/probe34 [get_nets [list {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_actual}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe35]
set_property port_width 1 [get_debug_ports u_ila_0/probe35]
connect_debug_port u_ila_0/probe35 [get_nets [list {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pred}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe36]
set_property port_width 1 [get_debug_ports u_ila_0/probe36]
connect_debug_port u_ila_0/probe36 [get_nets [list {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_mispred}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe37]
set_property port_width 1 [get_debug_ports u_ila_0/probe37]
connect_debug_port u_ila_0/probe37 [get_nets [list {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_brretire}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe38]
set_property port_width 1 [get_debug_ports u_ila_0/probe38]
connect_debug_port u_ila_0/probe38 [get_nets [list {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_redirect}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe39]
set_property port_width 32 [get_debug_ports u_ila_0/probe39]
connect_debug_port u_ila_0/probe39 [get_nets [list {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[0]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[1]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[2]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[3]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[4]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[5]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[6]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[7]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[8]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[9]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[10]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[11]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[12]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[13]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[14]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[15]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[16]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[17]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[18]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[19]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[20]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[21]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[22]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[23]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[24]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[25]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[26]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[27]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[28]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[29]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[30]} {i_scr1/i_core_top/i_pipe_top/i_pipe_exu/bp_dbg_pc[31]}]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets cpu_clk]
