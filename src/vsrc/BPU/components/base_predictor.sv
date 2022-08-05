// Base Predictor is a pure PC-indexed bimodal table
// Using BRAM, so result is delayed by 1 cycle

`include "utils/bram.sv"
`include "core_config.sv"
`include "BPU/include/bpu_types.sv"

module base_predictor
    import core_config::*;
    import bpu_types::*;
(
    input logic clk,
    input logic rst,
    // Query
    input logic [ADDR_WIDTH-1:0] pc_i,
    output logic taken,
    output logic [BPU_COMPONENT_CTR_WIDTH[0]-1:0] ctr,
    // Update
    input logic update_valid,
    input logic [ADDR_WIDTH-1:0] update_pc_i,
    input logic inc_ctr,
    input logic [BPU_COMPONENT_CTR_WIDTH[0]-1:0] update_ctr_i
);

    localparam TABLE_DEPTH = BPU_COMPONENT_TABLE_DEPTH[0];
    localparam TABLE_DEPTH_EXP2 = $clog2(TABLE_DEPTH);
    localparam CTR_WIDTH = BPU_COMPONENT_CTR_WIDTH[0];

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    // Query logic
    logic [TABLE_DEPTH_EXP2-1:0] query_index;
    logic [CTR_WIDTH-1:0] query_entry;

    assign query_index = pc_i[2+TABLE_DEPTH_EXP2-1:2];
    assign taken = (query_entry[CTR_WIDTH-1] == 1'b0);
    assign ctr = (query_entry);

    // Update logic
    logic [TABLE_DEPTH_EXP2-1:0] update_index;
    logic [CTR_WIDTH-1:0] update_content;
    assign update_index = update_pc_i[TABLE_DEPTH_EXP2+1:2];
    always_comb begin
        if (update_valid) begin
            if (update_ctr_i == {1'b0, {CTR_WIDTH - 1{1'b1}}}) begin
                update_content = inc_ctr ? update_ctr_i : update_ctr_i - 1;
            end else if (update_ctr_i == {1'b1, {CTR_WIDTH - 1{1'b0}}}) begin
                update_content = inc_ctr ? update_ctr_i + 1 : update_ctr_i;
            end else begin
                update_content = inc_ctr ? update_ctr_i + 1 : update_ctr_i - 1;
            end
        end else begin
            update_content = 0;
        end
    end

    // Table
    // Port A as read port, Port B as write port
`ifdef BRAM_IP
    bram_bpu_base_predictor pht_table (
        .clka (clk),
        .clkb (clk),
        .ena  (1'b1),
        .enb  (1'b1),
        .wea  (1'b0),
        .web  (update_valid),
        .dina (0),
        .addra(query_index),
        .douta(query_entry),
        .dinb (update_content),
        .addrb(update_index),
        .doutb()
    );
`else
    bram #(
        .DATA_WIDTH(CTR_WIDTH),
        .ADDR_WIDTH(TABLE_DEPTH_EXP2),
        .DATA_DEPTH_EXP2(TABLE_DEPTH_EXP2)
    ) pht_table (
        .clk  (clk),
        .ena  (1'b1),
        .enb  (1'b1),
        .wea  (1'b0),
        .web  (update_valid),
        .dina (0),
        .addra(query_index),
        .douta(query_entry),
        .dinb (update_content),
        .addrb(update_index),
        .doutb()
    );
`endif
endmodule
