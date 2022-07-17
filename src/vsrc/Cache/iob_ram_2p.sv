`timescale 1ns / 1ps
`include "Cache/dcache_config.sv"
module iob_ram_2p
    import dcache_config::*;
(
    input clk,

    //write port
    input              w_en,
    input [ADDR_W-1:0] w_addr,
    input [DATA_W-1:0] w_data,

    //read port
    input                   r_en,
    input      [ADDR_W-1:0] r_addr,
    output reg [DATA_W-1:0] r_data
);

    //this allows ISE 14.7 to work; do not remove
    localparam mem_init_file_int = HEXFILE;

    // Declare the RAM
    reg [DATA_W-1:0] mem[(2**ADDR_W)-1:0];

    // Initialize the RAM
    initial
        if (mem_init_file_int != "none") $readmemh(mem_init_file_int, mem, 0, (2 ** ADDR_W) - 1);

    //read port
    always @(posedge clk) if (r_en) r_data <= mem[r_addr];

    //write port
    always @(posedge clk) if (w_en) mem[w_addr] <= w_data;

endmodule
