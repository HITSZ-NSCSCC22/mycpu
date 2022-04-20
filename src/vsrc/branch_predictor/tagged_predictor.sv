// Gshared predictor as base predictor
`include "../defines.v"
`include "branch_predictor/defines.v"
`include "branch_predictor/utils/csr_hash.sv"
`include "branch_predictor/utils/fpa.sv"


module tagged_predictor #(
    parameter INPUT_GHR_LENGTH = 4,
    parameter PC_WIDTH = 32,
    parameter PHT_DEPTH_EXP2 = 10,
    parameter PHT_TAG_WIDTH = 8,
    parameter HASH_BUFFER_SIZE = 10
) (
    input logic clk,
    input logic rst,

    // Require one more bit input
    input logic [INPUT_GHR_LENGTH:0] global_history_i,
    input logic [PC_WIDTH-1:0] pc_i,

    // Update signals
    input logic update_valid,
    input logic [PC_WIDTH:0] update_instr_info,

    output logic taken,
    output logic tag_hit
);

    // Reset
    logic rst_n;
    assign rst_n = ~rst;

    // Unpack update instr info
    logic [PC_WIDTH-1:0] update_pc;
    assign update_pc = update_instr_info[PC_WIDTH:1];
    logic update_taken;
    assign update_taken = update_instr_info[0];

    // PHT
    // - entry: {3bits bimodal, xbits tag}
    logic [PHT_TAG_WIDTH+2:0] PHT[2**PHT_DEPTH_EXP2];


    // Fold GHT input to a fix length, the same as index range
    // Using a CSR, described in PPM-Liked essay
    logic [PHT_DEPTH_EXP2-1:0] hashed_ght_input;
    csr_hash #(
        .INPUT_LENGTH (INPUT_GHR_LENGTH + 1),
        .OUTPUT_LENGTH(PHT_DEPTH_EXP2)
    ) ght_hash_csr_hash (
        .clk   (clk),
        .rst   (rst),
        .data_i(global_history_i),
        .hash_o(hashed_ght_input)
    );



    // Tag
    // Generate a hashed tage from only pc, as described in PPM-Liked essay
    // csr1 < ght[high] < csr2 < ght[0]
    logic [PHT_TAG_WIDTH-1:0] pc_hash_csr1;
    logic [PHT_TAG_WIDTH-2:0] pc_hash_csr2;
    csr_hash #(
        .INPUT_LENGTH (INPUT_GHR_LENGTH + 1),
        .OUTPUT_LENGTH(PHT_TAG_WIDTH - 1)
    ) pc_hash_csr_hash2 (
        .clk   (clk),
        .rst   (rst),
        .data_i(global_history_i),
        .hash_o(pc_hash_csr2)
    );
    csr_hash #(
        .INPUT_LENGTH (INPUT_GHR_LENGTH + 1),
        .OUTPUT_LENGTH(PHT_TAG_WIDTH)
    ) pc_hash_csr_hash1 (
        .clk   (clk),
        .rst   (rst),
        .data_i(global_history_i),
        .hash_o(pc_hash_csr1)
    );

    logic [PHT_TAG_WIDTH-1:0] hashed_pc_tag;
    assign hashed_pc_tag = pc_i[PHT_TAG_WIDTH-1:0] ^ pc_hash_csr1 ^ {pc_hash_csr2, 1'b0};



    // hash with pc, and concatenate to PHT_DEPTH_EXP2
    // the low 2bits of pc is usually 0, so use upper bits
    logic [PHT_DEPTH_EXP2-1:0] query_hashed_index;
    assign query_hashed_index = (hashed_ght_input ^ pc_i[PHT_DEPTH_EXP2-1:0] ^ pc_i[PHT_DEPTH_EXP2*2-1:PHT_DEPTH_EXP2]);

    // Query logic ========================================== 
    logic [2:0] query_result_bimodal;
    assign query_result_bimodal = PHT[query_hashed_index][PHT_TAG_WIDTH+2:PHT_TAG_WIDTH];
    logic [PHT_TAG_WIDTH-1:0] query_result_tag;
    assign query_result_tag = PHT[query_hashed_index][PHT_TAG_WIDTH-1:0];

    assign taken = (query_result_bimodal[2] == 1'b1);
    assign tag_hit = (hashed_pc_tag == query_result_tag);
    // assign tag_hit = 1;


    // Use a buffer to hold the query_index and pc
    // entry: {valid 1, pc PC_WIDTH, query_index}
    typedef struct packed {
        bit valid;
        bit [PC_WIDTH-1:0] pc;
        bit [PHT_DEPTH_EXP2-1:0] index;
        bit [PHT_TAG_WIDTH-1:0] tag;
    } info_buffer_entry;
    info_buffer_entry hash_buffer[HASH_BUFFER_SIZE];
    logic [HASH_BUFFER_SIZE-1:0] pc_match_table;  // indicates which entry in the buffer is a match

    // Move from lower to higher
    assign hash_buffer[0] = {(pc_i != 0), pc_i, query_hashed_index, hashed_pc_tag};
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
                pc_match_table[i] = (hash_buffer[i].pc == update_pc);
            end
        end
    endgenerate

    // Get match index
    logic [$clog2(HASH_BUFFER_SIZE+1)-1:0] update_match_index;
    fpa #(
        .LINES(HASH_BUFFER_SIZE)
    ) u_fpa (
        .unitary_in({pc_match_table}),
        .binary_out(update_match_index)
    );
    logic [PHT_DEPTH_EXP2-1:0] update_index;
    assign update_index = hash_buffer[update_match_index].index;
    logic [PHT_TAG_WIDTH-1:0] update_tag;
    assign update_tag = hash_buffer[update_match_index].tag;
    logic update_match_valid;
    assign update_match_valid = (update_match_index != 0) & hash_buffer[update_match_index].valid;



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
