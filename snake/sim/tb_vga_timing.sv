// ============================================================================
// tb_vga_timing.sv  --  self-checking testbench for vga_timing
// Drives the generator at the pixel clock (pix_ce=1) and verifies the
// 640x480@60 timing: total pixels/lines, sync polarity, active-area size.
// Run: see snake/sim/run.sh
// ============================================================================
`timescale 1ns/1ps

module tb_vga_timing;
    logic clk = 0;
    logic rst_n = 0;
    logic hsync, vsync, active, frame_start;
    logic [11:0] px, py;

    // 25 MHz pixel clock
    always #20 clk = ~clk;

    vga_timing dut (
        .clk(clk), .rst_n(rst_n), .pix_ce(1'b1),
        .hsync(hsync), .vsync(vsync), .active(active),
        .pix_x(px), .pix_y(py), .frame_start(frame_start)
    );

    // Counters
    int active_cnt   = 0;   // active pixels in a frame
    int frame_pulses = 0;   // frame_start pulses
    int hs_low_len   = 0;   // hsync low run length (pixels)
    int hs_len_seen  = 0;
    int vs_low_len   = 0;
    int vs_len_seen  = 0;
    int total_pix    = 0;
    int errors       = 0;

    logic hsync_d, vsync_d;

    always @(posedge clk) begin
        if (rst_n) begin
            total_pix <= total_pix + 1;
            if (active)      active_cnt   <= active_cnt + 1;
            if (frame_start) frame_pulses <= frame_pulses + 1;

            // measure hsync low pulse width
            if (!hsync) hs_low_len <= hs_low_len + 1;
            else if (hs_low_len != 0) begin
                hs_len_seen <= hs_low_len;
                hs_low_len  <= 0;
            end
            // measure vsync low pulse width
            if (!vsync) vs_low_len <= vs_low_len + 1;
            else if (vs_low_len != 0) begin
                vs_len_seen <= vs_low_len;
                vs_low_len  <= 0;
            end
        end
    end

    task check(input string name, input int got, input int exp);
        if (got !== exp) begin
            $display("  FAIL: %-24s got=%0d expected=%0d", name, got, exp);
            errors++;
        end else begin
            $display("  ok  : %-24s = %0d", name, got);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;

        // Let the pipeline settle then align to a frame boundary
        wait (frame_start == 1'b1); @(posedge clk);
        active_cnt = 0; frame_pulses = 0; total_pix = 0;
        hs_len_seen = 0; vs_len_seen = 0;

        // Capture exactly one full frame (800*525 = 420000 pixels)
        while (total_pix < 800*525) @(posedge clk);

        $display("=== vga_timing 640x480@60 checks ===");
        check("active pixels/frame", active_cnt,   640*480);
        check("frame_start pulses",  frame_pulses, 1);
        check("hsync low width",     hs_len_seen,  96);
        check("vsync low width (px)", vs_len_seen, 2*800); // 2 lines * 800 px

        if (errors == 0) $display("RESULT: ALL PASS");
        else             $display("RESULT: %0d FAILURE(S)", errors);
        $finish;
    end

    // Safety timeout
    initial begin
        #50_000_000;
        $display("RESULT: TIMEOUT");
        $finish;
    end
endmodule
