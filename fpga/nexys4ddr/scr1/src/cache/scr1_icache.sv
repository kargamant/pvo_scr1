`timescale 1ns/1ps

`include "scr1_arch_description.svh"
`include "scr1_memif.svh"

module scr1_icache #(
    parameter logic [`SCR1_IMEM_AWIDTH-1:0] CACHEABLE_BRAM_ADDR_MASK    = '0,
    parameter logic [`SCR1_IMEM_AWIDTH-1:0] CACHEABLE_BRAM_ADDR_PATTERN = '0,
    parameter logic [`SCR1_IMEM_AWIDTH-1:0] CACHEABLE_DDR_ADDR_MASK    = '0,
    parameter logic [`SCR1_IMEM_AWIDTH-1:0] CACHEABLE_DDR_ADDR_PATTERN = '0,
    parameter int unsigned                  NUM_LINES              = 64,
    parameter int unsigned                  LINE_WORDS             = 4
) (
    input  logic                              clk,
    input  logic                              rst_n,

    input  logic                              invalidate_i,
    output logic                              invalidate_ack_o,

    output logic                              cpu_req_ack_o,
    input  logic                              cpu_req_i,
    input  type_scr1_mem_cmd_e                cpu_cmd_i,
    input  logic [`SCR1_IMEM_AWIDTH-1:0]       cpu_addr_i,
    output logic [`SCR1_IMEM_DWIDTH-1:0]       cpu_rdata_o,
    output type_scr1_mem_resp_e               cpu_resp_o,

    input  logic                              mem_req_ack_i,
    output logic                              mem_req_o,
    output type_scr1_mem_cmd_e                mem_cmd_o,
    output logic [`SCR1_IMEM_AWIDTH-1:0]       mem_addr_o,
    input  logic [`SCR1_IMEM_DWIDTH-1:0]       mem_rdata_i,
    input  type_scr1_mem_resp_e               mem_resp_i
);

    localparam int unsigned BYTE_OFFSET_BITS = 2;
    localparam int unsigned WORD_INDEX_BITS  = $clog2(LINE_WORDS);
    localparam int unsigned LINE_OFFSET_BITS = BYTE_OFFSET_BITS + WORD_INDEX_BITS;
    localparam int unsigned LINE_INDEX_BITS  = $clog2(NUM_LINES);
    localparam int unsigned CACHE_WORDS      = NUM_LINES * LINE_WORDS;
    localparam int unsigned CACHE_ADDR_BITS  = $clog2(CACHE_WORDS);
    localparam int unsigned TAG_BITS         = `SCR1_IMEM_AWIDTH
                                               - LINE_OFFSET_BITS
                                               - LINE_INDEX_BITS;

    typedef enum logic [3:0] {
        IC_IDLE,
        IC_LOOKUP,
        IC_FILL_REQ,
        IC_FILL_WAIT,
        IC_BYPASS_REQ,
        IC_BYPASS_WAIT,
        IC_RESP_OK,
        IC_RESP_ERR,
        IC_INVALIDATE,
        IC_INVALIDATE_ACK
    } icache_state_e;

    icache_state_e state_q;
    icache_state_e state_d;

    (* ram_style = "block" *)
    logic [`SCR1_IMEM_DWIDTH-1:0] data_mem [0:CACHE_WORDS-1];
    logic [TAG_BITS-1:0]          tag_mem  [0:NUM_LINES-1];
    logic [NUM_LINES-1:0]         valid_q;

    logic [`SCR1_IMEM_AWIDTH-1:0] req_addr_q;
    type_scr1_mem_cmd_e           req_cmd_q;
    logic [WORD_INDEX_BITS-1:0]   fill_word_q;
    logic [`SCR1_IMEM_DWIDTH-1:0] response_data_q;

    logic [LINE_INDEX_BITS-1:0]   req_line_index;
    logic [WORD_INDEX_BITS-1:0]   req_word_index;
    logic [CACHE_ADDR_BITS-1:0]   cpu_data_index;
    logic [CACHE_ADDR_BITS-1:0]   req_data_index;
    logic [CACHE_ADDR_BITS-1:0]   fill_data_index;
    logic [`SCR1_IMEM_DWIDTH-1:0] data_mem_rdata_q;
    logic [TAG_BITS-1:0]          req_tag;
    logic                         req_cacheable;
    logic                         req_hit;
    logic [`SCR1_IMEM_AWIDTH-1:0] fill_addr;

    integer line;

    initial begin
        if (LINE_WORDS < 2 || (LINE_WORDS & (LINE_WORDS - 1)) != 0) begin
            $error("scr1_icache: LINE_WORDS must be a power of two and >= 2");
        end
        if (NUM_LINES < 2 || (NUM_LINES & (NUM_LINES - 1)) != 0) begin
            $error("scr1_icache: NUM_LINES must be a power of two and >= 2");
        end
        if (`SCR1_IMEM_DWIDTH != 32) begin
            $error("scr1_icache: this implementation requires a 32-bit memory word");
        end
    end

    assign req_word_index = req_addr_q[BYTE_OFFSET_BITS +: WORD_INDEX_BITS];
    assign req_line_index = req_addr_q[LINE_OFFSET_BITS +: LINE_INDEX_BITS];
    assign cpu_data_index = {
        cpu_addr_i[LINE_OFFSET_BITS +: LINE_INDEX_BITS],
        cpu_addr_i[BYTE_OFFSET_BITS +: WORD_INDEX_BITS]
    };
    assign req_data_index = {req_line_index, req_word_index};
    assign fill_data_index = {req_line_index, fill_word_q};
    assign req_tag        = req_addr_q[`SCR1_IMEM_AWIDTH-1 -: TAG_BITS];

    assign req_cacheable = ((req_addr_q & CACHEABLE_BRAM_ADDR_MASK) == CACHEABLE_BRAM_ADDR_PATTERN) ||
                            ((req_addr_q & CACHEABLE_DDR_ADDR_MASK) == CACHEABLE_DDR_ADDR_PATTERN);
    assign req_hit       = valid_q[req_line_index]
                         && (tag_mem[req_line_index] == req_tag);

    always_comb begin
        fill_addr = req_addr_q;
        fill_addr[LINE_OFFSET_BITS-1:0] = '0;
        fill_addr[BYTE_OFFSET_BITS +: WORD_INDEX_BITS] = fill_word_q;
    end

    always_comb begin
        state_d = state_q;

        unique case (state_q)
            IC_IDLE: begin
                if (invalidate_i) begin
                    state_d = IC_INVALIDATE;
                end else if (cpu_req_i) begin
                    state_d = IC_LOOKUP;
                end
            end

            IC_LOOKUP: begin
                if (req_cmd_q != SCR1_MEM_CMD_RD) begin
                    state_d = IC_RESP_ERR;
                end else if (!req_cacheable) begin
                    state_d = IC_BYPASS_REQ;
                end else if (req_hit) begin
                    state_d = IC_RESP_OK;
                end else begin
                    state_d = IC_FILL_REQ;
                end
            end

            IC_FILL_REQ: begin
                if (mem_req_ack_i) begin
                    state_d = IC_FILL_WAIT;
                end
            end

            IC_FILL_WAIT: begin
                if (mem_resp_i == SCR1_MEM_RESP_RDY_ER) begin
                    state_d = IC_RESP_ERR;
                end else if (mem_resp_i == SCR1_MEM_RESP_RDY_OK) begin
                    if (fill_word_q == WORD_INDEX_BITS'(LINE_WORDS - 1)) begin
                        state_d = IC_RESP_OK;
                    end else begin
                        state_d = IC_FILL_REQ;
                    end
                end
            end

            IC_BYPASS_REQ: begin
                if (mem_req_ack_i) begin
                    state_d = IC_BYPASS_WAIT;
                end
            end

            IC_BYPASS_WAIT: begin
                if (mem_resp_i == SCR1_MEM_RESP_RDY_ER) begin
                    state_d = IC_RESP_ERR;
                end else if (mem_resp_i == SCR1_MEM_RESP_RDY_OK) begin
                    state_d = IC_RESP_OK;
                end
            end

            IC_RESP_OK,
            IC_RESP_ERR: begin
                state_d = IC_IDLE;
            end

            IC_INVALIDATE: begin
                state_d = IC_INVALIDATE_ACK;
            end

            IC_INVALIDATE_ACK: begin
                if (!invalidate_i) begin
                    state_d = IC_IDLE;
                end
            end

            default: begin
                state_d = IC_IDLE;
            end
        endcase
    end

    always_comb begin
        cpu_req_ack_o       = 1'b0;
        cpu_rdata_o         = response_data_q;
        cpu_resp_o          = SCR1_MEM_RESP_NOTRDY;
        invalidate_ack_o    = 1'b0;

        mem_req_o           = 1'b0;
        mem_cmd_o           = SCR1_MEM_CMD_RD;
        mem_addr_o          = '0;

        if ((state_q == IC_IDLE) && !invalidate_i) begin
            cpu_req_ack_o = 1'b1;
        end

        if (state_q == IC_FILL_REQ) begin
            mem_req_o  = 1'b1;
            mem_addr_o = fill_addr;
        end else if (state_q == IC_BYPASS_REQ) begin
            mem_req_o  = 1'b1;
            mem_addr_o = req_addr_q;
        end

        if (state_q == IC_RESP_OK) begin
            cpu_resp_o = SCR1_MEM_RESP_RDY_OK;
        end else if (state_q == IC_RESP_ERR) begin
            cpu_resp_o = SCR1_MEM_RESP_RDY_ER;
        end

        if (state_q == IC_INVALIDATE_ACK) begin
            invalidate_ack_o = 1'b1;
        end
    end

    // Cache memories have no reset. Their contents are ignored whenever the
    // corresponding valid bit is clear. Keeping all memory accesses in this
    // clock-only process matches the synchronous RAM inference template.
    always_ff @(posedge clk) begin
        if ((state_q == IC_IDLE) && cpu_req_i && cpu_req_ack_o) begin
            data_mem_rdata_q <= data_mem[cpu_data_index];
        end

        if ((state_q == IC_FILL_WAIT)
            && (mem_resp_i == SCR1_MEM_RESP_RDY_OK)) begin
            data_mem[fill_data_index] <= mem_rdata_i;

            if (fill_word_q == WORD_INDEX_BITS'(LINE_WORDS - 1)) begin
                tag_mem[req_line_index] <= req_tag;
            end
        end
    end

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            state_q        <= IC_IDLE;
            valid_q        <= '0;
            req_addr_q     <= '0;
            req_cmd_q      <= SCR1_MEM_CMD_RD;
            fill_word_q    <= '0;
            response_data_q <= '0;
        end else begin
            state_q <= state_d;

            if ((state_q == IC_IDLE) && cpu_req_i && cpu_req_ack_o) begin
                req_addr_q <= cpu_addr_i;
                req_cmd_q  <= cpu_cmd_i;
            end

            if ((state_q == IC_LOOKUP) && req_cacheable && !req_hit) begin
                fill_word_q            <= '0;
                valid_q[req_line_index] <= 1'b0;
            end

            if ((state_q == IC_LOOKUP) && req_cacheable && req_hit
                && (req_cmd_q == SCR1_MEM_CMD_RD)) begin
                response_data_q <= data_mem_rdata_q;
            end

            if ((state_q == IC_FILL_WAIT)
                && (mem_resp_i == SCR1_MEM_RESP_RDY_OK)) begin
                if (fill_word_q == req_word_index) begin
                    response_data_q <= mem_rdata_i;
                end

                if (fill_word_q == WORD_INDEX_BITS'(LINE_WORDS - 1)) begin
                    valid_q[req_line_index]   <= 1'b1;
                end else begin
                    fill_word_q <= fill_word_q + 1'b1;
                end
            end

            if ((state_q == IC_BYPASS_WAIT)
                && (mem_resp_i == SCR1_MEM_RESP_RDY_OK)) begin
                response_data_q <= mem_rdata_i;
            end

            if (state_q == IC_INVALIDATE) begin
                for (line = 0; line < NUM_LINES; line = line + 1) begin
                    valid_q[line] <= 1'b0;
                end
            end
        end
    end

endmodule
