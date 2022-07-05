`include "core_types.sv"
`include "core_config.sv"

module wb_ctrl
    import core_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,

    input logic stall,
    input logic flush,

    input  wb_ctrl_struct wb_o,
    output wb_ctrl_struct ctrl_i
);

    always_ff @(posedge clk) begin
        if (rst) 
            ctrl_i <= 0;
        else if(stall | flush)
            ctrl_i <= 0;
        else 
            ctrl_i <= wb_o;
    end

endmodule
