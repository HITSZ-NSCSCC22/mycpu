`include "defines.sv"
module ctrl (
    input logic [1:0] ex_branch_flag_i,

    output logic [1:0] ex_mem_flush_o
);

    assign ex_mem_flush_o[1] = ex_branch_flag_i[0];
    assign ex_mem_flush_o[0] = 0;


endmodule  //ctrl
