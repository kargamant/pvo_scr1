// ============================================================================
// vga_fb.sv  --  320x200 x 8bpp pixel framebuffer + HW 256-colour palette
//
// For DOOM (doomgeneric). Replaces the tile-mode snake controller.
//   * Framebuffer: 320x200, 1 byte/pixel (palette index). Stored 4 px per
//     32-bit word (16000 words) in true-dual-port BRAM. CPU writes words.
//   * Palette: 256 entries, RGB444, loadable at runtime (DOOM I_SetPalette).
//   * Output: 640x480@60. Image is 320x200 pixel-doubled -> 640x400, centred
//     vertically (40 px black bars top/bottom). pclk = 25 MHz (pix_ce=1).
//
// AXI4-Lite slave (ADDR_W=17, 128 KB window):
//   awaddr[16]=0 : framebuffer, word index = awaddr[15:2]  (write 4 px/word)
//   awaddr[16]=1 : palette,      index = awaddr[9:2], data = 0x00RRGGBB
//                  (HW keeps the top nibble of each channel -> RGB444)
// awready/wready are REGISTERED (no comb valid->ready loop with SmartConnect).
// ============================================================================
`timescale 1ns/1ps

module vga_fb #(
    parameter int SRC_W  = 320,
    parameter int SRC_H  = 200,
    parameter int V_OFF  = 40,          // (480-400)/2 top border
    parameter int ADDR_W = 17,
    parameter int FB_WORDS = 16384      // >= SRC_W*SRC_H/4 = 16000
) (
    input  logic                aclk,
    input  logic                aresetn,

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

    input  logic                pclk,       // 25 MHz pixel clock
    input  logic                prst_n,
    input  logic                pix_ce,     // 1 in SoC
    output logic [3:0]          vga_r,
    output logic [3:0]          vga_g,
    output logic [3:0]          vga_b,
    output logic                vga_hs,
    output logic                vga_vs
);
    localparam int FB_AW = $clog2(FB_WORDS);   // 14

    // ---- storage ----
    (* ram_style = "block" *) logic [31:0] fbmem  [0:FB_WORDS-1];
    (* ram_style = "distributed" *) logic [11:0] palmem [0:255];

    initial begin
        for (int i = 0; i < FB_WORDS; i++) fbmem[i] = 32'h0;
        // default palette = grayscale ramp so a raw framebuffer is visible
        for (int i = 0; i < 256; i++) palmem[i] = {i[7:4], i[7:4], i[7:4]};
    end

    // ================= AXI write (registered ready, latched) =================
    wire        aw_is_pal = s_axi_awaddr[16];
    wire [FB_AW-1:0] aw_word = s_axi_awaddr[2 +: FB_AW];
    wire [7:0]  aw_pidx = s_axi_awaddr[2 +: 8];

    logic            fb_wr, pal_wr;
    logic [FB_AW-1:0] wr_word;
    logic [7:0]      wr_pidx;
    logic [31:0]     wr_data;

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
            pal_wr        <= 1'b0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            fb_wr         <= 1'b0;
            pal_wr        <= 1'b0;
            case (wstate)
                W_IDLE: if (s_axi_awvalid && s_axi_wvalid) begin
                    wr_word       <= aw_word;
                    wr_pidx       <= aw_pidx;
                    wr_data       <= s_axi_wdata;
                    fb_wr         <= ~aw_is_pal;
                    pal_wr        <=  aw_is_pal;
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;
                    wstate        <= W_RESP;
                end
                W_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00;
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wstate       <= W_IDLE;
                    end
                end
                default: wstate <= W_IDLE;
            endcase
        end
    end

    // framebuffer write port (port A, aclk) + AXI read-back port
    logic [FB_AW-1:0] fb_a_addr;
    logic [31:0]      fb_a_q;
    logic [FB_AW-1:0] rd_word;
    assign fb_a_addr = fb_wr ? wr_word : rd_word;
    always_ff @(posedge aclk) begin
        if (fb_wr) fbmem[wr_word] <= wr_data;
        fb_a_q <= fbmem[fb_a_addr];
    end

    // palette write + AXI read-back
    logic [7:0]  rd_pidx;
    logic [11:0] pal_a_q;
    always_ff @(posedge aclk) begin
        if (pal_wr) palmem[wr_pidx] <= {wr_data[23:20], wr_data[15:12], wr_data[7:4]};
        pal_a_q <= palmem[rd_pidx];
    end

    // ================= AXI read (diagnostic read-back) =================
    wire ar_is_pal = s_axi_araddr[16];
    typedef enum logic [1:0] { R_IDLE, R_A, R_B, R_D } rstate_e;
    rstate_e rstate;
    logic    rd_is_pal;
    assign s_axi_arready = (rstate == R_IDLE);
    assign rd_word = s_axi_araddr[2 +: FB_AW];
    assign rd_pidx = s_axi_araddr[2 +: 8];

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rstate       <= R_IDLE;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
            s_axi_rdata  <= 32'h0;
            rd_is_pal    <= 1'b0;
        end else begin
            case (rstate)
                R_IDLE: if (s_axi_arvalid) begin
                    rd_is_pal <= ar_is_pal;
                    rstate    <= R_A;      // addr presented via rd_word/rd_pidx
                end
                R_A: rstate <= R_B;        // BRAM/dist-RAM read latency
                R_B: begin
                    s_axi_rdata  <= rd_is_pal ? {20'h0, pal_a_q} : fb_a_q;
                    s_axi_rresp  <= 2'b00;
                    s_axi_rvalid <= 1'b1;
                    rstate       <= R_D;
                end
                R_D: if (s_axi_rvalid && s_axi_rready) begin
                    s_axi_rvalid <= 1'b0;
                    rstate       <= R_IDLE;
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

    // ================= pixel readout (pclk) =================
    logic        active, hsync, vsync;
    logic [11:0] sx, sy;
    vga_timing u_timing (
        .clk(pclk), .rst_n(prst_n), .pix_ce(pix_ce),
        .hsync(hsync), .vsync(vsync), .active(active),
        .pix_x(sx), .pix_y(sy), .frame_start()
    );

    // stage 0 (combinational from timing outputs)
    localparam logic [11:0] VOFF_LO = 12'(V_OFF);
    localparam logic [11:0] VOFF_HI = 12'(V_OFF + 2*SRC_H);
    wire        in_img = active && (sy >= VOFF_LO) && (sy < VOFF_HI);
    wire [8:0]  px   = sx[9:1];                       // sx/2 -> 0..319
    wire [11:0] rely = sy - VOFF_LO;
    wire [7:0]  py   = rely[8:1];                      // (sy-off)/2 -> 0..199
    wire [15:0] sidx = 16'(({8'h0, py} * 16'd320) + {7'h0, px}); // py*320+px
    wire [FB_AW-1:0] rd_word_b = sidx[2 +: FB_AW];
    wire [1:0]  lane0 = sidx[1:0];

    // framebuffer port B (pclk read) + pipelined sync
    logic [31:0] word_b;
    logic [1:0]  lane1;
    logic        hs1, vs1, img1;
    always_ff @(posedge pclk) begin
        if (pix_ce) begin
            word_b <= fbmem[rd_word_b];              // valid next cycle
            lane1  <= lane0;
            hs1    <= hsync; vs1 <= vsync; img1 <= in_img;
        end
    end

    // extract pixel byte, palette lookup
    wire [7:0]  pidx_b = word_b[{lane1, 3'b000} +: 8];
    logic [11:0] rgb2;
    logic        hs2, vs2, img2;
    always_ff @(posedge pclk) begin
        if (pix_ce) begin
            rgb2 <= palmem[pidx_b];                  // valid next cycle
            hs2  <= hs1; vs2 <= vs1; img2 <= img1;
        end
    end

    // output stage (aligns colour, hs, vs at the same depth)
    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0;
            vga_hs <= 1'b1; vga_vs <= 1'b1;
        end else if (pix_ce) begin
            vga_hs <= hs2;
            vga_vs <= vs2;
            if (img2) begin
                vga_r <= rgb2[11:8];
                vga_g <= rgb2[7:4];
                vga_b <= rgb2[3:0];
            end else begin
                vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0;
            end
        end
    end

endmodule
