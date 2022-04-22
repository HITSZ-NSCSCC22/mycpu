// Gshared predictor as base predictor
`include "../defines.v"
`include "branch_predictor/defines.sv"
`include "branch_predictor/utils/csr_hash.sv"
`include "branch_predictor/utils/fpa.sv"


module tagged_predictor #(
    parameter INPUT_GHR_LENGTH = 4,
    parameter PC_WIDTH = 32,
    parameter PHT_DEPTH_EXP2 = 10,
    parameter PHT_TAG_WIDTH = 8,
    parameter PHT_CTR_WIDTH = 3,
    parameter PHT_USEFUL_WIDTH = 2,
    parameter HASH_BUFFER_SIZE = 10
) (
    input logic clk,
    input logic rst,

    // Require one more bit input
    input logic [INPUT_GHR_LENGTH:0] global_history_i,
    input logic [PC_WIDTH-1:0] pc_i,

    // Update signals
    input logic update_valid,
    input logic [PC_WIDTH+2:0] update_instr_info,
    // Useful counter for update policy
    output logic [PHT_USEFUL_WIDTH-1:0] update_query_useful_o,

    output logic taken,
    output logic tag_hit
);

    // Reset
    logic rst_n;
    assign rst_n = ~rst;

    // Update Info
    typedef struct packed {
        logic [PC_WIDTH-1:0] pc;
        logic taken;
        logic inc;
        logic useful;
    } update_info_struct;
    update_info_struct update_info;
    assign update_info = update_instr_info;

    // PHT
    typedef struct packed {
        bit [PHT_CTR_WIDTH-1:0] ctr;
        bit [PHT_TAG_WIDTH-1:0] tag;
        bit [PHT_USEFUL_WIDTH-1:0] useful;

    } pht_entry;
    pht_entry PHT[2**PHT_DEPTH_EXP2];


    // Query Index
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
    // query_index in Fold(GHR) ^ PC[low] ^ PC[high]
    logic [PHT_DEPTH_EXP2-1:0] query_index;
    assign query_index = (hashed_ght_input ^ pc_i[PHT_DEPTH_EXP2-1:0] ^ pc_i[PHT_DEPTH_EXP2*2-1:PHT_DEPTH_EXP2]);

    // Tag
    // Generate another hash different from above, as described in PPM-Liked essay
    logic [PHT_TAG_WIDTH-1:0] pc_hash_csr1;
    logic [PHT_TAG_WIDTH-2:0] pc_hash_csr2;
    csr_hash #(
        .INPUT_LENGTH (INPUT_GHR_LENGTH + 1),
        .OUTPUT_LENGTH(PHT_TAG_WIDTH)
    ) pc_hash_csr_hash1 (
        .clk   (clk),
        .rst   (rst),
        .data_i(global_history_i),
        .hash_o(pc_hash_csr1)
    );
    csr_hash #(
        .INPUT_LENGTH (INPUT_GHR_LENGTH + 1),
        .OUTPUT_LENGTH(PHT_TAG_WIDTH - 1)
    ) pc_hash_csr_hash2 (
        .clk   (clk),
        .rst   (rst),
        .data_i(global_history_i),
        .hash_o(pc_hash_csr2)
    );

    logic [PHT_TAG_WIDTH-1:0] query_tag;
    assign query_tag = pc_i[PHT_TAG_WIDTH-1:0] ^ pc_hash_csr1 ^ {pc_hash_csr2, 1'b0};




    // Query logic ========================================== 
    pht_entry query_result;
    assign query_result = PHT[query_index];

    // Assign Output
    assign taken = (query_result.ctr[PHT_CTR_WIDTH-1] == 1'b1);
    assign tag_hit = (query_tag == query_result.tag);


    // Use a buffer to hold the query_index and pc
    // This is used when branch update came in with uncertain delay
    typedef struct packed {
        bit valid;
        bit [PC_WIDTH-1:0] pc;
        bit [PHT_DEPTH_EXP2-1:0] index;
        bit [PHT_TAG_WIDTH-1:0] tag;
    } info_buffer_entry;
    info_buffer_entry hash_buffer[HASH_BUFFER_SIZE];
    logic [HASH_BUFFER_SIZE-1:0] pc_match_table;  // indicates which entry in the buffer is a match

    // Move from lower to higher
    assign hash_buffer[0] = {(pc_i != 0), pc_i, query_index, query_tag};
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
                pc_match_table[i] = (hash_buffer[i].pc == update_info.pc);
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

    // Give out the matched useful counter
    assign update_query_useful_o = PHT[update_index].useful;

    // Main update ff
    always_ff @(posedge clk or negedge rst_n) begin : update_ff
        if (!rst_n) begin
            // Reset all PHT, useful to 0, ctr to weak taken
            for (integer i = 0; i < 2 ** PHT_DEPTH_EXP2; i = i + 1) begin
                PHT[i].ctr = {1'b1, {PHT_CTR_WIDTH - 1{1'b0}}};
                PHT[i].tag = 0;
                PHT[i].useful = 0;
            end
        end else begin
            if (update_valid & update_match_valid) begin
                // Update PHT entry
                case (PHT[update_index].ctr)
                    {PHT_CTR_WIDTH{1'b0}} : begin
                        PHT[update_index].ctr <= update_info.taken ? {{PHT_CTR_WIDTH-1{1'b0}},1'b1} : {PHT_CTR_WIDTH{1'b0}};
                    end
                    {PHT_CTR_WIDTH{1'b1}} : begin
                        PHT[update_index].ctr <= update_info.taken ? {PHT_CTR_WIDTH{1'b1}}:{{PHT_CTR_WIDTH-1{1'b1}},1'b0};
                    end
                    default: begin
                        PHT[update_index].ctr <= update_info.taken ? PHT[update_index].ctr +1 : PHT[update_index].ctr -1;
                    end
                endcase

                // Update useful
                if (update_info.useful) begin
                    case (PHT[update_index].useful)
                        {PHT_USEFUL_WIDTH{1'b1}} : begin
                            PHT[update_index].useful <= update_info.inc ? {PHT_USEFUL_WIDTH{1'b1}} : PHT[update_index].useful -1;
                        end
                        {PHT_USEFUL_WIDTH{1'b0}} : begin
                            PHT[update_index].useful <= update_info.inc ? PHT[update_index].useful +1 : {PHT_USEFUL_WIDTH{1'b0}};
                        end
                        default: begin
                            PHT[update_index].useful <= update_info.inc ? PHT[update_index].useful +1 : PHT[update_index].useful -1;
                        end
                    endcase
                end

                if (PHT[update_index].tag != update_tag) // Miss tag
                begin
                    PHT[update_index].tag <= update_tag;
                    PHT[update_index].ctr <= {1'b1, {PHT_CTR_WIDTH - 1{1'b0}}};  // Reset CTR
                    PHT[update_index].useful <= 0;  // Reset useful counter
                end
            end
        end
    end

endmodule
