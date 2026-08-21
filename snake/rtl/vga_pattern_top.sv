// ============================================================================
// vga_pattern_top.sv  --  Phase-1 standalone VGA bring-up for Nexys A7-100T
//
// Purpose: prove the VGA chain (pixel clock, pin mapping, cable, monitor sync)
// in isolation, WITHOUT the SCR1 SoC / block design. If this shows a stable
// picture, Phase 2 (AXI framebuffer) only has to worry about the bus.
//
// Pattern: smooth colour gradient (exercises every R/G/B wire) + 1-px white
// border (proves the visible-area edges and H/V timing line up).
//
// Pixel clock: 100 MHz on-board osc, advanced 1-in-4 via clock-enable => 25 MHz.
// Everything runs in the single 100 MHz domain (no second clock, no CDC).
//
// Pins: snake/constraints/nexys_a7_vga.xdc
// ============================================================================
`timescale 1ns/1ps

module vga_pattern_top (
    input  logic        CLK100MHZ,
    input  logic        CPU_RESETN,   // active-low
    output logic [3:0]  VGA_R,
    output logic [3:0]  VGA_G,
    output logic [3:0]  VGA_B,
    output logic        VGA_HS,
    output logic        VGA_VS,
    output logic [15:0] LED
);

    // ---- Reset sync -------------------------------------------------------
    logic [1:0] rst_sync;
    logic       rst_n;
    always_ff @(posedge CLK100MHZ or negedge CPU_RESETN) begin
        if (!CPU_RESETN) rst_sync <= 2'b00;
        else             rst_sync <= {rst_sync[0], 1'b1};
    end
    assign rst_n = rst_sync[1];

    // ---- 100 MHz -> 25 MHz pixel clock-enable (divide by 4) ---------------
    logic [1:0] ce_cnt;
    logic       pix_ce;
    always_ff @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n) ce_cnt <= 2'd0;
        else        ce_cnt <= ce_cnt + 2'd1;
    end
    assign pix_ce = (ce_cnt == 2'd3);

    // ---- Timing generator -------------------------------------------------
    logic        active, frame_start;
    logic [11:0] px, py;
    vga_timing u_timing (
        .clk        (CLK100MHZ),
        .rst_n      (rst_n),
        .pix_ce     (pix_ce),
        .hsync      (VGA_HS),
        .vsync      (VGA_VS),
        .active     (active),
        .pix_x      (px),
        .pix_y      (py),
        .frame_start(frame_start)
    );

    // ---- Test pattern -----------------------------------------------------
    logic border;
    assign border = (px == 12'd0) || (px == 12'd639)
                 || (py == 12'd0) || (py == 12'd479);

    logic [3:0] r_pat, g_pat, b_pat;
    assign r_pat = px[9:6];              // horizontal ramp
    assign b_pat = py[8:5];              // vertical ramp
    assign g_pat = px[5:2] ^ py[5:2];    // fine detail / checker

    always_ff @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n) begin
            VGA_R <= 4'h0; VGA_G <= 4'h0; VGA_B <= 4'h0;
        end else if (pix_ce) begin
            if (!active) begin
                VGA_R <= 4'h0; VGA_G <= 4'h0; VGA_B <= 4'h0;  // blanking must be black
            end else if (border) begin
                VGA_R <= 4'hF; VGA_G <= 4'hF; VGA_B <= 4'hF;  // white frame
            end else begin
                VGA_R <= r_pat; VGA_G <= g_pat; VGA_B <= b_pat;
            end
        end
    end

    // ---- Heartbeat on LED0 so we can see the frame counter tick -----------
    logic [5:0] frame_cnt;
    always_ff @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n)          frame_cnt <= '0;
        else if (frame_start) frame_cnt <= frame_cnt + 1'b1;
    end
    assign LED = {10'd0, frame_cnt};

endmodule
