`include "core_types.sv"
`include "core_config.sv"

module mem2_wb
    import core_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,

    input logic stall,
    input logic flush,

    input  mem2_wb_struct mem2_o,
    output mem2_wb_struct wb_i
);

    always_ff @(posedge clk) begin
        if (rst) 
            wb_i <= 0;
        else if(stall | flush)
            wb_i <= 0;
        else 
            wb_i <= mem2_o;
    end

endmodule
