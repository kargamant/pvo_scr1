# =============================================================================
# create_sopc.tcl - build the `alinx_ve2302_sopc` block design for VD100 (Versal
# AI Edge XCVE2302). Port of the Nexys4DDR `nexys4ddr_sopc` BD:
#   mig_7series + clk_wiz + axi_clock_converter  ->  versal_cips + axi_noc + clk_wizard
# Peripherals (uart16550, axi_gpio x3, boot BRAM, smartconnect, proc_sys_reset) are
# carried over unchanged. VGA/PS2 are omitted (stage 1).
#
# CIPS/NoC/clk skeleton adapted from ALINX VD100 02_pl_rw_ddr reference
# (Demo/course_s1/02_pl_rw_ddr/auto_create_project/{pl_config,ps_config}.tcl).
#
# Usage (in an OPEN Vivado project targeting xcve2302-sfva784-1LP-e-s):
#   source create_sopc.tcl
# Produces BD `alinx_ve2302_sopc` (module name matches the top's i_soc instance).
#
# STATUS: first authored version - MUST be validated (validate_bd_design) on
# Vivado 2023.2 and address-mapped before build. See memory scr1-versal-vd100-port.
# =============================================================================

set bdname alinx_ve2302_sopc
create_bd_design $bdname
current_bd_design $bdname

# ---------------------------------------------------------------------------
# External interface/ports = the `alinx_ve2302_sopc` contract expected by the top
# (fpga/alinx_ve2302/scr1/src/alinx_ve2302_scr1.sv i_soc instance).
# ---------------------------------------------------------------------------
# 200 MHz DDR reference (differential) + physical DDR4 (owned by the BD).
set sys  [create_bd_intf_port -mode Slave  -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys]
set_property CONFIG.FREQ_HZ {200000000} $sys
set DDR4 [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 DDR4]

# SCR1 memory masters (slaves here): 32-bit AXI4. imem = read-only path.
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

# Peripheral-facing external interface ports (to top-level pins).
# UART: PL axi_uart16550 @ 0xFF010000 - the SAME register map the prebuilt scbl bootloader
# (scbl.mem) expects, so scbl works unchanged. On VD100 the board USB-UART is wired to the
# PS (MIO), not PL, so this PL UART is routed to PMOD J55 (3.3 V HDIO) for an external
# USB-TTL adapter. sin/sout only; scbl polls (UART IRQ unused).
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 uart
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0  soc_id
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0  bld_id
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0  core_clk_freq

# Clocks/resets/status scalar ports (match i_soc contract).
create_bd_port -dir O -type clk cpu_clk_o
# SCR1 drives axi_imem/axi_dmem on this exported clock; declare the association so the
# smartconnect and BD infer a single common clock domain for the external slave ports.
set_property -dict [list CONFIG.ASSOCIATED_BUSIF {axi_imem:axi_dmem} \
                         CONFIG.ASSOCIATED_RESET {pwrup_rst_n_o}] [get_bd_ports cpu_clk_o]
create_bd_port -dir O -type rst cpu_reset_o
create_bd_port -dir O          pwrup_rst_n_o
create_bd_port -dir I -type rst soc_rst_n
create_bd_port -dir O          ddr_init_complete
# SCR1 debug/observation on Versal is via mark_debug -> auto-inserted axi_dbg_hub -> CIPS
# HSDP -> device JTAG (the ALINX-idiomatic path; no manual BSCAN/debug_bridge). Program
# load is via .coe boot-BRAM init. So no PL JTAG-master ports are exported here.

# ---------------------------------------------------------------------------
# CIPS (clock/reset source; PL-only DESIGN_MODE=0) - from ALINX ps_config.tcl
# ---------------------------------------------------------------------------
set cips [create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:3.4 versal_cips_0]
set_property -dict [list \
  CONFIG.DESIGN_MODE {0} \
  CONFIG.PS_PMC_CONFIG { \
    DESIGN_MODE {0} \
    PS_BOARD_INTERFACE {Custom} \
    PS_NUM_FABRIC_RESETS {1} \
    SMON_ALARMS {Set_Alarms_On} \
    SMON_ENABLE_TEMP_AVERAGING {0} \
    SMON_TEMP_AVERAGING_SAMPLES {0} \
  } \
] $cips

# ---------------------------------------------------------------------------
# NoC + hard DDRMC (DDR4) - from ALINX pl_config.tcl. One MC, one PL slave port
# (S00) fed by the PL smartconnect; DDR at 0x0.
# ---------------------------------------------------------------------------
set noc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.0 axi_noc_0]
set_property -dict [list \
  CONFIG.MC_COMPONENT_WIDTH {x16} \
  CONFIG.MC_INPUTCLK0_PERIOD {5000} \
  CONFIG.MC_MEMORY_SPEEDGRADE {DDR4-3200AA(22-22-22)} \
  CONFIG.MC_SYSTEM_CLOCK {No_Buffer} \
  CONFIG.NUM_MC {1} \
  CONFIG.NUM_MI {0} \
  CONFIG.NUM_SI {1} \
] $noc
set_property -dict [list \
  CONFIG.CONNECTIONS {MC_0 {read_bw {1000} write_bw {1000} read_avg_burst {4} write_avg_burst {4}}} \
  CONFIG.CATEGORY {pl} \
] [get_bd_intf_pins /axi_noc_0/S00_AXI]
set_property CONFIG.ASSOCIATED_BUSIF {S00_AXI} [get_bd_pins /axi_noc_0/aclk0]

# ---------------------------------------------------------------------------
# PL clock (clk_wizard) + input diff buffer, from ALINX pl_config.tcl.
# clk_out1 provisional 100 MHz (1LP silicon; retune after first impl, then set
# SCR1_PTFM_CORE_CLK_FREQ to match). Single clock domain for the whole SoPC.
# ---------------------------------------------------------------------------
set clkw [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 clk_wizard_0]
set_property -dict [list \
  CONFIG.CLKOUT_DRIVES {BUFG,BUFG,BUFG,BUFG,BUFG,BUFG,BUFG} \
  CONFIG.CLKOUT_USED {true,false,false,false,false,false,false} \
  CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {90.000,100.000,100.000,100.000,100.000,100.000,100.000} \
] $clkw
set dsbuf [create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 util_ds_buf_0]
set psr   [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]

# ---------------------------------------------------------------------------
# Peripherals carried from the Nexys SoPC (unchanged IP).
# ---------------------------------------------------------------------------
set sc   [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {6}] $sc

# UART 16550 (@0xFF010000). ACLK freq must match the actual AXI clock (90 MHz) so the
# baud generator divides correctly; scbl reads core_clk_freq GPIO (=90 MHz) to pick the
# same divisor -> ~117187 baud vs host 115200 (~1.7% error, same as Nexys@30 MHz).
set uart [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uart16550:2.0 uart]
set_property -dict [list CONFIG.C_S_AXI_ACLK_FREQ_HZ {90000000} \
                         CONFIG.UART_BOARD_INTERFACE {Custom}] $uart

# NOTE: on Versal, debug cores (ILA/dbg_hub) are NOT instantiated as BD IP (system_ila,
# jtag_axi, debug_bridge are all unsupported for this part). Instead mark_debug is placed on
# RTL nets (here: imem/dmem AXI in the board top) and Vivado auto-inserts the axi_dbg_hub +
# ILA during synthesis, reachable over the device JTAG. See alinx_ve2302_scr1.sv.

proc _mk_gpio {name width dflt} {
  set g [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 $name]
  set_property -dict [list CONFIG.C_GPIO_WIDTH $width CONFIG.C_ALL_INPUTS {1} \
                           CONFIG.C_DOUT_DEFAULT $dflt] $g
  return $g
}
_mk_gpio soc_id_gpio        32 {0x00000000}
_mk_gpio bld_id_gpio        32 {0x00000000}
_mk_gpio core_clk_freq_gpio 32 {0x00000000}

set bramc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 bram_ctrl]
set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1} CONFIG.DATA_WIDTH {32}] $bramc
# Versal uses emb_mem_gen (not blk_mem_gen) as the fabric memory generator.
set bram  [create_bd_cell -type ip -vlnv xilinx.com:ip:emb_mem_gen:1.0 emb_mem_gen_0]
# Boot BRAM init: SCR1 bootloader image scbl.coe (16384 x 32b = 64 KB @ 0xFFFF0000,
# RST_VECTOR 0xFFFFFF00), generated from fpga/nexys4ddr/scr1/scbl.mem. Absolute path so
# standalone validate finds it; in the real project add mem/scbl.coe as a source and use
# the bare filename instead.
set_property CONFIG.MEMORY_INIT_FILE [file normalize [file join [file dirname [info script]] .. mem scbl.coe]] $bram

# ---------------------------------------------------------------------------
# Clock/reset wiring (from ALINX pl_config.tcl).
# ---------------------------------------------------------------------------
connect_bd_intf_net [get_bd_intf_ports sys]       [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]
connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins clk_wizard_0/clk_in1] [get_bd_pins axi_noc_0/sys_clk0]
connect_bd_net [get_bd_pins clk_wizard_0/clk_out1]  [get_bd_pins axi_noc_0/aclk0] \
               [get_bd_pins proc_sys_reset_0/slowest_sync_clk] [get_bd_ports cpu_clk_o]
connect_bd_net [get_bd_pins versal_cips_0/pl0_resetn] [get_bd_pins proc_sys_reset_0/ext_reset_in]
# CIPS also drives cpu_clk in the ALINX flow via pl0_ref_clk; here clk_wizard is the
# clock source. If pl0_ref_clk is preferred, swap clk_wizard/clk_out1 for cips/pl0_ref_clk.
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_ports pwrup_rst_n_o]
connect_bd_net [get_bd_pins proc_sys_reset_0/mb_reset]           [get_bd_ports cpu_reset_o]

# DDR4 physical + memory init status.
connect_bd_intf_net [get_bd_intf_ports DDR4] [get_bd_intf_pins axi_noc_0/CH0_DDR4_0]

# ---------------------------------------------------------------------------
# AXI fabric: imem+dmem -> smartconnect -> {NoC(DDR), gpio x3, boot BRAM}  (UART removed)
# ---------------------------------------------------------------------------
connect_bd_intf_net [get_bd_intf_ports axi_imem] [get_bd_intf_pins smartconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_ports axi_dmem] [get_bd_intf_pins smartconnect_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins axi_noc_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M01_AXI] [get_bd_intf_pins soc_id_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M02_AXI] [get_bd_intf_pins bld_id_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M03_AXI] [get_bd_intf_pins core_clk_freq_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M04_AXI] [get_bd_intf_pins bram_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M05_AXI] [get_bd_intf_pins uart/S_AXI]
connect_bd_intf_net [get_bd_intf_pins bram_ctrl/BRAM_PORTA]   [get_bd_intf_pins emb_mem_gen_0/BRAM_PORTA]

# Peripheral external interfaces.
connect_bd_intf_net [get_bd_intf_pins soc_id_gpio/GPIO]        [get_bd_intf_ports soc_id]
connect_bd_intf_net [get_bd_intf_pins bld_id_gpio/GPIO]        [get_bd_intf_ports bld_id]
connect_bd_intf_net [get_bd_intf_pins core_clk_freq_gpio/GPIO] [get_bd_intf_ports core_clk_freq]
connect_bd_intf_net [get_bd_intf_pins uart/UART]               [get_bd_intf_ports uart]

# Common clock/reset to all AXI peripherals (single domain).
foreach c {smartconnect_0/aclk soc_id_gpio/s_axi_aclk \
           bld_id_gpio/s_axi_aclk core_clk_freq_gpio/s_axi_aclk bram_ctrl/s_axi_aclk \
           uart/s_axi_aclk} {
  connect_bd_net [get_bd_pins clk_wizard_0/clk_out1] [get_bd_pins $c]
}
foreach r {smartconnect_0/aresetn soc_id_gpio/s_axi_aresetn \
           bld_id_gpio/s_axi_aresetn core_clk_freq_gpio/s_axi_aresetn bram_ctrl/s_axi_aresetn \
           uart/s_axi_aresetn} {
  connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins $r]
}

# ddr_init_complete: Versal DDRMC is calibrated by PMC during PDI boot; no PL calib
# flag from axi_noc. Tie high (see README note) - or wire a NoC status if exposed.
set vcc [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_1]
connect_bd_net [get_bd_pins xlconstant_1/dout] [get_bd_ports ddr_init_complete]

# ---------------------------------------------------------------------------
# Address map (both imem & dmem see the same space via smartconnect).
# ---------------------------------------------------------------------------
foreach space {axi_imem axi_dmem} {
  assign_bd_address -offset 0x00000000 -range 0x08000000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs axi_noc_0/S00_AXI/C0_DDR_LOW0] -force
  assign_bd_address -offset 0xFF000000 -range 0x00001000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs soc_id_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0xFF001000 -range 0x00001000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs bld_id_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0xFF002000 -range 0x00001000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs core_clk_freq_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0xFF010000 -range 0x00001000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs uart/S_AXI/Reg] -force
  assign_bd_address -offset 0xFFFF0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs bram_ctrl/S_AXI/Mem0] -force
}

regenerate_bd_layout
validate_bd_design
# Parameter propagation from axi_bram_ctrl resets emb_mem_gen's init file (BD 41-2180),
# so re-apply the boot image AFTER validate and save. In the full build, re-apply this
# once more after generate_target (propagation runs again there).
set_property CONFIG.MEMORY_INIT_FILE [file normalize [file join [file dirname [info script]] .. mem scbl.coe]] [get_bd_cells emb_mem_gen_0]
save_bd_design
