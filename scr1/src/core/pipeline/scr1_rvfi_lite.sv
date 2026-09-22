/// SCR1 RVFI-lite retire tap (synthesizable) — on-chip co-verification (Stage 3).
///
/// Samples the committed-instruction stream at the EXU retire point and packs one 128-bit
/// record per retired instruction, and drives a capture buffer (trace BRAM port A) that
/// records from reset until full, then freezes. The PS reads the buffer + record count and
/// diffs against the ISA reference model (sim/rvfi_coverif/refmodel.c).
///
/// Record layout (128 bits, matches refmodel's `RVFI ... ` fields):
///   [31:0]    pc        (retiring instruction PC)
///   [63:32]   pc_next   (architectural next PC)
///   [95:64]   rd_wdata  (0 if no write / write x0)
///   [100:96]  rd_addr   (0 if no write / write x0)
///   [101]     trap      (retired WITH exception)
///   [127:102] reserved  (0)
///
/// Pure observation of the core: no back-pressure on the pipeline (capture-until-full).
module scr1_rvfi_lite #(
    parameter int unsigned ADDR_W = 13            // capture depth = 2^ADDR_W records (8192)
) (
    input  logic                 clk,
    input  logic                 rst_n,
    // retire tap (from scr1_pipe_top)
    input  logic                 instret,          // instruction retired (valid)
    input  logic                 instret_nexc,     // retired without exception
    input  logic [31:0]          pc,               // retiring PC
    input  logic [31:0]          pc_next,          // next PC
    input  logic                 rd_wen,           // MPRF write request
    input  logic [4:0]           rd_addr,          // rd write address
    input  logic [31:0]          rd_wdata,         // rd write data
    // packed record + strobe (observation)
    output logic                 rvfi_valid,
    output logic [127:0]         rvfi_rec,
    // trace-BRAM port A (128-bit): capture-until-full, then freeze
    output logic                 trace_we,
    output logic [ADDR_W-1:0]    trace_waddr,
    output logic [127:0]         trace_wdata,
    output logic [31:0]          trace_count       // records captured so far (PS reads this)
);
    localparam logic [ADDR_W:0] DEPTH = (ADDR_W+1)'(1) << ADDR_W;

    logic        wr;
    logic [ADDR_W:0] cnt;
    logic        full;

    assign wr         = rd_wen & (rd_addr != 5'd0);
    assign rvfi_valid = instret;
    assign rvfi_rec   = {26'd0, ~instret_nexc, (wr ? rd_addr : 5'd0),
                         (wr ? rd_wdata : 32'd0), pc_next, pc};

    assign full        = (cnt == DEPTH);
    assign trace_we    = instret & ~full;
    assign trace_waddr = cnt[ADDR_W-1:0];
    assign trace_wdata = rvfi_rec;
    assign trace_count = {{(31-ADDR_W){1'b0}}, cnt};

    always_ff @(posedge clk) begin
        if (~rst_n) cnt <= '0;
        else if (trace_we) cnt <= cnt + 1'b1;
    end
endmodule
