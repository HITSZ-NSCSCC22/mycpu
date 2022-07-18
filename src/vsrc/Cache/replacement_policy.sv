`timescale 1ns / 1ps
`include "Cache/dcache_config.sv"
`include "Cache/iob_cache.vh"
`include "Cache/iob_regfile_sp.sv"

module replacement_policy
    import dcache_config::*;
(
    input                   clk,
    input                   reset,
    input                   write_en,
    input  [    N_WAYS-1:0] way_hit,
    input  [LINE_OFF_W-1:0] line_addr,
    output [    N_WAYS-1:0] way_select,
    output [    NWAY_W-1:0] way_select_bin
);


    genvar i, j, k;

    logic [N_WAYS -1:1] tree_in, tree_out;
    logic [NWAY_W:0] node_id[NWAY_W:1];
    assign node_id[1] = tree_out[1] ? 3 : 2;  // next node id @ level2 to traverse
    for (i = 2; i <= NWAY_W; i = i + 1) begin : traverse_tree_level
        // next node id @ level3, level4, ..., to traverse
        assign node_id[i] = tree_out[node_id[i-1]] ? ((node_id[i-1]<<1)+1) : (node_id[i-1]<<1);
    end

    for (i = 1; i <= NWAY_W; i = i + 1) begin : tree_level
        for (j = 0; j < (1 << (i - 1)); j = j + 1) begin : tree_level_node
            assign tree_in[(1<<(i-1))+j] = ~(|way_hit) ? tree_out[(1<<(i-1))+j] :
                                                (|way_hit[((((1<<(i-1))+j)*2)*(1<<(NWAY_W-i)))-N_WAYS +: (N_WAYS>>i)]) ||
                                                (tree_out[(1<<(i-1))+j] && (~(|way_hit[((((1<<(i-1))+j)*2+1)*(1<<(NWAY_W-i)))-N_WAYS +: (N_WAYS>>i)])));
        end
    end

    assign way_select_bin = node_id[NWAY_W] - N_WAYS;
    assign way_select = (1 << way_select_bin);

    //Most Recently Used (MRU) memory
    iob_regfile_sp #(
        .ADDR_W(LINE_OFF_W),
        .DATA_W(N_WAYS - 1)
    ) mru_memory  //simply uses the same format as valid memory
    (
        .clk(clk),
        .rst(reset),

        .we    (write_en),
        .addr  (line_addr),
        .w_data(tree_in),
        .r_data(tree_out)
    );
endmodule
