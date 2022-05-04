`include "instr_info.sv"
module frontend #(
    parameter FETCH_WIDTH = 2,
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32
) (
    input logic clk,
    input logic rst,

    // <-> ICache
    output logic [ADDR_WIDTH-1:0] icache_read_addr_o[FETCH_WIDTH],
    input logic icache_stallreq_i,  // ICache cannot accept more addr input
    input logic icache_read_valid_i[FETCH_WIDTH],
    input logic [ADDR_WIDTH-1:0] icache_read_addr_i[FETCH_WIDTH],
    input logic [DATA_WIDTH-1:0] icache_read_data_i[FETCH_WIDTH],


    // <-> Backend
    input branch_update_info_t branch_update_info_i,
    input logic [ADDR_WIDTH-1:0] backend_next_pc_i,
    input logic backend_flush_i,

    // <-> Instruction buffer
    input logic instr_buffer_stallreq_i,
    output instr_buffer_info_t instr_buffer_o[FETCH_WIDTH]

);

endmodule
