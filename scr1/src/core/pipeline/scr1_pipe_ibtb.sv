/// @file       <scr1_pipe_ibtb.sv>
/// @brief      Indirect Branch Target Buffer (I-BTB)
///
// Functionality:
// - Last-target cache for NON-return indirect jumps (jalr / c.jr / c.jalr).
// - Directly-mapped, tagged, indexed by the call-site PC (half-word granular).
// - Trained by the EXU with the resolved target of each retired indirect jump.
// - Read at the queue-head PC; a hit drives a head-side redirect (mirrors the RAS),
//   verified in the EXU (target == actual) so a wrong prediction costs only a flush.
//
// Returns are handled by the RAS (higher priority at predict), so this cache is only
// consulted for non-return indirect transfers; training the odd return call-site here
// is harmless (RAS always wins the prediction).

`include "scr1_arch_description.svh"

`ifdef SCR1_BP_IBTB

module scr1_pipe_ibtb #(
    parameter int unsigned SCR1_IBTB_SIZE  = 64,
    parameter int unsigned SCR1_IBTB_IDX_W = 6
) (
    input   logic                       clk,
    input   logic                       rst_n,

    // Read / query port (queue-head PC)
    input   logic [`SCR1_XLEN-1:0]      ibtb_query_pc_i,
    output  logic                       ibtb_hit_o,         // entry valid for this index
    output  logic [`SCR1_XLEN-1:0]      ibtb_target_o,      // cached last target

    // Train port: pulse on a resolved indirect jump at retire
    input   logic                       ibtb_upd_vd_i,      // one-shot at retire
    input   logic [`SCR1_XLEN-1:0]      ibtb_upd_pc_i,      // call-site PC of the indirect jump
    input   logic [`SCR1_XLEN-1:0]      ibtb_upd_target_i   // resolved target
);

// Half-word granular index/tag (indirect jumps can sit on any 2-byte boundary).
localparam int unsigned SCR1_IBTB_TAG_W = `SCR1_XLEN - (SCR1_IBTB_IDX_W + 1);

logic [SCR1_IBTB_IDX_W-1:0]         rd_idx;
logic [SCR1_IBTB_IDX_W-1:0]         wr_idx;
logic [SCR1_IBTB_TAG_W-1:0]         rd_tag;
logic [SCR1_IBTB_TAG_W-1:0]         wr_tag;

assign rd_idx = ibtb_query_pc_i[SCR1_IBTB_IDX_W:1];
assign wr_idx = ibtb_upd_pc_i  [SCR1_IBTB_IDX_W:1];
assign rd_tag = ibtb_query_pc_i[`SCR1_XLEN-1:SCR1_IBTB_IDX_W+1];
assign wr_tag = ibtb_upd_pc_i  [`SCR1_XLEN-1:SCR1_IBTB_IDX_W+1];

logic [SCR1_IBTB_SIZE-1:0]          valid_q;
logic [SCR1_IBTB_TAG_W-1:0]         tag_q    [SCR1_IBTB_SIZE];
logic [`SCR1_XLEN-1:0]              target_q [SCR1_IBTB_SIZE];

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        valid_q <= '0;
    end else if (ibtb_upd_vd_i) begin
        valid_q[wr_idx] <= 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (ibtb_upd_vd_i) begin
        tag_q[wr_idx]    <= wr_tag;
        target_q[wr_idx] <= ibtb_upd_target_i;
    end
end

assign ibtb_hit_o    = valid_q[rd_idx] & (tag_q[rd_idx] == rd_tag);
assign ibtb_target_o = target_q[rd_idx];

endmodule : scr1_pipe_ibtb

`endif // SCR1_BP_IBTB
