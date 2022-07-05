`include "core_types.sv"
`include "core_config.sv"

module mem1_mem2
    import core_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,

    input logic stall,
    input logic flush,

    input  mem1_mem2_struct mem1_o,
    output mem1_mem2_struct mem2_i
);

    always_ff @(posedge clk) begin
        if (rst) 
            mem2_i <= 0;
        else if(stall | flush)
            mem2_i <= 0;
        else 
            mem2_i <= mem1_o;
    end

endmodule
