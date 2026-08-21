// ============================================================================
// ps2_rx.sv  --  PS/2 device->host receiver (Phase 3)
//
// The keyboard drives PS2_CLK (~10-16 kHz) and PS2_DATA. A frame is:
//   start(0) | d0..d7 (LSB first) | parity(odd) | stop(1)   = 11 bits
// Data is valid on the FALLING edge of PS2_CLK.
//
// Runs entirely in the `clk` (system/AXI) domain: PS2_CLK is orders of
// magnitude slower than clk, so 2-FF sync + an 8-sample glitch filter + edge
// detect is robust. A watchdog resets a half-received frame if the line idles.
//
// Emits the 8-bit scancode + 1-cycle strobe on a well-formed frame
// (start=0, stop=1, odd parity). Malformed frames pulse rx_perr and are dropped.
// ============================================================================
`timescale 1ns/1ps

module ps2_rx #(
    parameter int IDLE_TIMEOUT = 12000   // clk cycles (~400us @30MHz) -> resync
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       ps2_clk,     // async from pin
    input  logic       ps2_data,    // async from pin
    output logic [7:0] rx_data,
    output logic       rx_strobe,   // 1-cycle pulse, rx_data valid
    output logic       rx_perr      // 1-cycle pulse on parity/framing error
);

    // ---- 2-FF synchronisers ----
    logic [1:0] clk_sync, dat_sync;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin clk_sync <= 2'b11; dat_sync <= 2'b11; end
        else        begin clk_sync <= {clk_sync[0], ps2_clk};
                          dat_sync <= {dat_sync[0], ps2_data}; end
    end
    wire ps2c = clk_sync[1];
    wire ps2d = dat_sync[1];

    // ---- 8-sample glitch filter on the clock line ----
    logic [7:0] filt;
    logic       ps2c_f, ps2c_f_d;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin filt <= 8'hFF; ps2c_f <= 1'b1; ps2c_f_d <= 1'b1; end
        else begin
            filt <= {filt[6:0], ps2c};
            if      (filt == 8'hFF) ps2c_f <= 1'b1;
            else if (filt == 8'h00) ps2c_f <= 1'b0;
            ps2c_f_d <= ps2c_f;
        end
    end
    wire fall = ps2c_f_d & ~ps2c_f;   // filtered falling edge

    // ---- frame assembly ----
    // shreg shifts right, newest bit into MSB. After 11 falling edges the
    // aligned value fv has: fv[0]=start, fv[8:1]=data (d0..d7), fv[9]=parity,
    // fv[10]=stop.
    logic [10:0] shreg;
    logic [3:0]  bitcnt;   // counts falling edges 0..10
    logic [15:0] wdog;
    logic [10:0] fv;

    always_comb fv = {ps2d, shreg[10:1]};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shreg     <= 11'h7FF;
            bitcnt    <= 4'd0;
            wdog      <= 16'd0;
            rx_data   <= 8'd0;
            rx_strobe <= 1'b0;
            rx_perr   <= 1'b0;
        end else begin
            rx_strobe <= 1'b0;
            rx_perr   <= 1'b0;

            // idle watchdog: drop a partial frame if the line goes quiet
            if (bitcnt != 4'd0) begin
                if (wdog == IDLE_TIMEOUT[15:0]) begin
                    bitcnt <= 4'd0;
                    wdog   <= 16'd0;
                end else begin
                    wdog <= wdog + 16'd1;
                end
            end else begin
                wdog <= 16'd0;
            end

            if (fall) begin
                wdog  <= 16'd0;
                shreg <= fv;                     // shift in the new bit
                if (bitcnt == 4'd10) begin
                    // 11th falling edge clocked in the stop bit -> frame done
                    bitcnt <= 4'd0;
                    if ((fv[0] == 1'b0) && (fv[10] == 1'b1) &&
                        ((^fv[9:1]) == 1'b1)) begin   // odd parity over data+parity
                        rx_data   <= fv[8:1];
                        rx_strobe <= 1'b1;
                    end else begin
                        rx_perr   <= 1'b1;
                    end
                end else begin
                    bitcnt <= bitcnt + 4'd1;
                end
            end
        end
    end

endmodule
