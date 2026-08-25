// tb_vga_fb.sv -- self-checking testbench for vga_fb (DOOM pixel framebuffer).
//   1. loads a small palette + writes framebuffer words over AXI4-Lite
//   2. reads a couple back (write-path check)
//   3. scans one full frame and verifies every output pixel against a
//      reference model of the 320x200 doubling + palette + 3-cycle pipeline.
`timescale 1ns/1ps

module tb_vga_fb;
    localparam int ADDR_W = 17;

    logic aclk = 0; always #16 aclk = ~aclk;   // ~31 MHz
    logic pclk = 0; always #20 pclk = ~pclk;   // 25 MHz
    logic aresetn = 0, prst_n = 0;

    logic [ADDR_W-1:0] awaddr, araddr;
    logic              awvalid, awready, wvalid, wready, bvalid, bready;
    logic [31:0]       wdata, rdata;
    logic [3:0]        wstrb;
    logic [1:0]        bresp, rresp;
    logic              arvalid, arready, rvalid, rready;
    logic [3:0]        vga_r, vga_g, vga_b;
    logic              vga_hs, vga_vs;

    vga_fb #(.ADDR_W(ADDR_W)) dut (
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

    // reference mirrors
    logic [31:0] ref_fb  [0:16383];
    logic [11:0] ref_pal [0:255];

    task automatic axi_wr(input [ADDR_W-1:0] a, input [31:0] d);
        begin
            @(posedge aclk); #1;
            awaddr = a; awvalid = 1'b1; wdata = d; wvalid = 1'b1; wstrb = 4'hF; bready = 1'b1;
            wait (awready && wready);
            @(posedge aclk); #1;
            awvalid = 1'b0; wvalid = 1'b0;
            wait (bvalid);
            @(posedge aclk); #1;
            bready = 1'b0;
        end
    endtask

    task automatic fb_write(input int word, input [31:0] d);
        begin axi_wr(word<<2, d); ref_fb[word] = d; end
    endtask

    task automatic pal_write(input int idx, input [31:0] rgb888);
        begin
            axi_wr((1<<16) | (idx<<2), rgb888);
            ref_pal[idx] = {rgb888[23:20], rgb888[15:12], rgb888[7:4]};
        end
    endtask

    task automatic axi_rd(input [ADDR_W-1:0] a, output [31:0] d);
        begin
            @(posedge aclk); #1;
            araddr = a; arvalid = 1'b1; rready = 1'b1;
            wait (arready); @(posedge aclk); #1;
            arvalid = 1'b0;
            wait (rvalid); d = rdata;
            @(posedge aclk); #1; rready = 1'b0;
        end
    endtask

    // reference colour for a screen pixel (stage-0 signals)
    function automatic [11:0] expect_rgb(input logic act, input [11:0] x, input [11:0] y);
        int px, py, idx, word, lane, b;
        begin
            if (act && y >= 40 && y < 440) begin
                px = x >> 1; py = (y - 40) >> 1;
                idx = py*320 + px; word = idx >> 2; lane = idx & 3;
                b = (ref_fb[word] >> (lane*8)) & 8'hFF;
                expect_rgb = ref_pal[b];
            end else expect_rgb = 12'h000;
        end
    endfunction

    // 3-deep pipeline of expected colour, aligned to the DUT output
    logic [11:0] e1, e2, e3;
    wire  [11:0] act_rgb = {vga_r, vga_g, vga_b};
    logic checking = 0;
    int   pix_seen = 0;
    always @(posedge pclk) begin
        e3 <= e2; e2 <= e1;
        e1 <= expect_rgb(dut.active, dut.sx, dut.sy);
        if (checking) begin
            pix_seen = pix_seen + 1;
            if (act_rgb !== e3) begin
                if (errors < 10)
                    $display("  MISMATCH @%0d out=%03h exp=%03h (sx=%0d sy=%0d)",
                             pix_seen, act_rgb, e3, dut.sx, dut.sy);
                errors = errors + 1;
            end
        end
    end

    logic [31:0] rb;
    int i;
    initial begin
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wstrb=4'hF;
        for (i=0;i<16384;i++) ref_fb[i]=0;
        for (i=0;i<256;i++) ref_pal[i]={i[7:4],i[7:4],i[7:4]}; // HW default
        repeat (4) @(posedge aclk); aresetn = 1;
        repeat (4) @(posedge pclk); prst_n = 1;

        // palette: 1=red 2=green 3=blue 4=white
        pal_write(1, 32'h00FF0000);
        pal_write(2, 32'h0000FF00);
        pal_write(3, 32'h000000FF);
        pal_write(4, 32'h00FFFFFF);

        // framebuffer: word0 = pixels (0,0)=1 (1,0)=2 (2,0)=3 (3,0)=4
        fb_write(0, 32'h04030201);
        // a pixel in the middle: (160,100) -> idx=100*320+160=32160, word=8040, lane0
        fb_write(8040, 32'h00000001);            // src(160,100)=red

        // write-path read-back
        axi_rd(0<<2, rb);
        if (rb !== 32'h04030201) begin $display("  RB word0=%08h exp 04030201", rb); errors++; end
        else $display("  ok  : readback word0 = %08h", rb);
        axi_rd((1<<16)|(4<<2), rb);              // palette[4]
        if ((rb & 12'hFFF) !== 12'hFFF) begin $display("  RB pal4=%03h exp fff", rb&12'hFFF); errors++; end
        else $display("  ok  : readback pal[4] = %03h", rb & 12'hFFF);

        // scan one frame
        @(negedge vga_vs); @(posedge vga_vs);
        repeat (4) @(posedge pclk);
        checking = 1;
        repeat (800*525) @(posedge pclk);
        checking = 0;

        $display("=== vga_fb checks ===");
        $display("  pixels checked : %0d", pix_seen);
        if (errors == 0) $display("RESULT: ALL PASS");
        else             $display("RESULT: %0d FAILURE(S)", errors);
        $finish;
    end

    initial begin #400_000_000; $display("RESULT: TIMEOUT"); $finish; end
endmodule
