`include "scr1_arch_description.svh"
`include "scr1_memif.svh"

module scr1_cache_wrapper #(
    parameter logic [`SCR1_IMEM_AWIDTH-1:0] ICACHE_ADDR_MASK    = '0,
    parameter logic [`SCR1_IMEM_AWIDTH-1:0] ICACHE_ADDR_PATTERN = '0,
    parameter logic [`SCR1_DMEM_AWIDTH-1:0] DCACHE_ADDR_MASK    = '0,
    parameter logic [`SCR1_DMEM_AWIDTH-1:0] DCACHE_ADDR_PATTERN = '0
) (
    input  logic                              clk,
    input  logic                              rst_n,

    // Инвалидация кэша инструкций(valid=0) и перепись кэша данных обратно в память(если dirty=1)
    input  logic                              icache_invalidate_i,
    output logic                              icache_invalidate_ack_o,
    input  logic                              dcache_flush_i,
    output logic                              dcache_flush_ack_o,

    // imem интерфейс с ядром
    output logic                              imem2core_req_ack_o,
    input  logic                              core2imem_req_i,
    input  type_scr1_mem_cmd_e                core2imem_cmd_i,
    input  logic [`SCR1_IMEM_AWIDTH-1:0]       core2imem_addr_i,
    output logic [`SCR1_IMEM_DWIDTH-1:0]       imem2core_rdata_o,
    output type_scr1_mem_resp_e               imem2core_resp_o,

    // dmem интерфейс с ядром
    output logic                              dmem2core_req_ack_o,
    input  logic                              core2dmem_req_i,
    input  type_scr1_mem_cmd_e                core2dmem_cmd_i,
    input  type_scr1_mem_width_e              core2dmem_width_i,
    input  logic [`SCR1_DMEM_AWIDTH-1:0]       core2dmem_addr_i,
    input  logic [`SCR1_DMEM_DWIDTH-1:0]       core2dmem_wdata_i,
    output logic [`SCR1_DMEM_DWIDTH-1:0]       dmem2core_rdata_o,
    output type_scr1_mem_resp_e               dmem2core_resp_o,

    // интерфейс icache и imem
    input  logic                              mem2icache_req_ack_i,
    output logic                              icache2mem_req_o,
    output type_scr1_mem_cmd_e                icache2mem_cmd_o,
    output logic [`SCR1_IMEM_AWIDTH-1:0]       icache2mem_addr_o,
    input  logic [`SCR1_IMEM_DWIDTH-1:0]       mem2icache_rdata_i,
    input  type_scr1_mem_resp_e               mem2icache_resp_i,

    // Интерфейс dcache и dmem
    input  logic                              mem2dcache_req_ack_i,
    output logic                              dcache2mem_req_o,
    output type_scr1_mem_cmd_e                dcache2mem_cmd_o,
    output type_scr1_mem_width_e              dcache2mem_width_o,
    output logic [`SCR1_DMEM_AWIDTH-1:0]       dcache2mem_addr_o,
    output logic [`SCR1_DMEM_DWIDTH-1:0]       dcache2mem_wdata_o,
    input  logic [`SCR1_DMEM_DWIDTH-1:0]       mem2dcache_rdata_i,
    input  type_scr1_mem_resp_e               mem2dcache_resp_i
);

    scr1_icache #(
        .CACHEABLE_ADDR_MASK    (ICACHE_ADDR_MASK),
        .CACHEABLE_ADDR_PATTERN (ICACHE_ADDR_PATTERN)
    ) i_icache (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .invalidate_i           (icache_invalidate_i),
        .invalidate_ack_o       (icache_invalidate_ack_o),
        .cpu_req_ack_o          (imem2core_req_ack_o),
        .cpu_req_i              (core2imem_req_i),
        .cpu_cmd_i              (core2imem_cmd_i),
        .cpu_addr_i             (core2imem_addr_i),
        .cpu_rdata_o            (imem2core_rdata_o),
        .cpu_resp_o             (imem2core_resp_o),
        .mem_req_ack_i          (mem2icache_req_ack_i),
        .mem_req_o              (icache2mem_req_o),
        .mem_cmd_o              (icache2mem_cmd_o),
        .mem_addr_o             (icache2mem_addr_o),
        .mem_rdata_i            (mem2icache_rdata_i),
        .mem_resp_i             (mem2icache_resp_i)
    );

    scr1_dcache #(
        .CACHEABLE_ADDR_MASK    (DCACHE_ADDR_MASK),
        .CACHEABLE_ADDR_PATTERN (DCACHE_ADDR_PATTERN)
    ) i_dcache (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .flush_i                (dcache_flush_i),
        .flush_ack_o            (dcache_flush_ack_o),
        .cpu_req_ack_o          (dmem2core_req_ack_o),
        .cpu_req_i              (core2dmem_req_i),
        .cpu_cmd_i              (core2dmem_cmd_i),
        .cpu_width_i            (core2dmem_width_i),
        .cpu_addr_i             (core2dmem_addr_i),
        .cpu_wdata_i            (core2dmem_wdata_i),
        .cpu_rdata_o            (dmem2core_rdata_o),
        .cpu_resp_o             (dmem2core_resp_o),
        .mem_req_ack_i          (mem2dcache_req_ack_i),
        .mem_req_o              (dcache2mem_req_o),
        .mem_cmd_o              (dcache2mem_cmd_o),
        .mem_width_o            (dcache2mem_width_o),
        .mem_addr_o             (dcache2mem_addr_o),
        .mem_wdata_o            (dcache2mem_wdata_o),
        .mem_rdata_i            (mem2dcache_rdata_i),
        .mem_resp_i             (mem2dcache_resp_i)
    );

endmodule
