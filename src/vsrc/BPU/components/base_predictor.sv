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
    input logic [ADDR_WIDTH-1:0] pc_i,
    input logic update_valid,
    input base_predictor_update_info_t update_info_i,
    output logic taken
);

    localparam TABLE_DEPTH = BPU_COMPONENT_TABLE_DEPTH[0];
    localparam TABLE_DEPTH_EXP2 = $clog2(TABLE_DEPTH);
    localparam CTR_WIDTH = BPU_COMPONENT_CTR_WIDTH[0];

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    // Query logic
    logic [TABLE_DEPTH_EXP2-1:0] query_index = pc_i[2+TABLE_DEPTH_EXP2-1:2];
    logic [       CTR_WIDTH-1:0] query_entry;

    assign taken = (query_entry[CTR_WIDTH-1] == 1'b1);

    // Update logic
    logic [TABLE_DEPTH_EXP2-1:0] update_index = update_info_i.pc[TABLE_DEPTH_EXP2+1:2];
    logic [       CTR_WIDTH-1:0] update_content;
    always_comb begin
        if (update_valid) begin
            if (update_info_i.ctr_bits == {CTR_WIDTH{1'b1}}) begin
                update_content = update_info_i.taken ? update_info_i.ctr_bits : update_info_i.ctr_bits - 1;
            end else if (update_info_i.ctr_bits == {CTR_WIDTH{1'b0}}) begin
                update_content = update_info_i.taken ? update_info_i.ctr_bits + 1 : update_info_i.ctr_bits;
            end else begin
                update_content = update_info_i.taken ? update_info_i.ctr_bits + 1 : update_info_i.ctr_bits - 1;
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
        .web  (1'b1),
        .dina (0),
        .addra(query_index),
        .douta(query_entry),
        .dinb (update_content),
        .addrb(update_index),
        .doutb()
    );
`endif
endmodule
