// Base Predictor is a pure PC-indexed bimodal table
// Using BRAM, so result is delayed by 1 cycle

`include "branch_predictor/utils/bram.sv"

module base_predictor #(
    parameter TABLE_DEPTH_EXP2 = 10,
    parameter CTR_WIDTH = 2,
    parameter PC_WIDTH = 32
) (
    input logic clk,
    input logic rst,
    input logic [PC_WIDTH-1:0] pc_i,
    input logic update_valid,
    input logic [1+PC_WIDTH+CTR_WIDTH-1:0] update_info_i,
    output logic taken
);

    typedef struct packed {
        logic taken;
        logic [PC_WIDTH-1:0] pc;
        logic [CTR_WIDTH-1:0] ctr_bits;
    } update_info_t;

    update_info_t update_info;
    assign update_info = update_info_i;

    // Table
    bram #(
        .DATA_WIDTH(CTR_WIDTH),
        .DATA_DEPTH_EXP2(TABLE_DEPTH_EXP2)
    ) pht_table (
        .clk  (clk),
        .wea  (1'b0),
        .web  (1'b1),
        .dina (0),
        .addra(query_index),
        .douta(query_entry),
        .dinb (update_content),
        .addrb(update_index),
        .doutb()
    );


    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    // Query logic
    logic [TABLE_DEPTH_EXP2-1:0] query_index = pc_i[2+TABLE_DEPTH_EXP2-1:2];
    logic [       CTR_WIDTH-1:0] query_entry;

    assign taken = (query_entry[CTR_WIDTH-1] == 1'b1);

    // Update logic
    logic [TABLE_DEPTH_EXP2-1:0] update_index = update_info.pc[TABLE_DEPTH_EXP2+1:2];
    logic [       CTR_WIDTH-1:0] update_content;
    always_comb begin
        if (update_valid) begin
            if (update_info.ctr_bits == {CTR_WIDTH{1'b1}}) begin
                update_content = update_info.taken ? update_info.ctr_bits : update_info.ctr_bits - 1;
            end else if (update_info.ctr_bits == {CTR_WIDTH{1'b0}}) begin
                update_content = update_info.taken ? update_info.ctr_bits + 1 : update_info.ctr_bits;
            end else begin
                update_content = update_info.taken ? update_info.ctr_bits + 1 : update_info.ctr_bits - 1;
            end
        end else begin
            update_content = 0;
        end
    end
endmodule
