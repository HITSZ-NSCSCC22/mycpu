`include "core_config.sv"


module ras
    import core_config::*;
(
    input logic clk,
    input logic rst,

    input logic push_i,
    input logic [ADDR_WIDTH-1:0] call_addr_i,
    input logic pop_i,

    output logic [ADDR_WIDTH-1:0] top_addr_o
);

    // Parameters
    localparam PTR_WIDTH = $clog2(RAS_ENTRY_NUM);
    // Data structure
    logic [ADDR_WIDTH-1:0] lutram[RAS_ENTRY_NUM];
    initial lutram = '{default: 0};


    // Signal defines
    logic [PTR_WIDTH-1:0] new_index;
    logic [PTR_WIDTH-1:0] read_index;


    // Index
    assign new_index = read_index + PTR_WIDTH'(push_i) - PTR_WIDTH'(pop_i);
    always_ff @(posedge clk) begin
        read_index <= new_index;
    end

    // Data
    always_ff @(posedge clk) begin
        if (push_i) lutram[new_index] <= call_addr_i;
    end


    // Output
    assign top_addr_o = lutram[read_index];




endmodule
