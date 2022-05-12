`include "defines.sv"
module ctrl (
    input logic rst,

    input logic [1:0] ex_branch_flag_i,
    input logic stallreq_from_dispatch,
    input logic data_stallreq_from_axi,
    input logic inst_stallreq_from_axi,
    input logic excp_i,
    input logic [15:0] excp_num_i,


    output logic [4:0] stall,
    output logic [1:0] ex_mem_flush_o
);

    assign ex_mem_flush_o[1] = ex_branch_flag_i[0];
    assign ex_mem_flush_o[0] = 0;

    always_comb begin
        if(rst)
            stall = 5'b00000;
        else if(data_stallreq_from_axi)
            stall = 5'b11110;
        else if(stallreq_from_dispatch)
            stall = 5'b11100;
        else if(inst_stallreq_from_axi)
            stall = 5'b11000;
        else 
            stall = 5'b00000;
    end

endmodule  //ctrl
