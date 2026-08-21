// ============================================================================
// tb_vga_ctrl.sv  --  self-checking testbench for vga_ctrl (Phase 2)
//   1. writes a handful of cells over AXI4-Lite (aclk domain)
//   2. reads a couple back over AXI4-Lite
//   3. scans one full VGA frame (pclk domain) and verifies every output pixel
//      matches a reference model of the 2-cycle tile+palette pipeline.
// Run: see snake/sim/run.sh
// ============================================================================
`timescale 1ns/1ps

module tb_vga_ctrl;
    localparam int ADDR_W = 13;

    logic aclk = 0; always #16 aclk = ~aclk;   // ~31 MHz
    logic pclk = 0; always #20 pclk = ~pclk;   // 25 MHz
    logic aresetn = 0, prst_n = 0;

    logic [ADDR_W-1:0] awaddr, araddr;
    logic              awvalid, awready, wvalid, wready, bvalid, bready;
    logic [31:0]       wdata, rdata;
    logic [3:0]        wstrb;
    logic [1:0]        bresp, rresp;
    logic              arvalid, arready, rvalid, rready;

    logic [3:0] vga_r, vga_g, vga_b;
    logic       vga_hs, vga_vs;

    vga_ctrl #(.ADDR_W(ADDR_W)) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'b0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(3'b0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .pclk(pclk), .prst_n(prst_n), .pix_ce(1'b1),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b), .vga_hs(vga_hs), .vga_vs(vga_vs)
    );

    int errors = 0;

    function automatic [11:0] pal(input [3:0] idx);
        case (idx)
            4'd0: pal = 12'h000; 4'd1: pal = 12'h0A0; 4'd2: pal = 12'h0F0; 4'd3: pal = 12'hF00;
            4'd4: pal = 12'h888; 4'd5: pal = 12'hFFF; 4'd6: pal = 12'hFF0; 4'd7: pal = 12'h00F;
            default: pal = 12'h000;
        endcase
    endfunction

    logic [3:0] ref_fb [0:2047];

    // NOTE: drive DUT inputs #1 after the clock edge so tb stimulus is ordered
    // after the DUT's always_ff sampling (avoids same-edge scheduling races).
    task automatic axi_wr(input integer x, input integer y, input integer color);
        begin
            @(posedge aclk); #1;
            awaddr = (((y<<6)|x)<<2); awvalid = 1'b1;
            wdata  = color;           wvalid  = 1'b1; wstrb = 4'hF; bready = 1'b1;
            wait (awready && wready);
            @(posedge aclk); #1;
            awvalid = 1'b0; wvalid = 1'b0;
            wait (bvalid);
            @(posedge aclk); #1;
            bready = 1'b0;
            ref_fb[((y<<6)|x)] = color[3:0];
        end
    endtask

    task automatic axi_rd(input integer x, input integer y, output integer got);
        begin
            @(posedge aclk); #1;
            araddr = (((y<<6)|x)<<2); arvalid = 1'b1; rready = 1'b1;
            wait (arready);
            @(posedge aclk); #1;
            arvalid = 1'b0;
            wait (rvalid);
            got = rdata & 8'hFF;
            @(posedge aclk); #1;
            rready = 1'b0;
        end
    endtask

    // ---- reference model of the 2-cycle pixel pipeline ----
    logic [11:0] exp_p1, exp_p2;
    logic [11:0] act_rgb;
    assign act_rgb = {vga_r, vga_g, vga_b};

    wire        t0_active = dut.active;
    wire [11:0] t0_x      = dut.pix_x;
    wire [11:0] t0_y      = dut.pix_y;

    logic        checking = 0;
    int          pix_seen = 0;
    logic [10:0] mcell;
    logic [11:0] e0;

    always @(posedge pclk) begin
        mcell  = { t0_y[8:4], t0_x[9:4] };
        e0     = t0_active ? pal(ref_fb[mcell]) : 12'h000;
        exp_p2 <= exp_p1;
        exp_p1 <= e0;
        if (checking) begin
            pix_seen = pix_seen + 1;
            if (act_rgb !== exp_p2) begin
                if (errors < 10)
                    $display("  MISMATCH @seen=%0d out=%03h exp=%03h (x=%0d y=%0d)",
                             pix_seen, act_rgb, exp_p2, t0_x, t0_y);
                errors = errors + 1;
            end
        end
    end

    integer i;
    integer g;
    initial begin
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wstrb=4'hF;
        for (i=0;i<2048;i=i+1) ref_fb[i] = 4'h0;
        repeat (4) @(posedge aclk);
        aresetn = 1;
        repeat (4) @(posedge pclk);
        prst_n = 1;

        axi_wr(0,   0, 4);
        axi_wr(39,  0, 4);
        axi_wr(2,   1, 3);
        axi_wr(5,   5, 1);
        axi_wr(6,   5, 2);
        axi_wr(39, 29, 4);

        axi_rd(6,5,g); if (g!==2) begin $display("  READBACK FAIL (6,5)=%0d exp 2",g); errors=errors+1; end
        else $display("  ok  : readback (6,5) = %0d", g);
        axi_rd(2,1,g); if (g!==3) begin $display("  READBACK FAIL (2,1)=%0d exp 3",g); errors=errors+1; end
        else $display("  ok  : readback (2,1) = %0d", g);

        @(negedge vga_vs);
        @(posedge vga_vs);
        repeat (3) @(posedge pclk);
        checking = 1;
        repeat (800*525) @(posedge pclk);
        checking = 0;

        $display("=== vga_ctrl checks ===");
        $display("  pixels checked : %0d", pix_seen);
        if (errors == 0) $display("RESULT: ALL PASS");
        else             $display("RESULT: %0d FAILURE(S)", errors);
        $finish;
    end

    initial begin #300_000_000; $display("RESULT: TIMEOUT"); $finish; end
endmodule
