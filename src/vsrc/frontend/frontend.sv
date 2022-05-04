`include "instr_info.sv"
module frontend #(
    parameter FETCH_WIDTH = 2
) (
    input logic clk,
    input logic rst,

    // <-> Backend
    input branch_update_info_t branch_update_info_i,
    input logic [`InstAddrBus] backend_next_pc_i,
    input logic backend_flush_i,

    // <-> Instruction buffer
    input logic instr_buffer_stallreq_i,
    output instr_buffer_info_t instr_buffer_o[FETCH_WIDTH]

);

endmodule
