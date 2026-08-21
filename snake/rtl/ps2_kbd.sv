// ============================================================================
// ps2_kbd.sv  --  AXI4-Lite PS/2 keyboard (Phase 3)
//
// Wraps ps2_rx + a 16-entry scancode FIFO behind AXI4-Lite.
// Base 0xFF03_0000. Registers (word offsets):
//   0x00 STATUS (RO): bit0 = data_valid (FIFO not empty)
//                     bit1 = overflow (sticky; cleared by reading DATA when empty)
//   0x04 DATA   (RO): bits[7:0] = oldest scancode; reading POPS the FIFO
// Writes are accepted and ignored (no writable registers).
//
// Everything is in the aclk domain (PS2_CLK is ~10-16 kHz, far slower).
// Scancodes are raw set-2. See doc/hw_contract.md.
// ============================================================================
`timescale 1ns/1ps

module ps2_kbd #(
    parameter int ADDR_W   = 8,
    parameter int FIFO_LOG2 = 4          // 16 entries
) (
    input  logic                aclk,
    input  logic                aresetn,     // active low

    // AXI4-Lite slave
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

    // PS/2 pins (async)
    input  logic                ps2_clk,
    input  logic                ps2_data
);
    localparam int DEPTH = (1 << FIFO_LOG2);

    // ---------------- receiver ----------------
    logic [7:0] rx_data;
    logic       rx_strobe, rx_perr;
    ps2_rx u_rx (
        .clk(aclk), .rst_n(aresetn),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .rx_data(rx_data), .rx_strobe(rx_strobe), .rx_perr(rx_perr)
    );

    // ---------------- FIFO --------------------
    logic [7:0]           fifo [0:DEPTH-1];
    logic [FIFO_LOG2-1:0] wr_ptr, rd_ptr;
    logic [FIFO_LOG2:0]   count;             // 0..DEPTH
    logic                 overflow;
    wire empty = (count == 0);
    wire full  = (count == DEPTH[FIFO_LOG2:0]);

    logic do_pop;                            // asserted by read channel

    wire push = rx_strobe & ~full;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_ptr   <= '0;
            rd_ptr   <= '0;
            count    <= '0;
            overflow <= 1'b0;
        end else begin
            // write
            if (push) begin
                fifo[wr_ptr] <= rx_data;
                wr_ptr       <= wr_ptr + 1'b1;
            end
            if (rx_strobe & full & ~do_pop) overflow <= 1'b1;  // dropped a code
            // read
            if (do_pop && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            // count
            case ({push, (do_pop && !empty)})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    wire [7:0] fifo_head = fifo[rd_ptr];

    // ---------------- AXI write (accept & ignore) ----------------
    // Registered awready/wready (no combinational valid->ready loop with the
    // SmartConnect -- see the vga_ctrl write channel for why this matters).
    typedef enum logic [0:0] { W_IDLE, W_RESP } wstate_e;
    wstate_e wstate;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wstate        <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            case (wstate)
                W_IDLE: if (s_axi_awvalid && s_axi_wvalid) begin
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

    // ---------------- AXI read ----------------
    typedef enum logic [1:0] { R_IDLE, R_DATA } rstate_e;
    rstate_e rstate;
    logic    rd_is_data;                     // selected register was DATA (0x04)

    // register select computed outside always (avoids iverilog const-select quirk)
    wire ar_is_data = (s_axi_araddr[3:2] == 2'b01);   // 0x04 = DATA, 0x00 = STATUS

    assign s_axi_arready = (rstate == R_IDLE);
    assign do_pop = (rstate == R_DATA) && rd_is_data &&
                    s_axi_rvalid && s_axi_rready && !empty;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rstate       <= R_IDLE;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
            s_axi_rdata  <= 32'h0;
            rd_is_data   <= 1'b0;
        end else begin
            case (rstate)
                R_IDLE: if (s_axi_arvalid) begin
                    rd_is_data <= ar_is_data;                     // 0x04 = DATA
                    // latch response data now (both regs are combinational)
                    if (ar_is_data)
                        s_axi_rdata <= {24'h0, fifo_head};
                    else
                        s_axi_rdata <= {30'h0, overflow, ~empty}; // STATUS
                    s_axi_rresp  <= 2'b00;
                    s_axi_rvalid <= 1'b1;
                    rstate       <= R_DATA;
                end
                R_DATA: if (s_axi_rvalid && s_axi_rready) begin
                    s_axi_rvalid <= 1'b0;
                    rstate       <= R_IDLE;
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

    // silence unused
    wire _unused = &{1'b0, s_axi_awaddr, s_axi_awprot, s_axi_arprot,
                     s_axi_wdata, s_axi_wstrb, rx_perr, 1'b0};

endmodule
