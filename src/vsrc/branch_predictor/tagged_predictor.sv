// Gshared predictor as base predictor
`include "../defines.v"
`include "branch_predictor/defines.v"
`include "branch_predictor/folder_func.v"
`include "branch_predictor/utils/fpa.v"


module tagged_predictor #(
    parameter INPUT_GHR_LENGTH = 4,
    parameter PC_WIDTH = 32,
    parameter PHT_DEPTH_EXP2 = 10,
    parameter PHT_TAG_WIDTH = 10,
    parameter HASH_BUFFER_SIZE = 10
) (
    input wire clk,
    input wire rst,
    input wire [INPUT_GHR_LENGTH-1:0] global_history_i,
    input wire [PC_WIDTH-1:0] pc_i,
    input wire update_valid,
    input wire [PC_WIDTH:0] update_instr_info,
    output wire taken,
    output wire tag_hit
);

    // Reset
    wire rst_n = ~rst;

    // Unpack update instr info
    wire [PC_WIDTH-1:0] update_pc = update_instr_info[PC_WIDTH:1];
    wire update_taken = update_instr_info[0];

    // PHT
    // - entry: {3bits bimodal, xbits tag}
    reg [PHT_TAG_WIDTH+2:0] PHT[2**PHT_DEPTH_EXP2];


    // Fold GHT input to a fix length, the same as index range
    wire [PHT_DEPTH_EXP2-1:0] hashed_ght_input;
    folder_func #(
        .INPUT_LENGTH  (INPUT_GHR_LENGTH),
        .OUTPUT_LENGTH (PHT_DEPTH_EXP2),
        .MAX_FOLD_ROUND(6)
    ) ght_hash (
        .var_i(global_history_i),
        .var_o(hashed_ght_input)
    );

    // Tag
    // wire [`PHT_TAG_WIDTH-1:0] hashed_pc_tag = pc_i[2+`PHT_TAG_WIDTH-1:2];
    wire [PHT_TAG_WIDTH-1:0] hashed_pc_tag;
    folder_func #(
        .INPUT_LENGTH  (PC_WIDTH),
        .OUTPUT_LENGTH (PHT_TAG_WIDTH),
        .MAX_FOLD_ROUND(4)
    ) pc_hash (
        .var_i(pc_i),
        .var_o(hashed_pc_tag)
    );



    // hash with pc, and concatenate to `PHT_DEPTH_LOG2
    // the low 2bits of pc is usually 0, so use upper bits
    wire [PHT_DEPTH_EXP2-1:0] query_hashed_index = {
        hashed_ght_input ^ pc_i[2+PHT_DEPTH_EXP2-1:2]
    };

    // Query logic ========================================== 
    wire [2:0] query_result_bimodal = PHT[query_hashed_index][PHT_TAG_WIDTH+2:PHT_TAG_WIDTH];
    wire [PHT_TAG_WIDTH-1:0] query_result_tag = PHT[query_hashed_index][PHT_TAG_WIDTH-1:0];

    assign taken   = (query_result_bimodal[2] == 1'b1);
    assign tag_hit = (hashed_pc_tag == query_result_tag);
    // assign tag_hit = 1;


    // Use a buffer to hold the query_index and pc
    // entry: {valid 1, pc PC_WIDTH, query_index}
    localparam HASH_BUFFER_WIDTH = 1 + PC_WIDTH + PHT_DEPTH_EXP2;
    reg [HASH_BUFFER_WIDTH-1:0] hash_buffer[HASH_BUFFER_SIZE];
    wire [HASH_BUFFER_SIZE-1:0] pc_match_table;  // indicates which entry in the buffer is a match

    // Move from lower to higher
    // always @(posedge clk)
    // begin
    assign hash_buffer[0] = {(pc_i != 0), pc_i, query_hashed_index};
    // end
    generate
        for (genvar i = 1; i < HASH_BUFFER_SIZE; i = i + 1) begin
            always @(posedge clk) begin
                hash_buffer[i] <= hash_buffer[i-1];
            end
        end
    endgenerate

    // Match PC
    generate
        for (genvar i = 0; i < HASH_BUFFER_SIZE; i = i + 1) begin
            always @(*) begin
                pc_match_table[i] = (hash_buffer[i][PC_WIDTH+PHT_DEPTH_EXP2-1:PHT_DEPTH_EXP2] == update_pc);
            end
        end
    endgenerate

    // Get match index
    wire [$clog2(HASH_BUFFER_SIZE+1)-1:0] update_match_index;
    fpa #(
        .LINES(HASH_BUFFER_SIZE + 1)
    ) u_fpa (
        .unitary_in({pc_match_table, 1'b1}),  // Set lowest bit to 1 to catch missing condition
        .binary_out(update_match_index)
    );
    wire [PHT_DEPTH_EXP2-1:0] update_index = hash_buffer[update_match_index-1][PHT_DEPTH_EXP2-1:0];
    wire update_match_valid                = ~(update_match_index == 0) & (hash_buffer[update_match_index][HASH_BUFFER_WIDTH-1] == 1);

    // Calculate update tag
    wire [PHT_TAG_WIDTH-1:0] update_tag;
    folder_func #(
        .INPUT_LENGTH  (PC_WIDTH),
        .OUTPUT_LENGTH (PHT_TAG_WIDTH),
        .MAX_FOLD_ROUND(4)
    ) u_folder_func (
        .var_i(update_pc),
        .var_o(update_tag)
    );




    // Update logic =========================================================== 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all PHT to 01
            for (integer i = 0; i < 2 ** PHT_DEPTH_EXP2; i = i + 1) begin
                PHT[i] = {3'b100, {PHT_TAG_WIDTH{1'b0}}};
            end
        end else begin
            if (update_valid & update_match_valid) begin
                // 000,001,010,011 | 100,101,110,111

                case (PHT[update_index][PHT_TAG_WIDTH+2:PHT_TAG_WIDTH])
                    3'b000: begin
                        PHT[update_index][PHT_TAG_WIDTH+2:PHT_TAG_WIDTH] <= update_taken ? 3'b001 : 3'b000;
                    end
                    3'b111: begin
                        PHT[update_index][PHT_TAG_WIDTH+2:PHT_TAG_WIDTH] <= update_taken ? 3'b111 : 3'b110;
                    end
                    default: begin
                        PHT[update_index][PHT_TAG_WIDTH+2:PHT_TAG_WIDTH] <= update_taken ? PHT[update_index][PHT_TAG_WIDTH+2:PHT_TAG_WIDTH] +1 : PHT[update_index][PHT_TAG_WIDTH+2:PHT_TAG_WIDTH] -1;
                    end
                endcase

                if (PHT[update_index][PHT_TAG_WIDTH-1:0] != update_tag) // Miss tag
                begin                                                   // Do swap
                    PHT[update_index][PHT_TAG_WIDTH-1:0] <= {update_tag};
                end
            end
        end
    end

endmodule
