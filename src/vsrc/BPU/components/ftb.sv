// Branch Target Buffer
`include "core_config.sv"
`include "BPU/include/bpu_types.sv"
`include "utils/bram.sv"


module ftb
    import core_config::*;
    import bpu_types::*;
(
    input logic clk,
    input logic rst,

    // Query
    input logic [ADDR_WIDTH-1:0] query_pc_i,
    output ftb_entry_t query_entry_o,
    output logic hit,

    // Update signals
    input logic [ADDR_WIDTH-1:0] update_pc_i,
    input logic update_valid_i,
    input ftb_entry_t update_entry_i

);

    // Query logic //////////////////////////////////////////////////////////////////////////
    logic [$clog2(FTB_DEPTH)-1:0] query_index;
    assign query_index = query_pc_i[$clog2(FTB_DEPTH)+1:2];

    ftb_entry_t query_entry;
    assign hit = (query_entry.tag == query_pc_i[ADDR_WIDTH-1:$clog2(
        FTB_DEPTH
    )+2]) && query_entry.valid;
    assign query_entry_o = query_entry;

    // Update logic //////////////////////////////////////////////////////////////////////////
    logic [$clog2(FTB_DEPTH)-1:0] update_index;
    assign update_index = update_pc_i[$clog2(FTB_DEPTH)+1:2];

`ifdef BRAM_IP
    bram_ftb u_bram (
        .clka (clk),
        .clkb (clk),
        .ena  (1'b1),
        .enb  (update_valid_i),
        .wea  (0),
        .web  (update_valid_i),
        .dina (0),
        .addra(query_index),
        .douta(query_entry),
        .dinb (update_entry_i),
        .addrb(update_index),
        .doutb()
    );
`else
    bram #(
        .DATA_WIDTH     ($bits(ftb_entry_t)),
        .DATA_DEPTH_EXP2($clog2(FTB_DEPTH))
    ) u_bram (
        .clk  (clk),
        .ena  (1'b1),
        .enb  (update_valid_i),
        .wea  (0),
        .web  (update_valid_i),
        .dina (0),
        .addra(query_index),
        .douta(query_entry),
        .dinb (update_entry_i),
        .addrb(update_index),
        .doutb()
    );
`endif


endmodule
