// Base Predictor is a pure PC-indexed bimodal table

module base_predictor #(
    parameter TABLE_DEPTH_EXP2 = 10,
    parameter CTR_WIDTH = 2,
    parameter PC_WIDTH = 32
) (
    input logic clk,
    input logic rst,
    input logic [PC_WIDTH-1:0] pc_i,
    input logic update_valid,
    input logic [PC_WIDTH:0] update_instr_info,
    output logic taken
);

    // Table
    bit   [CTR_WIDTH-1:0] PHT   [2**TABLE_DEPTH_EXP2];

    // Reset signal
    logic                 rst_n;
    assign rst_n = ~rst;

    // Query logic
    logic [TABLE_DEPTH_EXP2-1:0] query_index = pc_i[2+TABLE_DEPTH_EXP2-1:2];
    logic [       CTR_WIDTH-1:0] query_entry = PHT[query_index];

    assign taken = (query_entry[CTR_WIDTH-1] == 1'b1);

    // Update logic
    logic [        PC_WIDTH-1:0] update_pc = update_instr_info[PC_WIDTH:1];
    logic [TABLE_DEPTH_EXP2-1:0] update_index = update_pc[TABLE_DEPTH_EXP2+1:2];
    logic                        update_taken = update_instr_info[0];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (integer i = 0; i < 2 ** TABLE_DEPTH_EXP2; i = i + 1) begin
                PHT[i] = {1'b1, {CTR_WIDTH - 1{1'b0}}};
            end
        end else if (update_valid) begin
            if (PHT[update_index] == {CTR_WIDTH{1'b1}}) begin
                PHT[update_index] <= update_taken ? PHT[update_index] : PHT[update_index] - 1;
            end else if (PHT[update_index] == {CTR_WIDTH{1'b0}}) begin
                PHT[update_index] <= update_taken ? PHT[update_index] + 1 : PHT[update_index];
            end else begin
                PHT[update_index] <= update_taken ? PHT[update_index] + 1 : PHT[update_index] - 1;
            end
        end
    end
endmodule
