`timescale 1ns/1ps

`include "scr1_arch_description.svh"
`include "scr1_memif.svh"

module scr1_cache_blocks_tb;

    localparam logic [31:0] DDR_MASK    = 32'hf8000000;
    localparam logic [31:0] DDR_PATTERN = 32'h00000000;

    logic clk;
    logic rst_n;

    logic i_invalidate;
    logic i_invalidate_ack;
    logic i_cpu_req_ack;
    logic i_cpu_req;
    type_scr1_mem_cmd_e i_cpu_cmd;
    logic [31:0] i_cpu_addr;
    logic [31:0] i_cpu_rdata;
    type_scr1_mem_resp_e i_cpu_resp;
    logic i_mem_req_ack;
    logic i_mem_req;
    type_scr1_mem_cmd_e i_mem_cmd;
    logic [31:0] i_mem_addr;
    logic [31:0] i_mem_rdata;
    type_scr1_mem_resp_e i_mem_resp;

    logic d_flush;
    logic d_flush_ack;
    logic d_cpu_req_ack;
    logic d_cpu_req;
    type_scr1_mem_cmd_e d_cpu_cmd;
    type_scr1_mem_width_e d_cpu_width;
    logic [31:0] d_cpu_addr;
    logic [31:0] d_cpu_wdata;
    logic [31:0] d_cpu_rdata;
    type_scr1_mem_resp_e d_cpu_resp;
    logic d_mem_req_ack;
    logic d_mem_req;
    type_scr1_mem_cmd_e d_mem_cmd;
    type_scr1_mem_width_e d_mem_width;
    logic [31:0] d_mem_addr;
    logic [31:0] d_mem_wdata;
    logic [31:0] d_mem_rdata;
    type_scr1_mem_resp_e d_mem_resp;

    logic        i_pending_q;
    logic [31:0] i_pending_addr_q;
    logic        d_pending_q;
    logic [31:0] d_pending_addr_q;
    logic [31:0] d_pending_wdata_q;
    type_scr1_mem_cmd_e d_pending_cmd_q;
    type_scr1_mem_width_e d_pending_width_q;

    logic [31:0] d_memory [0:1023];
    integer i_mem_transactions;
    integer d_mem_transactions;
    integer errors;
    integer k;

    always #5 clk = ~clk;

    assign i_mem_req_ack = 1'b1;
    assign d_mem_req_ack = 1'b1;

    scr1_icache #(
        .CACHEABLE_ADDR_MASK    (DDR_MASK),
        .CACHEABLE_ADDR_PATTERN (DDR_PATTERN),
        .NUM_LINES              (8),
        .LINE_WORDS             (4)
    ) i_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .invalidate_i     (i_invalidate),
        .invalidate_ack_o (i_invalidate_ack),
        .cpu_req_ack_o    (i_cpu_req_ack),
        .cpu_req_i        (i_cpu_req),
        .cpu_cmd_i        (i_cpu_cmd),
        .cpu_addr_i       (i_cpu_addr),
        .cpu_rdata_o      (i_cpu_rdata),
        .cpu_resp_o       (i_cpu_resp),
        .mem_req_ack_i    (i_mem_req_ack),
        .mem_req_o        (i_mem_req),
        .mem_cmd_o        (i_mem_cmd),
        .mem_addr_o       (i_mem_addr),
        .mem_rdata_i      (i_mem_rdata),
        .mem_resp_i       (i_mem_resp)
    );

    scr1_dcache #(
        .CACHEABLE_ADDR_MASK    (DDR_MASK),
        .CACHEABLE_ADDR_PATTERN (DDR_PATTERN),
        .NUM_LINES              (8),
        .LINE_WORDS             (4)
    ) d_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .flush_i       (d_flush),
        .flush_ack_o   (d_flush_ack),
        .cpu_req_ack_o (d_cpu_req_ack),
        .cpu_req_i     (d_cpu_req),
        .cpu_cmd_i     (d_cpu_cmd),
        .cpu_width_i   (d_cpu_width),
        .cpu_addr_i    (d_cpu_addr),
        .cpu_wdata_i   (d_cpu_wdata),
        .cpu_rdata_o   (d_cpu_rdata),
        .cpu_resp_o    (d_cpu_resp),
        .mem_req_ack_i (d_mem_req_ack),
        .mem_req_o     (d_mem_req),
        .mem_cmd_o     (d_mem_cmd),
        .mem_width_o   (d_mem_width),
        .mem_addr_o    (d_mem_addr),
        .mem_wdata_o   (d_mem_wdata),
        .mem_rdata_i   (d_mem_rdata),
        .mem_resp_i    (d_mem_resp)
    );

    function automatic logic [31:0] i_memory_value(input logic [31:0] addr);
        i_memory_value = {addr[15:2], 2'b00} ^ 32'ha5a50000;
    endfunction

    function automatic logic [31:0] merge_write(
        input logic [31:0] old_word,
        input logic [31:0] write_data,
        input type_scr1_mem_width_e width,
        input logic [1:0] offset
    );
        logic [31:0] mask;
        begin
            case (width)
                SCR1_MEM_WIDTH_BYTE:  mask = 32'h000000ff << (8 * offset);
                SCR1_MEM_WIDTH_HWORD: mask = 32'h0000ffff << (8 * offset);
                default:              mask = 32'hffffffff;
            endcase
            merge_write = (old_word & ~mask)
                        | ((write_data << (8 * offset)) & mask);
        end
    endfunction

    function automatic logic [31:0] read_d_memory(
        input logic [31:0] addr,
        input type_scr1_mem_width_e width
    );
        logic [31:0] raw;
        begin
            if (addr[31:24] == 8'hff) begin
                raw = 32'hcafebabe;
            end else begin
                raw = d_memory[addr[11:2]];
            end
            case (width)
                SCR1_MEM_WIDTH_BYTE,
                SCR1_MEM_WIDTH_HWORD: read_d_memory = raw >> (8 * addr[1:0]);
                default:              read_d_memory = raw;
            endcase
        end
    endfunction

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            i_pending_q       <= 1'b0;
            i_pending_addr_q  <= '0;
            i_mem_rdata       <= '0;
            i_mem_resp        <= SCR1_MEM_RESP_NOTRDY;
            i_mem_transactions <= 0;
        end else begin
            i_mem_resp <= SCR1_MEM_RESP_NOTRDY;

            if (i_pending_q) begin
                i_mem_rdata <= i_memory_value(i_pending_addr_q);
                i_mem_resp  <= SCR1_MEM_RESP_RDY_OK;
                i_pending_q <= 1'b0;
            end

            if (i_mem_req && i_mem_req_ack) begin
                i_pending_q        <= 1'b1;
                i_pending_addr_q   <= i_mem_addr;
                i_mem_transactions <= i_mem_transactions + 1;
            end
        end
    end

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            d_pending_q        <= 1'b0;
            d_pending_addr_q   <= '0;
            d_pending_wdata_q  <= '0;
            d_pending_cmd_q    <= SCR1_MEM_CMD_RD;
            d_pending_width_q  <= SCR1_MEM_WIDTH_WORD;
            d_mem_rdata        <= '0;
            d_mem_resp         <= SCR1_MEM_RESP_NOTRDY;
            d_mem_transactions <= 0;
        end else begin
            d_mem_resp <= SCR1_MEM_RESP_NOTRDY;

            if (d_pending_q) begin
                if (d_pending_cmd_q == SCR1_MEM_CMD_RD) begin
                    d_mem_rdata <= read_d_memory(d_pending_addr_q, d_pending_width_q);
                end else if (d_pending_addr_q[31:24] != 8'hff) begin
                    d_memory[d_pending_addr_q[11:2]] <= merge_write(
                        d_memory[d_pending_addr_q[11:2]],
                        d_pending_wdata_q,
                        d_pending_width_q,
                        d_pending_addr_q[1:0]
                    );
                end
                d_mem_resp  <= SCR1_MEM_RESP_RDY_OK;
                d_pending_q <= 1'b0;
            end

            if (d_mem_req && d_mem_req_ack) begin
                d_pending_q        <= 1'b1;
                d_pending_addr_q   <= d_mem_addr;
                d_pending_wdata_q  <= d_mem_wdata;
                d_pending_cmd_q    <= d_mem_cmd;
                d_pending_width_q  <= d_mem_width;
                d_mem_transactions <= d_mem_transactions + 1;
            end
        end
    end

    task automatic issue_i_read(
        input logic [31:0] addr,
        output logic [31:0] data,
        output type_scr1_mem_resp_e resp
    );
        integer timeout;
        begin
            @(negedge clk);
            i_cpu_addr = addr;
            i_cpu_cmd  = SCR1_MEM_CMD_RD;
            i_cpu_req  = 1'b1;
            timeout = 0;
            while (!i_cpu_req_ack && timeout < 100) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            @(negedge clk);
            i_cpu_req = 1'b0;
            timeout = 0;
            while ((i_cpu_resp == SCR1_MEM_RESP_NOTRDY) && timeout < 200) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            data = i_cpu_rdata;
            resp = i_cpu_resp;
        end
    endtask

    task automatic issue_d_request(
        input type_scr1_mem_cmd_e cmd,
        input type_scr1_mem_width_e width,
        input logic [31:0] addr,
        input logic [31:0] wdata,
        output logic [31:0] rdata,
        output type_scr1_mem_resp_e resp
    );
        integer timeout;
        begin
            @(negedge clk);
            d_cpu_cmd   = cmd;
            d_cpu_width = width;
            d_cpu_addr  = addr;
            d_cpu_wdata = wdata;
            d_cpu_req   = 1'b1;
            timeout = 0;
            while (!d_cpu_req_ack && timeout < 100) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            @(negedge clk);
            d_cpu_req = 1'b0;
            timeout = 0;
            while ((d_cpu_resp == SCR1_MEM_RESP_NOTRDY) && timeout < 200) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            rdata = d_cpu_rdata;
            resp  = d_cpu_resp;
        end
    endtask

    task automatic check(
        input logic condition,
        input [8*80-1:0] message
    );
        begin
            if (!condition) begin
                $display("ERROR: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    logic [31:0] observed_data;
    type_scr1_mem_resp_e observed_resp;
    integer before_count;

    initial begin
        clk          = 1'b0;
        rst_n        = 1'b0;
        i_invalidate = 1'b0;
        i_cpu_req    = 1'b0;
        i_cpu_cmd    = SCR1_MEM_CMD_RD;
        i_cpu_addr   = '0;
        d_flush      = 1'b0;
        d_cpu_req    = 1'b0;
        d_cpu_cmd    = SCR1_MEM_CMD_RD;
        d_cpu_width  = SCR1_MEM_WIDTH_WORD;
        d_cpu_addr   = '0;
        d_cpu_wdata  = '0;
        errors       = 0;

        for (k = 0; k < 1024; k = k + 1) begin
            d_memory[k] = 32'h10000000 + k;
        end

        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        // I$: a miss performs four reads, and the second access is a hit.
        before_count = i_mem_transactions;
        issue_i_read(32'h00000124, observed_data, observed_resp);
        check(observed_resp == SCR1_MEM_RESP_RDY_OK, "I$ miss must complete successfully");
        check(observed_data == i_memory_value(32'h00000124), "I$ miss returned wrong instruction");
        check(i_mem_transactions == before_count + 4, "I$ line fill must issue four memory reads");

        before_count = i_mem_transactions;
        issue_i_read(32'h00000128, observed_data, observed_resp);
        check(observed_data == i_memory_value(32'h00000128), "I$ hit returned wrong instruction");
        check(i_mem_transactions == before_count, "I$ hit must not access lower memory");

        // I$ invalidate forces the next access to refill.
        @(negedge clk);
        i_invalidate = 1'b1;
        wait (i_invalidate_ack);
        @(negedge clk);
        i_invalidate = 1'b0;
        wait (!i_invalidate_ack);
        before_count = i_mem_transactions;
        issue_i_read(32'h00000128, observed_data, observed_resp);
        check(i_mem_transactions == before_count + 4, "I$ invalidate must remove the cached line");

        // D$: read miss followed by read hit.
        before_count = d_mem_transactions;
        issue_d_request(SCR1_MEM_CMD_RD, SCR1_MEM_WIDTH_WORD,
                        32'h00000204, '0, observed_data, observed_resp);
        check(observed_data == d_memory[32'h204 >> 2], "D$ miss returned wrong word");
        check(d_mem_transactions == before_count + 4, "D$ read miss must fill four words");

        before_count = d_mem_transactions;
        issue_d_request(SCR1_MEM_CMD_RD, SCR1_MEM_WIDTH_WORD,
                        32'h00000208, '0, observed_data, observed_resp);
        check(observed_data == d_memory[32'h208 >> 2], "D$ hit returned wrong word");
        check(d_mem_transactions == before_count, "D$ hit must not access lower memory");

        // Write-through byte store hit updates memory and cached copy.
        before_count = d_mem_transactions;
        issue_d_request(SCR1_MEM_CMD_WR, SCR1_MEM_WIDTH_BYTE,
                        32'h00000209, 32'h000000aa, observed_data, observed_resp);
        check(observed_resp == SCR1_MEM_RESP_RDY_OK, "D$ store hit must complete successfully");
        check(d_mem_transactions == before_count + 1, "Write-through store must access lower memory");
        check(d_memory[32'h208 >> 2] == 32'h1000aa82, "Byte store produced wrong memory word");

        before_count = d_mem_transactions;
        issue_d_request(SCR1_MEM_CMD_RD, SCR1_MEM_WIDTH_WORD,
                        32'h00000208, '0, observed_data, observed_resp);
        check(observed_data == d_memory[32'h208 >> 2], "Cached word was not updated after store hit");
        check(d_mem_transactions == before_count, "Read after store hit should remain a cache hit");

        // Store miss does not allocate; following read must perform a fill.
        issue_d_request(SCR1_MEM_CMD_WR, SCR1_MEM_WIDTH_WORD,
                        32'h00000300, 32'hdeadbeef, observed_data, observed_resp);
        before_count = d_mem_transactions;
        issue_d_request(SCR1_MEM_CMD_RD, SCR1_MEM_WIDTH_WORD,
                        32'h00000300, '0, observed_data, observed_resp);
        check(observed_data == 32'hdeadbeef, "Read after store miss returned wrong data");
        check(d_mem_transactions == before_count + 4, "No-write-allocate store must leave a read miss");

        // MMIO is bypassed every time.
        before_count = d_mem_transactions;
        issue_d_request(SCR1_MEM_CMD_RD, SCR1_MEM_WIDTH_WORD,
                        32'hff010000, '0, observed_data, observed_resp);
        check(observed_data == 32'hcafebabe, "MMIO bypass returned wrong data");
        issue_d_request(SCR1_MEM_CMD_RD, SCR1_MEM_WIDTH_WORD,
                        32'hff010000, '0, observed_data, observed_resp);
        check(d_mem_transactions == before_count + 2, "MMIO reads must never be cached");

        // D$ flush invalidates a cached line.
        @(negedge clk);
        d_flush = 1'b1;
        wait (d_flush_ack);
        @(negedge clk);
        d_flush = 1'b0;
        wait (!d_flush_ack);
        before_count = d_mem_transactions;
        issue_d_request(SCR1_MEM_CMD_RD, SCR1_MEM_WIDTH_WORD,
                        32'h00000208, '0, observed_data, observed_resp);
        check(d_mem_transactions == before_count + 4, "D$ flush must invalidate cached lines");

        if (errors == 0) begin
            $display("PASS: all cache tests completed successfully");
        end else begin
            $display("FAIL: %0d cache tests failed", errors);
        end
        $finish;
    end

endmodule
