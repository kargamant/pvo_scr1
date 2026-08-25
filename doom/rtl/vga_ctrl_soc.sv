// ============================================================================
// vga_ctrl_soc.sv -- SoC integration wrapper for vga_ctrl.
//
// `pclk` is a dedicated, buffered 25 MHz pixel clock from clk_wiz clk_out4
// (clk_out2 is No_buffer -> reserved for the DDR MIG; must NOT drive fabric).
// Pixel rate = pclk, so pix_ce is tied high.
//
// AXI4-Lite on aclk (30 MHz). Port names kept AXI-standard so Vivado IP
// integrator infers the S_AXI interface for a -type module bd cell.
// ============================================================================
`timescale 1ns/1ps

module vga_ctrl_soc #(
    parameter int ADDR_W = 13
) (
    input  logic                aclk,
    input  logic                aresetn,     // active low, aclk domain
    input  logic                pclk,        // 25 MHz pixel clock (clk_wiz clk_out4)

    input  logic [ADDR_W-1:0]   s_axi_awaddr,
    input  logic [2:0]          s_axi_awprot,
    input  logic                s_axi_awvalid,
    output logic                s_axi_awready,
    input  logic [31:0]         s_axi_wdata,
    input  logic [3:0]          s_axi_wstrb,
    input  logic                s_axi_wvalid,
    output logic                s_axi_wready,
    output logic [1:0]          s_axi_bresp,
    output logic                s_axi_bvalid,
    input  logic                s_axi_bready,
    input  logic [ADDR_W-1:0]   s_axi_araddr,
    input  logic [2:0]          s_axi_arprot,
    input  logic                s_axi_arvalid,
    output logic                s_axi_arready,
    output logic [31:0]         s_axi_rdata,
    output logic [1:0]          s_axi_rresp,
    output logic                s_axi_rvalid,
    input  logic                s_axi_rready,

    output logic [3:0]          vga_r,
    output logic [3:0]          vga_g,
    output logic [3:0]          vga_b,
    output logic                vga_hs,
    output logic                vga_vs
);
    // ---- 2-FF reset synchroniser into the pclk domain ----
    logic [1:0] prst_sync;
    logic       prst_n;
    always_ff @(posedge pclk or negedge aresetn) begin
        if (!aresetn) prst_sync <= 2'b00;
        else          prst_sync <= {prst_sync[0], 1'b1};
    end
    assign prst_n = prst_sync[1];

    // pclk is already the 25 MHz pixel clock -> advance every cycle
    logic pix_ce;
    assign pix_ce = 1'b1;

    vga_ctrl #(.ADDR_W(ADDR_W)) u_vga (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .pclk(pclk), .prst_n(prst_n), .pix_ce(pix_ce),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b), .vga_hs(vga_hs), .vga_vs(vga_vs)
    );
endmodule
