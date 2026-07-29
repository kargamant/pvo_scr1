/// Copyright by Syntacore LLC © 2016-2021. See LICENSE for details
/// @file       <scr1_cg.sv>
/// @brief      SCR1 clock gate primitive
///

`include "scr1_arch_description.svh"

`ifdef SCR1_CLKCTRL_EN
module scr1_cg (
    input   logic   clk,
    input   logic   clk_en,
    input   logic   test_mode,
    output  logic   clk_out
);

`ifdef SCR1_TRGT_FPGA_XILINX
    // Xilinx target: use BUFGCE primitive (clock buffer with clock enable)
    // This avoids latch inference warnings during Vivado synthesis
    BUFGCE i_bufgce (
        .I  (clk),
        .CE (clk_en | test_mode),
        .O  (clk_out)
    );
`else
    // Simulation / ASIC / other targets: latch-based model
    // For synthesis on non-Xilinx FPGAs, replace with platform-specific clock gate cell.
    logic latch_en;

    always_latch begin
        if (~clk) begin
            latch_en <= test_mode | clk_en;
        end
    end

    assign clk_out = latch_en & clk;
`endif

endmodule : scr1_cg

`endif // SCR1_CLKCTRL_EN
