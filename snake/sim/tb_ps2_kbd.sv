// ============================================================================
// tb_ps2_kbd.sv  --  self-checking testbench for ps2_kbd (Phase 3)
//   1. bit-bangs PS/2 frames on the pins (start/8data-LSB/odd-parity/stop)
//   2. reads STATUS/DATA over AXI4-Lite and checks scancodes come out in order
//   3. includes a WASD sequence and a break (0xF0 xx) sequence
// Run: see snake/sim/run.sh
// ============================================================================
`timescale 1ns/1ps

module tb_ps2_kbd;
    localparam int ADDR_W = 8;
    localparam     HALF    = 1000;   // PS/2 half-bit in ns (sim-fast, ~500 kHz)

    logic aclk = 0; always #16 aclk = ~aclk;   // ~31 MHz
    logic aresetn = 0;

    logic [ADDR_W-1:0] awaddr, araddr;
    logic              awvalid, awready, wvalid, wready, bvalid, bready;
    logic [31:0]       wdata, rdata;
    logic [3:0]        wstrb;
    logic [1:0]        bresp, rresp;
    logic              arvalid, arready, rvalid, rready;

    logic ps2_clk = 1, ps2_data = 1;

    ps2_kbd #(.ADDR_W(ADDR_W)) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'b0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(3'b0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data)
    );

    int errors = 0;

    // ---- PS/2 bit-bang ----
    task automatic ps2_bit(input v);
        begin
            ps2_data = v;
            #HALF; ps2_clk = 1'b0;   // falling edge -> receiver samples
            #HALF; ps2_clk = 1'b1;
        end
    endtask

    task automatic ps2_send(input [7:0] b);
        integer i;
        reg par;
        begin
            par = ~(^b);             // odd parity
            ps2_bit(1'b0);           // start
            for (i=0;i<8;i=i+1) ps2_bit(b[i]);
            ps2_bit(par);            // parity
            ps2_bit(1'b1);           // stop
            #HALF;                   // idle gap
        end
    endtask

    // ---- AXI reads (#1 after edge to avoid same-edge races) ----
    task automatic axi_rd(input integer word_off, output integer val);
        begin
            @(posedge aclk); #1;
            araddr = word_off<<2; arvalid = 1'b1; rready = 1'b1;
            wait (arready);
            @(posedge aclk); #1;
            arvalid = 1'b0;
            wait (rvalid);
            val = rdata;
            @(posedge aclk); #1;
            rready = 1'b0;
        end
    endtask

    task automatic get_scancode(output integer code);
        integer st;
        begin
            st = 0;
            // poll STATUS until data_valid
            while ((st & 1) == 0) axi_rd(0, st);
            axi_rd(1, code);        // read DATA (pops)
            code = code & 8'hFF;
        end
    endtask

    integer got;
    initial begin
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wstrb=4'hF;
        repeat (4) @(posedge aclk);
        aresetn = 1;
        repeat (4) @(posedge aclk);

        // STATUS should be empty at start
        axi_rd(0, got);
        if ((got & 1) !== 0) begin $display("  FAIL: STATUS not empty at reset (%0h)", got); errors++; end
        else $display("  ok  : STATUS empty at reset");

        // send W, A, S, D  then a break (F0, 1D)
        ps2_send(8'h1D);  // W
        ps2_send(8'h1C);  // A
        ps2_send(8'h1B);  // S
        ps2_send(8'h23);  // D
        ps2_send(8'hF0);  // break prefix
        ps2_send(8'h1D);  // W release

        // read them back in order
        check_code(8'h1D, "W");
        check_code(8'h1C, "A");
        check_code(8'h1B, "S");
        check_code(8'h23, "D");
        check_code(8'hF0, "break");
        check_code(8'h1D, "W-rel");

        // FIFO should now be empty
        axi_rd(0, got);
        if ((got & 1) !== 0) begin $display("  FAIL: STATUS not empty after drain (%0h)", got); errors++; end
        else $display("  ok  : STATUS empty after drain");

        $display("=== ps2_kbd checks ===");
        if (errors == 0) $display("RESULT: ALL PASS");
        else             $display("RESULT: %0d FAILURE(S)", errors);
        $finish;
    end

    task automatic check_code(input [7:0] exp, input string nm);
        integer c;
        begin
            get_scancode(c);
            if (c !== exp) begin
                $display("  FAIL: %-6s got %02h exp %02h", nm, c[7:0], exp);
                errors++;
            end else
                $display("  ok  : %-6s = %02h", nm, c[7:0]);
        end
    endtask

    initial begin #500_000_000; $display("RESULT: TIMEOUT"); $finish; end
endmodule
