/// Copyright by Syntacore LLC © 2016, 2017, 2018, 2021. See LICENSE for details
/// @file       <alinx_ve2302_scr1.sv>
/// @brief      Top-level entity with SCR1 for ALINX Versal AI Edge (XCVE2302 / VD100)
///
/// Ported from fpga/nexys4ddr/scr1/src/nexys4ddr_scr1.sv
///
/// Stage-1 configuration: SCR1 core + DDR (via CIPS/NoC/DDRMC) + PL UART (axi_uart16550
/// @0xFF010000, same register map the prebuilt scbl expects). The VD100 board USB-UART is
/// wired to PS-UART0 on MIO (unreachable from PL), so this PL UART is routed to PMOD J55
/// (3.3 V) for an external USB-TTL adapter. Debug/observation is via mark_debug -> auto
/// axi_dbg_hub over the Versal device JTAG. VGA/PS2 come back in a later stage.
///
/// The SoPC block design (alinx_ve2302_sopc, built by ../tcl/create_sopc.tcl) owns the
/// CIPS clock/reset, the NoC/DDRMC (DDR4) and the boot BRAM + GPIO peripherals. This top
/// exposes only the physical DDR4/clock pins, the reset and one status LED.

`include "scr1_arch_types.svh"
`include "scr1_arch_custom.svh"
`include "scr1_arch_description.svh"

parameter bit [31:0] FPGA_VE2302_SOC_ID             = `SCR1_PTFM_SOC_ID;
parameter bit [31:0] FPGA_VE2302_BLD_ID             = `SCR1_PTFM_BLD_ID;
parameter bit [31:0] FPGA_VE2302_CORE_CLK_FREQ      = `SCR1_PTFM_CORE_CLK_FREQ;


module alinx_ve2302_scr1 (
    // === RESET ===========================================
    input  logic                    CPU_RESETn,
    // === STATUS LED ======================================
    output logic                    LED,            // heartbeat / sign-of-life
    // === DDR4 reference clock (200 MHz LVDS) =============
    input  logic    [ 0:0]          sys_clk_p,
    input  logic    [ 0:0]          sys_clk_n,
    // === DDR4 (hard DDRMC via NoC, exported from the BD) =
    output logic    [ 0:0]          DDR4_act_n,
    output logic    [16:0]          DDR4_adr,
    output logic    [ 1:0]          DDR4_ba,
    output logic    [ 0:0]          DDR4_bg,
    output logic    [ 0:0]          DDR4_ck_c,
    output logic    [ 0:0]          DDR4_ck_t,
    output logic    [ 0:0]          DDR4_cke,
    output logic    [ 0:0]          DDR4_cs_n,
    inout  logic    [ 7:0]          DDR4_dm_n,
    inout  logic    [63:0]          DDR4_dq,
    inout  logic    [ 7:0]          DDR4_dqs_c,
    inout  logic    [ 7:0]          DDR4_dqs_t,
    output logic    [ 0:0]          DDR4_odt,
    output logic    [ 0:0]          DDR4_reset_n,
    // === PL UART (axi_uart16550 @ 0xFF010000) on PMOD J55, 3.3 V ===
    // For an external USB-TTL adapter; scbl serial console. RxD in, TxD out.
    input  logic                    uart_rxd,
    output logic                    uart_txd
`ifdef SCR1_DBG_EN
    ,
    // === SCR1 core debug JTAG (OpenOCD), on the PMOD J55 header ===
    input  logic                    JTAG_TCK,
    input  logic                    JTAG_TMS,
    input  logic                    JTAG_TDI,
    output logic                    JTAG_TDO
`endif // SCR1_DBG_EN
);

//=======================================================
//  Signals / Variables declarations
//=======================================================
logic                               pwrup_rst_n;
logic                               cpu_clk;
logic                               extn_rst_n;
logic [1:0]                         extn_rst_n_sync;
logic                               hard_rst_n;
logic [3:0]                         hard_rst_n_count;
logic                               soc_rst_n;
logic                               cpu_reset;
`ifdef SCR1_DBG_EN
logic                               sys_rst_n;
`endif // SCR1_DBG_EN

// --- SCR1 ---------------------------------------------

// AXI IMEM
logic [ 2:0]                        axi_imem_arid;
(* mark_debug = "true" *) logic [31:0]                        axi_imem_araddr;
(* mark_debug = "true" *) logic                               axi_imem_arvalid;
(* mark_debug = "true" *) logic                               axi_imem_arready;
logic [ 7:0]                        axi_imem_arlen;
logic [ 2:0]                        axi_imem_arsize;
logic [ 1:0]                        axi_imem_arburst;
logic [ 3:0]                        axi_imem_arcache;
logic [ 2:0]                        axi_imem_rid;
(* mark_debug = "true" *) logic [31:0]                        axi_imem_rdata;
(* mark_debug = "true" *) logic                               axi_imem_rvalid;
logic                               axi_imem_rready;
logic [ 1:0]                        axi_imem_rresp;
logic                               axi_imem_rlast;
// AXI DMEM
logic [ 1:0]                        axi_dmem_awid;
(* mark_debug = "true" *) logic [31:0]                        axi_dmem_awaddr;
(* mark_debug = "true" *) logic                               axi_dmem_awvalid;
logic                               axi_dmem_awready;
logic [ 7:0]                        axi_dmem_awlen;
logic [ 2:0]                        axi_dmem_awsize;
logic [ 1:0]                        axi_dmem_awburst;
logic [ 3:0]                        axi_dmem_awcache;
(* mark_debug = "true" *) logic [31:0]                        axi_dmem_wdata;
logic [ 3:0]                        axi_dmem_wstrb;
logic                               axi_dmem_wvalid;
logic                               axi_dmem_wready;
logic                               axi_dmem_wlast;
logic [ 1:0]                        axi_dmem_bid;
logic [ 1:0]                        axi_dmem_bresp;
logic                               axi_dmem_bvalid;
logic                               axi_dmem_bready;
logic [ 1:0]                        axi_dmem_arid;
(* mark_debug = "true" *) logic [31:0]                        axi_dmem_araddr;
logic                               axi_dmem_arvalid;
logic                               axi_dmem_arready;
logic [ 7:0]                        axi_dmem_arlen;
logic [ 2:0]                        axi_dmem_arsize;
logic [ 1:0]                        axi_dmem_arburst;
logic [ 3:0]                        axi_dmem_arcache;
logic [ 1:0]                        axi_dmem_rid;
(* mark_debug = "true" *) logic [31:0]                        axi_dmem_rdata;
logic                               axi_dmem_rvalid;
logic                               axi_dmem_rready;
logic [ 1:0]                        axi_dmem_rresp;
logic                               axi_dmem_rlast;

`ifdef SCR1_IPIC_EN
logic [SCR1_IRQ_LINES_NUM-1:0]      scr1_irq;
`else
logic                               scr1_irq;
`endif // SCR1_IPIC_EN

// DDRMC calibration status: on Versal calibration is run by the PMC during PDI boot, so
// there is no PL-visible calib flag from the NoC. The SoPC ties this high.
logic                               ddr_init_complete;

// --- UART modem-control loopback (scbl uses no flow control) --------------
// Mirror the Nexys hookup: RTS->CTS and DTR->DSR/DCD looped, RI held inactive.
logic                               uart_rtsn_lb;
logic                               uart_dtrn_lb;

// --- Heartbeat ----------------------------------------
logic [31:0]                        rtc_counter;
logic                               tick_2Hz;
logic                               heartbeat;


//=======================================================
//  Resets
//=======================================================
always_ff @(posedge cpu_clk, negedge pwrup_rst_n)
begin
    if (~pwrup_rst_n) begin
        extn_rst_n_sync     <= '0;
    end else begin
        extn_rst_n_sync[0]  <= CPU_RESETn;
        extn_rst_n_sync[1]  <= extn_rst_n_sync[0];
    end
end
assign extn_rst_n = extn_rst_n_sync[1];

always_ff @(posedge cpu_clk, negedge pwrup_rst_n)
begin
    if (~pwrup_rst_n) begin
        hard_rst_n          <= 1'b0;
        hard_rst_n_count    <= '0;
    end else begin
        if (hard_rst_n) begin
            hard_rst_n          <= extn_rst_n;
            hard_rst_n_count    <= '0;
        end else begin
            if (extn_rst_n) begin
                if (hard_rst_n_count == '1) begin
                    hard_rst_n          <= 1'b1;
                end else begin
                    hard_rst_n_count    <= hard_rst_n_count + 1;
                end
            end else begin
                hard_rst_n_count    <= '0;
            end
        end
    end
end

`ifdef SCR1_DBG_EN
assign soc_rst_n = sys_rst_n;
`else
assign soc_rst_n = hard_rst_n;
`endif // SCR1_DBG_EN

//=======================================================
//  Heartbeat
//=======================================================
always_ff @(posedge cpu_clk, negedge hard_rst_n)
begin
    if (~hard_rst_n) begin
        rtc_counter     <= '0;
        tick_2Hz        <= 1'b0;
    end
    else begin
        if (rtc_counter == '0) begin
            rtc_counter <= (FPGA_VE2302_CORE_CLK_FREQ/2);
            tick_2Hz    <= 1'b1;
        end
        else begin
            rtc_counter <= rtc_counter - 1'b1;
            tick_2Hz    <= 1'b0;
        end
    end
end

always_ff @(posedge cpu_clk, negedge hard_rst_n)
begin
    if (~hard_rst_n) begin
        heartbeat       <= 1'b0;
    end
    else begin
        if (tick_2Hz) begin
            heartbeat   <= ~heartbeat;
        end
    end
end

//=======================================================
//  SCR1 Core's Processor Cluster
//=======================================================
// scbl drives the UART entirely by polling (interrupts disabled), so the UART IRQ is left
// unconnected and the core IRQ line(s) are tied low.
assign scr1_irq = '0;


scr1_top_axi
i_scr1 (
    // Common
    .pwrup_rst_n                (pwrup_rst_n),
    .rst_n                      (hard_rst_n),
    .cpu_rst_n                  (~cpu_reset),
    .test_mode                  (1'b0),
    .test_rst_n                 (1'b1),
    .clk                        (cpu_clk),
    .rtc_clk                    (1'b0),
`ifdef SCR1_DBG_EN
    .sys_rst_n_o                (sys_rst_n),
    .sys_rdc_qlfy_o             (),
`endif // SCR1_DBG_EN

    // Fuses
    .fuse_mhartid               ('0),
`ifdef SCR1_DBG_EN
    .fuse_idcode                (`SCR1_TAP_IDCODE),
`endif // SCR1_DBG_EN

    // IRQ
`ifdef SCR1_IPIC_EN
    .irq_lines                  (scr1_irq),
`else
    .ext_irq                    (scr1_irq),
`endif // SCR1_IPIC_EN
    .soft_irq                   (1'b0),

`ifdef SCR1_DBG_EN
    // Debug Interface - JTAG I/F, brought to the PMOD J55 pins for OpenOCD. trst_n is
    // held high (no dedicated reset line); tdo is driven on a dedicated output pin
    // (tdo_en left open - the pin is not shared/tri-stated).
    .trst_n                     (1'b1),
    .tck                        (JTAG_TCK),
    .tms                        (JTAG_TMS),
    .tdi                        (JTAG_TDI),
    .tdo                        (JTAG_TDO),
    .tdo_en                     (),
`endif // SCR1_DBG_EN

    // Instruction Memory Interface (read-only path)
    .io_axi_imem_awid           (),
    .io_axi_imem_awaddr         (),
    .io_axi_imem_awlen          (),
    .io_axi_imem_awsize         (),
    .io_axi_imem_awburst        (),
    .io_axi_imem_awlock         (),
    .io_axi_imem_awcache        (),
    .io_axi_imem_awprot         (),
    .io_axi_imem_awregion       (),
    .io_axi_imem_awuser         (),
    .io_axi_imem_awqos          (),
    .io_axi_imem_awvalid        (),
    .io_axi_imem_awready        ('0),
    .io_axi_imem_wdata          (),
    .io_axi_imem_wstrb          (),
    .io_axi_imem_wlast          (),
    .io_axi_imem_wuser          (),
    .io_axi_imem_wvalid         (),
    .io_axi_imem_wready         ('0),
    .io_axi_imem_bid            ('0),
    .io_axi_imem_bresp          ('0),
    .io_axi_imem_bvalid         ('0),
    .io_axi_imem_buser          ('0),
    .io_axi_imem_bready         (),
    .io_axi_imem_arid           (axi_imem_arid),
    .io_axi_imem_araddr         (axi_imem_araddr),
    .io_axi_imem_arlen          (axi_imem_arlen),
    .io_axi_imem_arsize         (axi_imem_arsize),
    .io_axi_imem_arburst        (axi_imem_arburst),
    .io_axi_imem_arlock         (),
    .io_axi_imem_arcache        (),
    .io_axi_imem_arprot         (),
    .io_axi_imem_arregion       (),
    .io_axi_imem_aruser         (),
    .io_axi_imem_arqos          (),
    .io_axi_imem_arvalid        (axi_imem_arvalid),
    .io_axi_imem_arready        (axi_imem_arready),
    .io_axi_imem_rid            (axi_imem_rid),
    .io_axi_imem_rdata          (axi_imem_rdata),
    .io_axi_imem_rresp          (axi_imem_rresp),
    .io_axi_imem_rlast          (axi_imem_rlast),
    .io_axi_imem_ruser          ('0),
    .io_axi_imem_rvalid         (axi_imem_rvalid),
    .io_axi_imem_rready         (axi_imem_rready),

    // Data Memory Interface
    .io_axi_dmem_awid           (axi_dmem_awid),
    .io_axi_dmem_awaddr         (axi_dmem_awaddr),
    .io_axi_dmem_awlen          (axi_dmem_awlen),
    .io_axi_dmem_awsize         (axi_dmem_awsize),
    .io_axi_dmem_awburst        (axi_dmem_awburst),
    .io_axi_dmem_awlock         (),
    .io_axi_dmem_awcache        (),
    .io_axi_dmem_awprot         (),
    .io_axi_dmem_awregion       (),
    .io_axi_dmem_awuser         (),
    .io_axi_dmem_awqos          (),
    .io_axi_dmem_awvalid        (axi_dmem_awvalid),
    .io_axi_dmem_awready        (axi_dmem_awready),
    .io_axi_dmem_wdata          (axi_dmem_wdata),
    .io_axi_dmem_wstrb          (axi_dmem_wstrb),
    .io_axi_dmem_wlast          (axi_dmem_wlast),
    .io_axi_dmem_wuser          (),
    .io_axi_dmem_wvalid         (axi_dmem_wvalid),
    .io_axi_dmem_wready         (axi_dmem_wready),
    .io_axi_dmem_bid            (axi_dmem_bid),
    .io_axi_dmem_bresp          (axi_dmem_bresp),
    .io_axi_dmem_bvalid         (axi_dmem_bvalid),
    .io_axi_dmem_buser          ('0),
    .io_axi_dmem_bready         (axi_dmem_bready),
    .io_axi_dmem_arid           (axi_dmem_arid),
    .io_axi_dmem_araddr         (axi_dmem_araddr),
    .io_axi_dmem_arlen          (axi_dmem_arlen),
    .io_axi_dmem_arsize         (axi_dmem_arsize),
    .io_axi_dmem_arburst        (axi_dmem_arburst),
    .io_axi_dmem_arlock         (),
    .io_axi_dmem_arcache        (),
    .io_axi_dmem_arprot         (),
    .io_axi_dmem_arregion       (),
    .io_axi_dmem_aruser         (),
    .io_axi_dmem_arqos          (),
    .io_axi_dmem_arvalid        (axi_dmem_arvalid),
    .io_axi_dmem_arready        (axi_dmem_arready),
    .io_axi_dmem_rid            (axi_dmem_rid),
    .io_axi_dmem_rdata          (axi_dmem_rdata),
    .io_axi_dmem_rresp          (axi_dmem_rresp),
    .io_axi_dmem_rlast          (axi_dmem_rlast),
    .io_axi_dmem_ruser          ('0),
    .io_axi_dmem_rvalid         (axi_dmem_rvalid),
    .io_axi_dmem_rready         (axi_dmem_rready)
);

//=======================================================
//  FPGA Platform's System-on-Programmable-Chip (SOPC)
//=======================================================
// Built by ../tcl/create_sopc.tcl (BD `alinx_ve2302_sopc`). Port names below are the
// contract that BD exposes; adjust on both sides together.
alinx_ve2302_sopc
i_soc (
    // CLOCKs & RESETs (cpu_clk from the CIPS/clk_wizard; no board oscillator pin)
    .pwrup_rst_n_o              (pwrup_rst_n        ),
    .soc_rst_n                  (soc_rst_n          ),
    .cpu_clk_o                  (cpu_clk            ),
    .cpu_reset_o                (cpu_reset          ),
    .ddr_init_complete          (ddr_init_complete  ),
    // DDR4 reference clock + physical DDR4 pins (owned by the BD)
    .sys_clk_p                  (sys_clk_p          ),
    .sys_clk_n                  (sys_clk_n          ),
    .DDR4_act_n                 (DDR4_act_n         ),
    .DDR4_adr                   (DDR4_adr           ),
    .DDR4_ba                    (DDR4_ba            ),
    .DDR4_bg                    (DDR4_bg            ),
    .DDR4_ck_c                  (DDR4_ck_c          ),
    .DDR4_ck_t                  (DDR4_ck_t          ),
    .DDR4_cke                   (DDR4_cke           ),
    .DDR4_cs_n                  (DDR4_cs_n          ),
    .DDR4_dm_n                  (DDR4_dm_n          ),
    .DDR4_dq                    (DDR4_dq            ),
    .DDR4_dqs_c                 (DDR4_dqs_c         ),
    .DDR4_dqs_t                 (DDR4_dqs_t         ),
    .DDR4_odt                   (DDR4_odt           ),
    .DDR4_reset_n               (DDR4_reset_n       ),
    // AXI I-MEM
    .axi_imem_arid              (axi_imem_arid      ),
    .axi_imem_araddr            (axi_imem_araddr    ),
    .axi_imem_arlen             (axi_imem_arlen     ),
    .axi_imem_arsize            (axi_imem_arsize    ),
    .axi_imem_arburst           (axi_imem_arburst   ),
    .axi_imem_arlock            ('0                 ),
    .axi_imem_arcache           ('d3                ),
    .axi_imem_arprot            ('0                 ),
    .axi_imem_arqos             ('0                 ),
    .axi_imem_arvalid           (axi_imem_arvalid   ),
    .axi_imem_arready           (axi_imem_arready   ),
    .axi_imem_rid               (axi_imem_rid       ),
    .axi_imem_rdata             (axi_imem_rdata     ),
    .axi_imem_rresp             (axi_imem_rresp     ),
    .axi_imem_rlast             (axi_imem_rlast     ),
    .axi_imem_rvalid            (axi_imem_rvalid    ),
    .axi_imem_rready            (axi_imem_rready    ),
    // AXI D-MEM
    .axi_dmem_awid              (axi_dmem_awid      ),
    .axi_dmem_awaddr            (axi_dmem_awaddr    ),
    .axi_dmem_awlen             (axi_dmem_awlen     ),
    .axi_dmem_awsize            (axi_dmem_awsize    ),
    .axi_dmem_awburst           (axi_dmem_awburst   ),
    .axi_dmem_awlock            ('0                 ),
    .axi_dmem_awcache           ('d3                ),
    .axi_dmem_awprot            ('0                 ),
    .axi_dmem_awqos             ('0                 ),
    .axi_dmem_awvalid           (axi_dmem_awvalid   ),
    .axi_dmem_awready           (axi_dmem_awready   ),
    .axi_dmem_wdata             (axi_dmem_wdata     ),
    .axi_dmem_wstrb             (axi_dmem_wstrb     ),
    .axi_dmem_wlast             (axi_dmem_wlast     ),
    .axi_dmem_wvalid            (axi_dmem_wvalid    ),
    .axi_dmem_wready            (axi_dmem_wready    ),
    .axi_dmem_bid               (axi_dmem_bid       ),
    .axi_dmem_bresp             (axi_dmem_bresp     ),
    .axi_dmem_bvalid            (axi_dmem_bvalid    ),
    .axi_dmem_bready            (axi_dmem_bready    ),
    .axi_dmem_arid              (axi_dmem_arid      ),
    .axi_dmem_araddr            (axi_dmem_araddr    ),
    .axi_dmem_arlen             (axi_dmem_arlen     ),
    .axi_dmem_arsize            (axi_dmem_arsize    ),
    .axi_dmem_arburst           (axi_dmem_arburst   ),
    .axi_dmem_arlock            ('0                 ),
    .axi_dmem_arcache           ('d3                ),
    .axi_dmem_arprot            ('0                 ),
    .axi_dmem_arqos             ('0                 ),
    .axi_dmem_arvalid           (axi_dmem_arvalid   ),
    .axi_dmem_arready           (axi_dmem_arready   ),
    .axi_dmem_rid               (axi_dmem_rid       ),
    .axi_dmem_rdata             (axi_dmem_rdata     ),
    .axi_dmem_rresp             (axi_dmem_rresp     ),
    .axi_dmem_rlast             (axi_dmem_rlast     ),
    .axi_dmem_rvalid            (axi_dmem_rvalid    ),
    .axi_dmem_rready            (axi_dmem_rready    ),
    // IDs (read by the CPU through axi_gpio)
    .soc_id_tri_i               (FPGA_VE2302_SOC_ID),
    .bld_id_tri_i               (FPGA_VE2302_BLD_ID),
    .core_clk_freq_tri_i        (FPGA_VE2302_CORE_CLK_FREQ),
    // UART (axi_uart16550) - data to PMOD pins; modem controls looped back
    .uart_rxd                   (uart_rxd          ),
    .uart_txd                   (uart_txd          ),
    .uart_rtsn                  (uart_rtsn_lb      ),
    .uart_ctsn                  (uart_rtsn_lb      ),
    .uart_dtrn                  (uart_dtrn_lb      ),
    .uart_dsrn                  (uart_dtrn_lb      ),
    .uart_dcdn                  (uart_dtrn_lb      ),
    .uart_ri                    (1'b1              ),
    .uart_baudoutn              (                  ),
    .uart_ddis                  (                  ),
    .uart_out1n                 (                  ),
    .uart_out2n                 (                  ),
    .uart_rxrdyn                (                  ),
    .uart_txrdyn                (                  )
);

//==========================================================
// LED (sign of life)
//==========================================================
assign LED = heartbeat;

endmodule : alinx_ve2302_scr1
