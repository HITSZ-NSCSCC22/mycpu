`include "core_types.sv"
`include "core_config.sv"

module ex_mem
    import core_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,

    input logic stall,
    input logic flush,

    input  ex_mem_struct ex_o,
    output ex_mem_struct mem_i
);
    always_ff @(posedge clk) begin
        if(rst)
            mem_i <= 0;
        else if(stall | flush)
            mem_i <= 0;
        else 
            mem_i <= ex_o;
    end

endmodule
