// Branch Target Buffer
`include "core_config.sv"
`include "BPU/include/bpu_types.sv"
`include "utils/bram.sv"
`include "utils/one_hot_to_index.sv"
`include "utils/lfsr.sv"
`include "utils/normal_priority_encoder.sv"


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
    input logic update_dirty_i,
    input ftb_entry_t update_entry_i

);

    // Parameters
    localparam NSET_WIDTH = $clog2(FTB_NSET);
    localparam NWAY_WIDTH = $clog2(FTB_NWAY);
    localparam NSET = FTB_NSET;
    localparam NWAY = FTB_NWAY;

    // Signals definition
    ftb_entry_t [NWAY-1:0] way_query_entry;
    logic [NWAY-1:0] way_hit;
    logic [NWAY_WIDTH-1:0] way_hit_index;
    // Query
    logic [NSET_WIDTH-1:0] query_index;
    logic [ADDR_WIDTH-NSET_WIDTH-3:0] query_tag_buffer;
    // Update
    logic [NSET_WIDTH-1:0] update_index;
    ftb_entry_t update_entry;
    logic [NWAY-1:0] update_we;
    logic [15:0] random_r;


    /////////////////////////////////////////////////////////////////////////////////////////
    // Query logic 
    /////////////////////////////////////////////////////////////////////////////////////////
    assign query_index = query_pc_i[2+:NSET_WIDTH];
    always_ff @(posedge clk) begin
        query_tag_buffer <= query_pc_i[ADDR_WIDTH-1:NSET_WIDTH+2];
    end
    always_comb begin
        for (integer way_idx = 0; way_idx < NWAY; way_idx++) begin
            way_hit[way_idx] = (way_query_entry[way_idx].tag == query_tag_buffer) && way_query_entry[way_idx].valid;
        end
    end



    // Query output
    assign query_entry_o = way_query_entry[way_hit_index];
    assign hit = |way_hit;

    /////////////////////////////////////////////////////////////////////////////////////////
    // Update logic 
    /////////////////////////////////////////////////////////////////////////////////////////
    assign update_index = update_pc_i[NSET_WIDTH+1:2];
    always_comb begin
        if (update_dirty_i) begin  // Just override all entry in this group to ensure old entry is cleared
            update_entry = update_entry_i;
            update_we = {NWAY{1'b1}};
        end else begin  // Update a new entry in
            update_entry = update_entry_i;
            update_we = 0;
            for (integer way_idx = 0; way_idx < NWAY; way_idx++) begin
                if (way_idx[NWAY_WIDTH-1:0] == random_r[NWAY_WIDTH-1:0]) update_we[way_idx] = 1;
            end
        end
    end



    // Module instantiation
    // Use priority_encoder because multiple hit can occur 
    normal_priority_encoder #(
        .WIDTH(NWAY)
    ) u_normal_priority_encoder (
        .priority_vector(way_hit),
        .encoded_result (way_hit_index)
    );


    lfsr #(
        .WIDTH(16)
    ) u_lfsr (
        .clk  (clk),
        .rst  (rst),
        .en   (1'b1),
        .value(random_r)
    );

    generate
        for (genvar way_idx = 0; way_idx < NWAY; way_idx++) begin
`ifdef BRAM_IP
            bram_ftb u_bram (
                .clka (clk),
                .clkb (clk),
                .ena  (1'b1),
                .enb  (1'b1),
                .wea  (0),
                .web  (update_we[way_idx]),
                .dina (0),
                .addra(query_index),
                .douta(way_query_entry[way_idx]),
                .dinb (update_entry),
                .addrb(update_index),
                .doutb()
            );
`else
            bram #(
                .DATA_WIDTH     ($bits(ftb_entry_t)),
                .DATA_DEPTH_EXP2(NSET_WIDTH)
            ) u_bram (
                .clk  (clk),
                .ena  (1'b1),
                .enb  (1'b1),
                .wea  (0),
                .web  (update_we[way_idx]),
                .dina (0),
                .addra(query_index),
                .douta(way_query_entry[way_idx]),
                .dinb (update_entry),
                .addrb(update_index),
                .doutb()
            );
`endif
        end
    endgenerate

    // DEBUG
`ifdef SIMULATION
    integer multi_hit_cnt;
    integer hit_num;
    always_comb begin
        hit_num = 0;
        for (integer i = 0; i < NWAY; i++) hit_num = hit_num + way_hit[i];
    end

    always_ff @(posedge clk) begin
        multi_hit_cnt <= multi_hit_cnt + (hit_num > 1);
    end
`endif

endmodule
