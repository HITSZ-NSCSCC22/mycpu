`include "defines.sv"
module ctrl (
    input logic rst,

    input logic [1:0] ex_branch_flag_i,
    input logic stallreg_from_dispatch,
    input logic excp_i,
    input logic [15:0] excp_num_i,


    output logic [3:0] stall,
    output logic [1:0] ex_mem_flush_o
);

    assign ex_mem_flush_o[1] = ex_branch_flag_i[0];
    assign ex_mem_flush_o[0] = 0;

    always_comb begin
        if(rst)
            stall = 4'b0000;
        else if(stallreg_from_dispatch)
            stall = 4'b1100;
        else 
            stall = 4'b0000;
    end

endmodule  //ctrl
