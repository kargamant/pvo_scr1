# =============================================================================
# create_sopc_ps.tcl - COMBINED BD: full Versal PS (boots ALINX PetaLinux) + our
# standalone SCR1 SoC + a PS->PL AXI bridge, on VD100 (xcve2302).
#
# DESIGN PRINCIPLE (memory vd100-keep-both-load-paths): keep BOTH load paths.
#   - Direct: boot-BRAM init (bake-to-BRAM) + JTAG/ILA  -> unchanged, still works.
#   - PS/Linux: M_AXI_LPD -> axi_smc -> {boot BRAM port B, scr1_reset_gpio} so Linux
#     `devmem` writes a test into the boot BRAM and releases SCR1 reset at runtime.
# SCR1 keeps DDR access (shares the DDR MC with the PS via an extra NoC PL port).
#
# Reuses ALINX's exact PS config (the one that boots the SD PetaLinux) verbatim via
# tcl/alinx_ps_config.tcl::set_ps_config, so Linux keeps booting from the new XSA.
#
# Usage (in an OPEN Vivado 2023.2 project on xcve2302-sfva784-1LP-e-s):
#   source tcl/create_sopc_ps.tcl
# Produces BD `alinx_ve2302_sopc` (module name the top's i_soc instance expects).
# =============================================================================

set here [file dirname [file normalize [info script]]]
set bdname alinx_ve2302_sopc
create_bd_design $bdname
current_bd_design $bdname

# ---------------------------------------------------------------------------
# External ports = the `alinx_ve2302_sopc` contract expected by the board top.
# (Same as create_sopc.tcl; adds one PS-controlled SCR1 reset output.)
# ---------------------------------------------------------------------------
set sys  [create_bd_intf_port -mode Slave  -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys]
set_property CONFIG.FREQ_HZ {200000000} $sys
set DDR4 [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 DDR4]

proc _mk_axi_slave {name rw} {
  set p [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 $name]
  set_property -dict [list \
    CONFIG.ADDR_WIDTH {32} CONFIG.DATA_WIDTH {32} CONFIG.ID_WIDTH {4} \
    CONFIG.PROTOCOL {AXI4} CONFIG.HAS_BURST {1} CONFIG.HAS_LOCK {1} \
    CONFIG.HAS_CACHE {1} CONFIG.HAS_PROT {1} CONFIG.HAS_QOS {1} CONFIG.HAS_REGION {0} \
    CONFIG.HAS_WSTRB {1} CONFIG.HAS_BRESP {1} CONFIG.HAS_RRESP {1} \
    CONFIG.READ_WRITE_MODE $rw CONFIG.MAX_BURST_LENGTH {256} \
    CONFIG.NUM_READ_OUTSTANDING {2} CONFIG.NUM_WRITE_OUTSTANDING {2} \
  ] $p
  return $p
}
_mk_axi_slave axi_imem READ_ONLY
_mk_axi_slave axi_dmem READ_WRITE

create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 uart
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0  soc_id
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0  bld_id
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0  core_clk_freq

create_bd_port -dir O -type clk cpu_clk_o
set_property -dict [list CONFIG.ASSOCIATED_BUSIF {axi_imem:axi_dmem} \
                         CONFIG.ASSOCIATED_RESET {pwrup_rst_n_o}] [get_bd_ports cpu_clk_o]
create_bd_port -dir O -type rst cpu_reset_o
create_bd_port -dir O          pwrup_rst_n_o
create_bd_port -dir I -type rst soc_rst_n
create_bd_port -dir O          ddr_init_complete
# NEW: PS-controlled SCR1 reset request (active-low). Top ANDs this into soc_rst_n so
# Linux can hold SCR1 in reset (write 0), load a test, then release (write 1). Default
# high (deasserted) via the gpio dout default so a bare boot doesn't wedge SCR1.
create_bd_port -dir O          scr1_pl_rst_n_o

# ---------------------------------------------------------------------------
# CIPS - FULL PS config, verbatim from ALINX course_s2 (boots the SD PetaLinux).
# ---------------------------------------------------------------------------
set cips [create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:3.4 versal_cips_0]
source $here/alinx_ps_config.tcl
set_ps_config versal_cips_0

# ---------------------------------------------------------------------------
# NoC + DDRMC (DDR4). PS ports S00-S05 (ps_cci x4, ps_rpu, ps_pmc) verbatim from
# ALINX; PLUS S06 = our SCR1 (pl) so SCR1 shares the DDR MC. MC config from ALINX.
# ---------------------------------------------------------------------------
set noc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.0 axi_noc_0]
set_property -dict [list \
  CONFIG.CONTROLLERTYPE {DDR4_SDRAM} \
  CONFIG.MC_CASLATENCY {22} \
  CONFIG.MC_CHAN_REGION1 {NONE} \
  CONFIG.MC_COMPONENT_WIDTH {x16} \
  CONFIG.MC_INPUTCLK0_PERIOD {5000} \
  CONFIG.MC_MEMORY_SPEEDGRADE {DDR4-3200AA(22-22-22)} \
  CONFIG.MC_SYSTEM_CLOCK {No_Buffer} \
  CONFIG.MC_USER_DEFINED_ADDRESS_MAP {16RA-2BA-1BG-10CA} \
  CONFIG.NUM_CLKS {7} \
  CONFIG.NUM_MC {1} \
  CONFIG.NUM_MCP {4} \
  CONFIG.NUM_MI {0} \
  CONFIG.NUM_SI {7} \
] $noc
# PS DDR ports (categories/MC mapping verbatim from ALINX course_s2 pl_config).
set_property -dict [list CONFIG.REGION {0} CONFIG.CONNECTIONS {MC_3 {read_bw {4096} write_bw {4096} read_avg_burst {4} write_avg_burst {4}}} CONFIG.NOC_PARAMS {} CONFIG.CATEGORY {ps_cci}] [get_bd_intf_pins /axi_noc_0/S00_AXI]
set_property -dict [list CONFIG.REGION {0} CONFIG.CONNECTIONS {MC_2 {read_bw {4096} write_bw {4096} read_avg_burst {4} write_avg_burst {4}}} CONFIG.NOC_PARAMS {} CONFIG.CATEGORY {ps_cci}] [get_bd_intf_pins /axi_noc_0/S01_AXI]
set_property -dict [list CONFIG.REGION {0} CONFIG.CONNECTIONS {MC_0 {read_bw {4096} write_bw {4096} read_avg_burst {4} write_avg_burst {4}}} CONFIG.NOC_PARAMS {} CONFIG.CATEGORY {ps_cci}] [get_bd_intf_pins /axi_noc_0/S02_AXI]
set_property -dict [list CONFIG.REGION {0} CONFIG.CONNECTIONS {MC_1 {read_bw {4096} write_bw {4096} read_avg_burst {4} write_avg_burst {4}}} CONFIG.NOC_PARAMS {} CONFIG.CATEGORY {ps_cci}] [get_bd_intf_pins /axi_noc_0/S03_AXI]
set_property -dict [list CONFIG.REGION {0} CONFIG.CONNECTIONS {MC_3 {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}}} CONFIG.NOC_PARAMS {} CONFIG.CATEGORY {ps_rpu}] [get_bd_intf_pins /axi_noc_0/S04_AXI]
set_property -dict [list CONFIG.REGION {0} CONFIG.CONNECTIONS {MC_2 {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}}} CONFIG.NOC_PARAMS {} CONFIG.CATEGORY {ps_pmc}] [get_bd_intf_pins /axi_noc_0/S05_AXI]
# S06 = SCR1 (via its smartconnect) -> DDR (pl category).
set_property -dict [list CONFIG.CONNECTIONS {MC_0 {read_bw {1000} write_bw {1000} read_avg_burst {4} write_avg_burst {4}}} CONFIG.NOC_PARAMS {} CONFIG.CATEGORY {pl}] [get_bd_intf_pins /axi_noc_0/S06_AXI]
foreach {i b} {0 S00_AXI 1 S01_AXI 2 S02_AXI 3 S03_AXI 4 S04_AXI 5 S05_AXI 6 S06_AXI} {
  set_property CONFIG.ASSOCIATED_BUSIF $b [get_bd_pins /axi_noc_0/aclk$i]
}

# ---------------------------------------------------------------------------
# PL clock (clk_wizard) + input diff buffer. clk_out1 = 90 MHz = cpu_clk (SCR1 +
# peripherals + PS bridge). NoC MC ref = sys via util_ds_buf.
# ---------------------------------------------------------------------------
set clkw [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 clk_wizard_0]
set_property -dict [list \
  CONFIG.CLKOUT_DRIVES {BUFG,BUFG,BUFG,BUFG,BUFG,BUFG,BUFG} \
  CONFIG.CLKOUT_USED {true,false,false,false,false,false,false} \
  CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {80.000,100.000,100.000,100.000,100.000,100.000,100.000} \
] $clkw
set dsbuf [create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 util_ds_buf_0]
set psr   [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]

# ---------------------------------------------------------------------------
# SCR1-side peripherals (unchanged from create_sopc.tcl).
# ---------------------------------------------------------------------------
set sc   [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {6}] $sc

set uart [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uart16550:2.0 uart]
set_property -dict [list CONFIG.C_S_AXI_ACLK_FREQ_HZ {80000000} \
                         CONFIG.UART_BOARD_INTERFACE {Custom}] $uart

proc _mk_gpio_in {name width dflt} {
  set g [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 $name]
  set_property -dict [list CONFIG.C_GPIO_WIDTH $width CONFIG.C_ALL_INPUTS {1} \
                           CONFIG.C_DOUT_DEFAULT $dflt] $g
  return $g
}
_mk_gpio_in soc_id_gpio        32 {0x00000000}
_mk_gpio_in bld_id_gpio        32 {0x00000000}
_mk_gpio_in core_clk_freq_gpio 32 {0x00000000}

# Boot BRAM = TRUE DUAL PORT: port A = SCR1 (bram_ctrl), port B = PS (bram_ctrl_ps).
set bramc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 bram_ctrl]
set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1} CONFIG.DATA_WIDTH {32}] $bramc
set bram  [create_bd_cell -type ip -vlnv xilinx.com:ip:emb_mem_gen:1.0 emb_mem_gen_0]
set_property -dict [list CONFIG.MEMORY_TYPE {True_Dual_Port_RAM}] $bram
set_property CONFIG.MEMORY_INIT_FILE {/home/toast/pvo_scr1/fpga/alinx_ve2302/scr1/mem/scbl.coe} $bram

# ---------------------------------------------------------------------------
# PS->PL bridge: M_AXI_LPD -> axi_smc -> { bram_ctrl_ps (boot BRAM port B), scr1_reset_gpio }.
# ---------------------------------------------------------------------------
set smcps [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $smcps
set bramcps [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 bram_ctrl_ps]
set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1} CONFIG.DATA_WIDTH {32}] $bramcps
# scr1_reset_gpio: OUTPUT gpio, 1 bit, default 1 (SCR1 not held in reset by default).
set rstgpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 scr1_reset_gpio]
set_property -dict [list CONFIG.C_GPIO_WIDTH {1} CONFIG.C_ALL_INPUTS {0} \
                         CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_DOUT_DEFAULT {0x00000001}] $rstgpio

# ---------------------------------------------------------------------------
# Clock / reset wiring.
# ---------------------------------------------------------------------------
connect_bd_intf_net [get_bd_intf_ports sys] [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]
connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins clk_wizard_0/clk_in1] [get_bd_pins axi_noc_0/sys_clk0]
# cpu_clk (90 MHz) domain: SCR1 slaves, peripherals, both smartconnects, PS bridge, NoC aclk6.
set cpuclk [get_bd_pins clk_wizard_0/clk_out1]
connect_bd_net $cpuclk [get_bd_pins proc_sys_reset_0/slowest_sync_clk] [get_bd_ports cpu_clk_o] \
                       [get_bd_pins axi_noc_0/aclk6]
# NoC PS-side clocks from CIPS.
connect_bd_net [get_bd_pins versal_cips_0/fpd_cci_noc_axi0_clk] [get_bd_pins axi_noc_0/aclk0]
connect_bd_net [get_bd_pins versal_cips_0/fpd_cci_noc_axi1_clk] [get_bd_pins axi_noc_0/aclk1]
connect_bd_net [get_bd_pins versal_cips_0/fpd_cci_noc_axi2_clk] [get_bd_pins axi_noc_0/aclk2]
connect_bd_net [get_bd_pins versal_cips_0/fpd_cci_noc_axi3_clk] [get_bd_pins axi_noc_0/aclk3]
connect_bd_net [get_bd_pins versal_cips_0/lpd_axi_noc_clk]      [get_bd_pins axi_noc_0/aclk4]
connect_bd_net [get_bd_pins versal_cips_0/pmc_axi_noc_axi0_clk] [get_bd_pins axi_noc_0/aclk5]
connect_bd_net [get_bd_pins versal_cips_0/m_axi_lpd_aclk]       $cpuclk
# proc_sys_reset from CIPS pl0_resetn.
connect_bd_net [get_bd_pins versal_cips_0/pl0_resetn] [get_bd_pins proc_sys_reset_0/ext_reset_in]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_ports pwrup_rst_n_o]
connect_bd_net [get_bd_pins proc_sys_reset_0/mb_reset]           [get_bd_ports cpu_reset_o]

# DDR4 physical.
connect_bd_intf_net [get_bd_intf_ports DDR4] [get_bd_intf_pins axi_noc_0/CH0_DDR4_0]

# CIPS -> NoC (PS DDR path).
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/FPD_CCI_NOC_0] [get_bd_intf_pins axi_noc_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/FPD_CCI_NOC_1] [get_bd_intf_pins axi_noc_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/FPD_CCI_NOC_2] [get_bd_intf_pins axi_noc_0/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/FPD_CCI_NOC_3] [get_bd_intf_pins axi_noc_0/S03_AXI]
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/LPD_AXI_NOC_0] [get_bd_intf_pins axi_noc_0/S04_AXI]
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/PMC_NOC_AXI_0] [get_bd_intf_pins axi_noc_0/S05_AXI]

# ---------------------------------------------------------------------------
# SCR1 AXI fabric: imem+dmem -> smartconnect_0 -> {NoC(DDR) S06, gpio x3, boot BRAM A, uart}.
# ---------------------------------------------------------------------------
connect_bd_intf_net [get_bd_intf_ports axi_imem] [get_bd_intf_pins smartconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_ports axi_dmem] [get_bd_intf_pins smartconnect_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins axi_noc_0/S06_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M01_AXI] [get_bd_intf_pins soc_id_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M02_AXI] [get_bd_intf_pins bld_id_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M03_AXI] [get_bd_intf_pins core_clk_freq_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M04_AXI] [get_bd_intf_pins bram_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M05_AXI] [get_bd_intf_pins uart/S_AXI]
connect_bd_intf_net [get_bd_intf_pins bram_ctrl/BRAM_PORTA]   [get_bd_intf_pins emb_mem_gen_0/BRAM_PORTA]

# PS bridge fabric.
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/M_AXI_LPD] [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins bram_ctrl_ps/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M01_AXI] [get_bd_intf_pins scr1_reset_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins bram_ctrl_ps/BRAM_PORTA] [get_bd_intf_pins emb_mem_gen_0/BRAM_PORTB]

# Peripheral external interfaces.
connect_bd_intf_net [get_bd_intf_pins soc_id_gpio/GPIO]        [get_bd_intf_ports soc_id]
connect_bd_intf_net [get_bd_intf_pins bld_id_gpio/GPIO]        [get_bd_intf_ports bld_id]
connect_bd_intf_net [get_bd_intf_pins core_clk_freq_gpio/GPIO] [get_bd_intf_ports core_clk_freq]
connect_bd_intf_net [get_bd_intf_pins uart/UART]               [get_bd_intf_ports uart]
# scr1_reset_gpio single-bit output -> BD port (top ANDs into soc_rst_n).
connect_bd_net [get_bd_pins scr1_reset_gpio/gpio_io_o] [get_bd_ports scr1_pl_rst_n_o]

# cpu_clk to all cpu-domain AXI blocks.
foreach c {smartconnect_0/aclk soc_id_gpio/s_axi_aclk bld_id_gpio/s_axi_aclk \
           core_clk_freq_gpio/s_axi_aclk bram_ctrl/s_axi_aclk uart/s_axi_aclk \
           axi_smc/aclk bram_ctrl_ps/s_axi_aclk scr1_reset_gpio/s_axi_aclk} {
  connect_bd_net $cpuclk [get_bd_pins $c]
}
foreach r {smartconnect_0/aresetn soc_id_gpio/s_axi_aresetn bld_id_gpio/s_axi_aresetn \
           core_clk_freq_gpio/s_axi_aresetn bram_ctrl/s_axi_aresetn uart/s_axi_aresetn \
           axi_smc/aresetn bram_ctrl_ps/s_axi_aresetn scr1_reset_gpio/s_axi_aresetn} {
  connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins $r]
}

# ddr_init_complete: tie high (PMC calibrates DDR during PDI boot).
set vcc [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_1]
connect_bd_net [get_bd_pins xlconstant_1/dout] [get_bd_ports ddr_init_complete]

# ---------------------------------------------------------------------------
# Address maps.
# ---------------------------------------------------------------------------
# SCR1 space (imem & dmem): DDR + peripherals + boot BRAM (unchanged).
foreach space {axi_imem axi_dmem} {
  # SCR1 DDR window = identity map of the full 2GB low DDR so SCR1 can reach the region
  # reserved from Linux (top 256MB @0x70000000; Linux booted with mem=1792M). PS loads DDR
  # programs there via /dev/mem (RAM -> write()/dd works, fast). See tools/README.md.
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs axi_noc_0/S06_AXI/C0_DDR_LOW0] -force
  assign_bd_address -offset 0xFF000000 -range 0x00001000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs soc_id_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0xFF001000 -range 0x00001000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs bld_id_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0xFF002000 -range 0x00001000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs core_clk_freq_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0xFF010000 -range 0x00001000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs uart/S_AXI/Reg] -force
  assign_bd_address -offset 0xFFFF0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs bram_ctrl/S_AXI/Mem0] -force
}
# PS M_AXI_LPD space: boot BRAM (port B) @0x80100000, scr1_reset_gpio @0x80200000.
assign_bd_address -offset 0x80100000 -range 0x00010000 -target_address_space [get_bd_addr_spaces versal_cips_0/M_AXI_LPD] [get_bd_addr_segs bram_ctrl_ps/S_AXI/Mem0] -force
assign_bd_address -offset 0x80200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces versal_cips_0/M_AXI_LPD] [get_bd_addr_segs scr1_reset_gpio/S_AXI/Reg] -force
# PS DDR (FPD/LPD/PMC -> NoC) : offset 0x0, range 0x80000000 (matches ALINX).
foreach {sp seg} {FPD_CCI_NOC_0 S00_AXI/C3_DDR_LOW0 FPD_CCI_NOC_1 S01_AXI/C2_DDR_LOW0 \
                  FPD_CCI_NOC_2 S02_AXI/C0_DDR_LOW0 FPD_CCI_NOC_3 S03_AXI/C1_DDR_LOW0 \
                  LPD_AXI_NOC_0 S04_AXI/C3_DDR_LOW0 PMC_NOC_AXI_0 S05_AXI/C2_DDR_LOW0} {
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces versal_cips_0/$sp] [get_bd_addr_segs axi_noc_0/$seg] -force
}

regenerate_bd_layout
validate_bd_design
# Re-apply boot image AFTER validate (axi_bram_ctrl propagation resets emb_mem_gen init).
set_property CONFIG.MEMORY_INIT_FILE {/home/toast/pvo_scr1/fpga/alinx_ve2302/scr1/mem/scbl.coe} [get_bd_cells emb_mem_gen_0]
save_bd_design
puts "CREATE_SOPC_PS: done"
