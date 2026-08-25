// ============================================================================
// vga_ctrl.sv  --  AXI4-Lite tile framebuffer + VGA output (Phase 2)
//
// Two clock domains:
//   * s_axi_aclk  : AXI4-Lite register/framebuffer writes from SCR1 (~30 MHz)
//   * pclk        : 25 MHz pixel clock for VGA readout (clk_wiz output)
// CDC is handled entirely by the true-dual-port framebuffer BRAM
// (port A = AXI clock, port B = pixel clock). No shared registers cross domains.
//
// Framebuffer: 40x30 grid of 16x16 tiles -> 640x480. 1 word per cell,
// low 4 bits = palette index. Cell address = ((y<<6)|x). See doc/hw_contract.md.
//
// Base address 0xFF02_0000, 8 KB region (word-per-cell, 2048 cells).
// ============================================================================
`timescale 1ns/1ps

module vga_ctrl #(
    parameter int GRID_W   = 40,   // cells across
    parameter int GRID_H   = 30,   // cells down
    parameter int TILE     = 16,   // pixels per tile edge
    parameter int FB_CELLS = 2048, // framebuffer depth (>= (GRID_H<<6)+GRID_W)
    parameter int ADDR_W   = 13     // AXI byte-address width (8 KB)
) (
    // ---- AXI4-Lite slave (write path used; read path minimal read-back) ----
    input  logic                aclk,
    input  logic                aresetn,   // active low
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

    // ---- Pixel-clock domain / VGA out ----
    input  logic                pclk,
    input  logic                prst_n,    // active low, in pclk domain
    input  logic                pix_ce,    // 1 in SoC (pclk is already 25 MHz)
    output logic [3:0]          vga_r,
    output logic [3:0]          vga_g,
    output logic [3:0]          vga_b,
    output logic                vga_hs,
    output logic                vga_vs
);

    localparam int CELL_AW = $clog2(FB_CELLS);   // 11

    // ------------------------------------------------------------------
    // Framebuffer: true dual-port, 8-bit wide (store palette index byte)
    // ------------------------------------------------------------------
    (* ram_style = "block" *)
    logic [7:0] fb_mem [0:FB_CELLS-1];

    // Power-up to background (black). Vivado turns this into BRAM INIT;
    // also gives defined values in simulation for un-written cells.
    initial begin
        for (int i = 0; i < FB_CELLS; i++) fb_mem[i] = 8'h00;
    end

    // Port A: AXI clock. A framebuffer write (from the write FSM) takes the
    // address bus; otherwise port A serves the read-back address.
    logic                fb_wr;              // 1-cycle framebuffer write pulse
    logic [CELL_AW-1:0]  wr_cell;
    logic [7:0]          wr_data;
    logic [CELL_AW-1:0]  fb_a_addr;
    logic [7:0]          fb_a_rdata;
    assign fb_a_addr = fb_wr ? wr_cell : rd_cell;
    always_ff @(posedge aclk) begin
        if (fb_wr) fb_mem[wr_cell] <= wr_data;
        fb_a_rdata <= fb_mem[fb_a_addr];
    end

    // Port B: pixel clock (render read)
    logic [CELL_AW-1:0]  fb_b_addr;
    logic [7:0]          fb_b_rdata;
    always_ff @(posedge pclk) begin
        if (pix_ce) fb_b_rdata <= fb_mem[fb_b_addr];
    end

    // ------------------------------------------------------------------
    // AXI4-Lite write channel (one cell per transaction).
    // awready/wready are REGISTERED -- they must NOT combinationally depend on
    // awvalid/wvalid, or a valid->ready path forms a loop with the AXI
    // SmartConnect that corrupts AWADDR (observed: all writes landed at cell 0).
    // The address/data are latched when both valids are seen.
    // ------------------------------------------------------------------
    typedef enum logic [0:0] { W_IDLE, W_RESP } wstate_e;
    wstate_e wstate;
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wstate        <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            fb_wr         <= 1'b0;
            wr_cell       <= '0;
            wr_data       <= '0;
        end else begin
            s_axi_awready <= 1'b0;   // default: single-cycle ready pulses
            s_axi_wready  <= 1'b0;
            fb_wr         <= 1'b0;
            case (wstate)
                W_IDLE: if (s_axi_awvalid && s_axi_wvalid) begin
                    wr_cell       <= s_axi_awaddr[2 +: CELL_AW];  // awvalid high -> valid
                    wr_data       <= s_axi_wdata[7:0];
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;
                    fb_wr         <= 1'b1;
                    wstate        <= W_RESP;
                end
                W_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00;      // OKAY
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wstate       <= W_IDLE;
                    end
                end
                default: wstate <= W_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // AXI4-Lite read channel  (framebuffer read-back; snake never uses it)
    // ------------------------------------------------------------------
    typedef enum logic [1:0] { R_IDLE, R_WAIT, R_DATA } rstate_e;
    rstate_e rstate;
    logic [CELL_AW-1:0] rd_cell;
    assign s_axi_arready = (rstate == R_IDLE);

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rstate       <= R_IDLE;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
            s_axi_rdata  <= 32'h0;
            rd_cell      <= '0;
        end else begin
            case (rstate)
                R_IDLE: if (s_axi_arvalid) begin
                    rd_cell <= s_axi_araddr[2 +: CELL_AW];
                    rstate  <= R_WAIT;              // fb_a_rdata pipelined via port A
                end
                R_WAIT: rstate <= R_DATA;           // wait 1 cyc for BRAM
                R_DATA: begin
                    s_axi_rdata  <= {24'h0, fb_a_rdata};
                    s_axi_rresp  <= 2'b00;
                    s_axi_rvalid <= 1'b1;
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rstate       <= R_IDLE;
                    end
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // VGA timing + tile render (pixel clock domain)
    // ------------------------------------------------------------------
    logic        active, hsync, vsync;
    logic [11:0] pix_x, pix_y;
    vga_timing u_timing (
        .clk        (pclk),
        .rst_n      (prst_n),
        .pix_ce     (pix_ce),
        .hsync      (hsync),
        .vsync      (vsync),
        .active     (active),
        .pix_x      (pix_x),
        .pix_y      (pix_y),
        .frame_start()
    );

    // tile index from pixel position (TILE=16 -> shift by 4)
    localparam int TSH = $clog2(TILE);              // 4
    logic [4:0] tile_y;                             // 0..29
    logic [5:0] tile_x;                             // 0..39
    assign tile_y = pix_y[TSH +: 5];
    assign tile_x = pix_x[TSH +: 6];
    assign fb_b_addr = {tile_y, tile_x};            // (y<<6)|x

    // Pipeline sync so it lines up with the 2-cycle colour path
    // (t1: BRAM read reg + sync delay ; t2: palette comb + output reg)
    logic hs1, vs1, act1;
    always_ff @(posedge pclk) begin
        if (pix_ce) begin
            hs1  <= hsync;
            vs1  <= vsync;
            act1 <= active;
        end
    end

    // 16-entry fixed palette (RGB444) -- see doc/hw_contract.md
    logic [11:0] pal_rgb;
    always_comb begin
        case (fb_b_rdata[3:0])
            4'd0:    pal_rgb = 12'h000; // black  (background)
            4'd1:    pal_rgb = 12'h0A0; // green  (snake body)
            4'd2:    pal_rgb = 12'h0F0; // bright green (head)
            4'd3:    pal_rgb = 12'hF00; // red    (apple)
            4'd4:    pal_rgb = 12'h888; // grey   (wall)
            4'd5:    pal_rgb = 12'hFFF; // white  (text/score)
            4'd6:    pal_rgb = 12'hFF0; // yellow (bonus)
            4'd7:    pal_rgb = 12'h00F; // blue
            default: pal_rgb = 12'h000;
        endcase
    end

    // Output register (t2): blanking must be black
    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0;
            vga_hs <= 1'b1; vga_vs <= 1'b1;
        end else if (pix_ce) begin
            vga_hs <= hs1;
            vga_vs <= vs1;
            if (act1) begin
                vga_r <= pal_rgb[11:8];
                vga_g <= pal_rgb[7:4];
                vga_b <= pal_rgb[3:0];
            end else begin
                vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0;
            end
        end
    end

endmodule
