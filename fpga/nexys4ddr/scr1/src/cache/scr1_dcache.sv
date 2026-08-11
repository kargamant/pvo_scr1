`timescale 1ns/1ps

`include "scr1_arch_description.svh"
`include "scr1_memif.svh"

module scr1_dcache #(
    parameter logic [`SCR1_DMEM_AWIDTH-1:0] CACHEABLE_ADDR_MASK    = '0,
    parameter logic [`SCR1_DMEM_AWIDTH-1:0] CACHEABLE_ADDR_PATTERN = '0,
    parameter int unsigned                  NUM_LINES              = 64,
    parameter int unsigned                  LINE_WORDS             = 4
) (
    input  logic                              clk,
    input  logic                              rst_n,

    input  logic                              flush_i,
    output logic                              flush_ack_o,

    output logic                              cpu_req_ack_o,
    input  logic                              cpu_req_i,
    input  type_scr1_mem_cmd_e                cpu_cmd_i,
    input  type_scr1_mem_width_e              cpu_width_i,
    input  logic [`SCR1_DMEM_AWIDTH-1:0]       cpu_addr_i,
    input  logic [`SCR1_DMEM_DWIDTH-1:0]       cpu_wdata_i,
    output logic [`SCR1_DMEM_DWIDTH-1:0]       cpu_rdata_o,
    output type_scr1_mem_resp_e               cpu_resp_o,

    input  logic                              mem_req_ack_i,
    output logic                              mem_req_o,
    output type_scr1_mem_cmd_e                mem_cmd_o,
    output type_scr1_mem_width_e              mem_width_o,
    output logic [`SCR1_DMEM_AWIDTH-1:0]       mem_addr_o,
    output logic [`SCR1_DMEM_DWIDTH-1:0]       mem_wdata_o,
    input  logic [`SCR1_DMEM_DWIDTH-1:0]       mem_rdata_i,
    input  type_scr1_mem_resp_e               mem_resp_i
);

    localparam int unsigned BYTE_OFFSET_BITS = 2;
    localparam int unsigned WORD_INDEX_BITS  = $clog2(LINE_WORDS);
    localparam int unsigned LINE_OFFSET_BITS = BYTE_OFFSET_BITS + WORD_INDEX_BITS;
    localparam int unsigned LINE_INDEX_BITS  = $clog2(NUM_LINES);
    localparam int unsigned CACHE_WORDS      = NUM_LINES * LINE_WORDS;
    localparam int unsigned CACHE_ADDR_BITS  = $clog2(CACHE_WORDS);
    localparam int unsigned TAG_BITS         = `SCR1_DMEM_AWIDTH
                                               - LINE_OFFSET_BITS
                                               - LINE_INDEX_BITS;

    typedef enum logic [3:0] {
        DC_IDLE,
        DC_LOOKUP,
        DC_FILL_REQ,
        DC_FILL_WAIT,
        DC_BYPASS_REQ,
        DC_BYPASS_WAIT,
        DC_RESP_OK,
        DC_RESP_ERR,
        DC_FLUSH,
        DC_FLUSH_ACK
    } dcache_state_e;

    dcache_state_e state_q;
    dcache_state_e state_d;

    (* ram_style = "block" *)
    logic [`SCR1_DMEM_DWIDTH-1:0] data_mem [0:CACHE_WORDS-1];
    logic [TAG_BITS-1:0]          tag_mem  [0:NUM_LINES-1];
    logic [NUM_LINES-1:0]         valid_q;

    logic [`SCR1_DMEM_AWIDTH-1:0] req_addr_q;
    logic [`SCR1_DMEM_DWIDTH-1:0] req_wdata_q;
    type_scr1_mem_cmd_e           req_cmd_q;
    type_scr1_mem_width_e         req_width_q;
    logic [WORD_INDEX_BITS-1:0]   fill_word_q;
    logic [`SCR1_DMEM_DWIDTH-1:0] response_data_q;

    logic [LINE_INDEX_BITS-1:0]   req_line_index;
    logic [WORD_INDEX_BITS-1:0]   req_word_index;
    logic [CACHE_ADDR_BITS-1:0]   cpu_data_index;
    logic [CACHE_ADDR_BITS-1:0]   req_data_index;
    logic [CACHE_ADDR_BITS-1:0]   fill_data_index;
    logic [`SCR1_DMEM_DWIDTH-1:0] data_mem_rdata_q;
    logic                         data_mem_write_en;
    logic [3:0]                   data_mem_write_byte_en;
    logic [CACHE_ADDR_BITS-1:0]   data_mem_write_addr;
    logic [`SCR1_DMEM_DWIDTH-1:0] data_mem_write_data;
    logic [TAG_BITS-1:0]          req_tag;
    logic                         req_cacheable;
    logic                         req_hit;
    logic [`SCR1_DMEM_AWIDTH-1:0] fill_addr;

    integer line;

    function automatic logic [`SCR1_DMEM_DWIDTH-1:0] select_load_data (
        input logic [`SCR1_DMEM_DWIDTH-1:0] word_data,
        input logic [1:0]                   byte_offset
    );
        select_load_data = word_data >> (8 * byte_offset);
    endfunction

    initial begin
        if (LINE_WORDS < 2 || (LINE_WORDS & (LINE_WORDS - 1)) != 0) begin
            $error("scr1_dcache: LINE_WORDS must be a power of two and >= 2");
        end
        if (NUM_LINES < 2 || (NUM_LINES & (NUM_LINES - 1)) != 0) begin
            $error("scr1_dcache: NUM_LINES must be a power of two and >= 2");
        end
        if (`SCR1_DMEM_DWIDTH != 32) begin
            $error("scr1_dcache: this implementation requires a 32-bit memory word");
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
    assign req_tag        = req_addr_q[`SCR1_DMEM_AWIDTH-1 -: TAG_BITS];

    assign req_cacheable = (req_addr_q & CACHEABLE_ADDR_MASK)
                         == (CACHEABLE_ADDR_PATTERN & CACHEABLE_ADDR_MASK);
    assign req_hit       = valid_q[req_line_index]
                         && (tag_mem[req_line_index] == req_tag);

    always_comb begin
        fill_addr = req_addr_q;
        fill_addr[LINE_OFFSET_BITS-1:0] = '0;
        fill_addr[BYTE_OFFSET_BITS +: WORD_INDEX_BITS] = fill_word_q;
    end

    // Both cache-line fills and write-through updates share one physical RAM
    // write port. Byte enables let stores update only the addressed byte lanes
    // without reading and merging the old RAM word.
    always_comb begin
        data_mem_write_en      = 1'b0;
        data_mem_write_byte_en = 4'b0000;
        data_mem_write_addr    = '0;
        data_mem_write_data    = '0;

        if ((state_q == DC_FILL_WAIT)
            && (mem_resp_i == SCR1_MEM_RESP_RDY_OK)) begin
            data_mem_write_en      = 1'b1;
            data_mem_write_byte_en = 4'b1111;
            data_mem_write_addr    = fill_data_index;
            data_mem_write_data    = mem_rdata_i;
        end else if ((state_q == DC_BYPASS_WAIT)
            && (mem_resp_i == SCR1_MEM_RESP_RDY_OK)
            && (req_cmd_q != SCR1_MEM_CMD_RD)
            && req_cacheable && req_hit) begin
            data_mem_write_en   = 1'b1;
            data_mem_write_addr = req_data_index;
            data_mem_write_data = req_wdata_q << (8 * req_addr_q[1:0]);

            unique case (req_width_q)
                SCR1_MEM_WIDTH_BYTE: begin
                    data_mem_write_byte_en = 4'b0001 << req_addr_q[1:0];
                end

                SCR1_MEM_WIDTH_HWORD: begin
                    data_mem_write_byte_en = 4'b0011 << req_addr_q[1:0];
                end

                default: begin
                    data_mem_write_byte_en = 4'b1111;
                end
            endcase
        end
    end

    always_comb begin
        state_d = state_q;

        unique case (state_q)
            DC_IDLE: begin
                if (flush_i) begin
                    state_d = DC_FLUSH;
                end else if (cpu_req_i) begin
                    state_d = DC_LOOKUP;
                end
            end

            DC_LOOKUP: begin
                if (req_cmd_q == SCR1_MEM_CMD_WR) begin
                    state_d = DC_BYPASS_REQ;
                end else if (!req_cacheable) begin
                    state_d = DC_BYPASS_REQ;
                end else if (req_hit) begin
                    state_d = DC_RESP_OK;
                end else begin
                    state_d = DC_FILL_REQ;
                end
            end

            DC_FILL_REQ: begin
                if (mem_req_ack_i) begin
                    state_d = DC_FILL_WAIT;
                end
            end

            DC_FILL_WAIT: begin
                if (mem_resp_i == SCR1_MEM_RESP_RDY_ER) begin
                    state_d = DC_RESP_ERR;
                end else if (mem_resp_i == SCR1_MEM_RESP_RDY_OK) begin
                    if (fill_word_q == WORD_INDEX_BITS'(LINE_WORDS - 1)) begin
                        state_d = DC_RESP_OK;
                    end else begin
                        state_d = DC_FILL_REQ;
                    end
                end
            end

            DC_BYPASS_REQ: begin
                if (mem_req_ack_i) begin
                    state_d = DC_BYPASS_WAIT;
                end
            end

            DC_BYPASS_WAIT: begin
                if (mem_resp_i == SCR1_MEM_RESP_RDY_ER) begin
                    state_d = DC_RESP_ERR;
                end else if (mem_resp_i == SCR1_MEM_RESP_RDY_OK) begin
                    state_d = DC_RESP_OK;
                end
            end

            DC_RESP_OK,
            DC_RESP_ERR: begin
                state_d = DC_IDLE;
            end

            DC_FLUSH: begin
                state_d = DC_FLUSH_ACK;
            end

            DC_FLUSH_ACK: begin
                if (!flush_i) begin
                    state_d = DC_IDLE;
                end
            end

            default: begin
                state_d = DC_IDLE;
            end
        endcase
    end

    always_comb begin
        cpu_req_ack_o = 1'b0;
        cpu_rdata_o   = response_data_q;
        cpu_resp_o    = SCR1_MEM_RESP_NOTRDY;
        flush_ack_o   = 1'b0;

        mem_req_o     = 1'b0;
        mem_cmd_o     = SCR1_MEM_CMD_RD;
        mem_width_o   = SCR1_MEM_WIDTH_WORD;
        mem_addr_o    = '0;
        mem_wdata_o   = '0;

        if ((state_q == DC_IDLE) && !flush_i) begin
            cpu_req_ack_o = 1'b1;
        end

        if (state_q == DC_FILL_REQ) begin
            mem_req_o   = 1'b1;
            mem_cmd_o   = SCR1_MEM_CMD_RD;
            mem_width_o = SCR1_MEM_WIDTH_WORD;
            mem_addr_o  = fill_addr;
        end else if (state_q == DC_BYPASS_REQ) begin
            mem_req_o   = 1'b1;
            mem_cmd_o   = req_cmd_q;
            mem_width_o = req_width_q;
            mem_addr_o  = req_addr_q;
            mem_wdata_o = req_wdata_q;
        end

        if (state_q == DC_RESP_OK) begin
            cpu_resp_o = SCR1_MEM_RESP_RDY_OK;
        end else if (state_q == DC_RESP_ERR) begin
            cpu_resp_o = SCR1_MEM_RESP_RDY_ER;
        end

        if (state_q == DC_FLUSH_ACK) begin
            flush_ack_o = 1'b1;
        end
    end

    // Cache memories have no reset. Their contents are ignored whenever the
    // corresponding valid bit is clear. Keeping all memory accesses in this
    // clock-only process matches the synchronous RAM inference template.
    always_ff @(posedge clk) begin
        if ((state_q == DC_IDLE) && cpu_req_i && cpu_req_ack_o) begin
            data_mem_rdata_q <= data_mem[cpu_data_index];
        end

        if (data_mem_write_en) begin
            for (int byte_num = 0; byte_num < 4; byte_num++) begin
                if (data_mem_write_byte_en[byte_num]) begin
                    data_mem[data_mem_write_addr][byte_num*8 +: 8]
                        <= data_mem_write_data[byte_num*8 +: 8];
                end
            end
        end

        if ((state_q == DC_FILL_WAIT)
            && (mem_resp_i == SCR1_MEM_RESP_RDY_OK)
            && (fill_word_q == WORD_INDEX_BITS'(LINE_WORDS - 1))) begin
            tag_mem[req_line_index] <= req_tag;
        end
    end

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            state_q         <= DC_IDLE;
            valid_q         <= '0;
            req_addr_q      <= '0;
            req_wdata_q     <= '0;
            req_cmd_q       <= SCR1_MEM_CMD_RD;
            req_width_q     <= SCR1_MEM_WIDTH_WORD;
            fill_word_q     <= '0;
            response_data_q <= '0;
        end else begin
            state_q <= state_d;

            if ((state_q == DC_IDLE) && cpu_req_i && cpu_req_ack_o) begin
                req_addr_q  <= cpu_addr_i;
                req_wdata_q <= cpu_wdata_i;
                req_cmd_q   <= cpu_cmd_i;
                req_width_q <= cpu_width_i;
            end

            if ((state_q == DC_LOOKUP) && (req_cmd_q == SCR1_MEM_CMD_RD)
                && req_cacheable && !req_hit) begin
                fill_word_q             <= '0;
                valid_q[req_line_index] <= 1'b0;
            end

            if ((state_q == DC_LOOKUP) && (req_cmd_q == SCR1_MEM_CMD_RD)
                && req_cacheable && req_hit) begin
                response_data_q <= select_load_data(
                    data_mem_rdata_q, req_addr_q[1:0]
                );
            end

            if ((state_q == DC_FILL_WAIT)
                && (mem_resp_i == SCR1_MEM_RESP_RDY_OK)) begin
                if (fill_word_q == req_word_index) begin
                    response_data_q <= select_load_data(mem_rdata_i, req_addr_q[1:0]);
                end

                if (fill_word_q == WORD_INDEX_BITS'(LINE_WORDS - 1)) begin
                    valid_q[req_line_index] <= 1'b1;
                end else begin
                    fill_word_q <= fill_word_q + 1'b1;
                end
            end

            if ((state_q == DC_BYPASS_WAIT)
                && (mem_resp_i == SCR1_MEM_RESP_RDY_OK)) begin
                if (req_cmd_q == SCR1_MEM_CMD_RD) begin
                    // The SCR1 lower-memory bridge already right-aligns
                    // byte/halfword reads, so bypass data needs no shift.
                    response_data_q <= mem_rdata_i;
                end
            end

            if (state_q == DC_FLUSH) begin
                // This D$ is write-through, so no dirty data exists.  Flush
                // therefore consists only of invalidating all cached lines.
                for (line = 0; line < NUM_LINES; line = line + 1) begin
                    valid_q[line] <= 1'b0;
                end
            end
        end
    end

endmodule
