// ============================================================================
// vga_timing.sv  --  VGA sync/timing generator
//
// Domain-agnostic: advances one pixel every cycle that `pix_ce` is high.
//   * Standalone test  : clk = 100 MHz, pix_ce = divide-by-4  -> 25.0 MHz pixels
//   * SoC integration  : clk = 25 MHz (clk_wiz), pix_ce = 1'b1
//
// Default parameters = 640x480 @ 60 Hz, pixel clock 25.175 MHz (25.0 MHz ok).
// HS/VS are active-LOW (standard VGA).
//
// Part of the SCR1 "snake" bring-up (Phase 1). See snake/doc/hw_contract.md.
// ============================================================================
`timescale 1ns/1ps

module vga_timing #(
    // Horizontal timing (in pixels)
    parameter int H_VISIBLE = 640,
    parameter int H_FRONT   = 16,
    parameter int H_SYNC    = 96,
    parameter int H_BACK    = 48,
    // Vertical timing (in lines)
    parameter int V_VISIBLE = 480,
    parameter int V_FRONT   = 10,
    parameter int V_SYNC    = 2,
    parameter int V_BACK    = 33
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        pix_ce,      // pixel clock-enable (1 pixel per high cycle)

    output logic        hsync,       // active low
    output logic        vsync,       // active low
    output logic        active,      // high inside the visible area
    output logic [11:0] pix_x,       // 0..H_VISIBLE-1 while active (else don't-care)
    output logic [11:0] pix_y,       // 0..V_VISIBLE-1 while active
    output logic        frame_start  // 1-cycle pulse at start of a new frame
);

    // 12-bit-sized constants so all comparisons stay 12-bit vs 12-bit
    localparam logic [11:0] H_TOTAL_M1   = 12'(H_VISIBLE + H_FRONT + H_SYNC + H_BACK - 1); // 799
    localparam logic [11:0] V_TOTAL_M1   = 12'(V_VISIBLE + V_FRONT + V_SYNC + V_BACK - 1); // 524
    localparam logic [11:0] H_VIS        = 12'(H_VISIBLE);
    localparam logic [11:0] V_VIS        = 12'(V_VISIBLE);
    // Sync pulse windows (measured from end of visible + front porch)
    localparam logic [11:0] H_SYNC_START = 12'(H_VISIBLE + H_FRONT);          // 656
    localparam logic [11:0] H_SYNC_END   = 12'(H_VISIBLE + H_FRONT + H_SYNC); // 752
    localparam logic [11:0] V_SYNC_START = 12'(V_VISIBLE + V_FRONT);          // 490
    localparam logic [11:0] V_SYNC_END   = 12'(V_VISIBLE + V_FRONT + V_SYNC); // 492

    logic [11:0] h_cnt;   // 0..H_TOTAL_M1
    logic [11:0] v_cnt;   // 0..V_TOTAL_M1

    // ---- Counters ---------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= '0;
            v_cnt <= '0;
        end else if (pix_ce) begin
            if (h_cnt == H_TOTAL_M1) begin
                h_cnt <= '0;
                v_cnt <= (v_cnt == V_TOTAL_M1) ? '0 : (v_cnt + 1'b1);
            end else begin
                h_cnt <= h_cnt + 1'b1;
            end
        end
    end

    // ---- Derived outputs (registered so they align with a pipelined pixel) -
    logic        h_active, v_active;
    assign h_active = (h_cnt < H_VIS);
    assign v_active = (v_cnt < V_VIS);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hsync       <= 1'b1;
            vsync       <= 1'b1;
            active      <= 1'b0;
            pix_x       <= '0;
            pix_y       <= '0;
            frame_start <= 1'b0;
        end else if (pix_ce) begin
            hsync       <= ~((h_cnt >= H_SYNC_START) && (h_cnt < H_SYNC_END));
            vsync       <= ~((v_cnt >= V_SYNC_START) && (v_cnt < V_SYNC_END));
            active      <= h_active && v_active;
            pix_x       <= h_active ? h_cnt : '0;
            pix_y       <= v_active ? v_cnt : '0;
            frame_start <= (h_cnt == H_TOTAL_M1) && (v_cnt == V_TOTAL_M1);
        end else begin
            frame_start <= 1'b0;
        end
    end

endmodule
