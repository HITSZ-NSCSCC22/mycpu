// Gshared predictor as base predictor
`include "defines.sv"
`include "BPU/include/bpu_defines.sv"
`include "BPU/utils/csr_hash.sv"
`include "BPU/utils/fpa.sv"
`include "utils/bram.sv"
`include "core_config.sv"


module tagged_predictor
    import core_config::*;
#(
    parameter INPUT_GHR_LENGTH = 4,
    parameter PHT_DEPTH = 2048,
    parameter PHT_TAG_WIDTH = 11,
    parameter PHT_CTR_WIDTH = 2,
    parameter PHT_USEFUL_WIDTH = 3
) (
    input logic clk,
    input logic rst,

    // Query signal
    input logic global_history_update_i,
    input logic [INPUT_GHR_LENGTH:0] global_history_i,
    input logic [ADDR_WIDTH-1:0] pc_i,

    // Meta
    output logic [PHT_USEFUL_WIDTH-1:0] useful_bits_o,
    output logic [PHT_CTR_WIDTH-1:0] ctr_bits_o,
    output logic [PHT_TAG_WIDTH-1:0] query_tag_o,
    output logic [PHT_TAG_WIDTH-1:0] origin_tag_o,
    output logic [$clog2(PHT_DEPTH)-1:0] hit_index_o,
    // Query result
    output logic taken_o,
    output logic tag_hit_o,

    // Update signals
    input logic [ADDR_WIDTH-1:0] update_pc_i,
    input logic update_valid,
    input logic update_useful,
    input logic inc_useful,
    input logic [PHT_USEFUL_WIDTH-1:0] update_useful_bits_i,
    input logic update_ctr,
    input logic inc_ctr,
    input logic [PHT_CTR_WIDTH-1:0] update_ctr_bits_i,
    input logic realloc_entry,
    input logic [PHT_TAG_WIDTH-1:0] update_tag_i,
    input logic [$clog2(PHT_DEPTH)-1:0] update_index_i
);

    // Parameters
    localparam PHT_ADDR_WIDTH = $clog2(PHT_DEPTH);

    // Reset
    logic rst_n;
    assign rst_n = ~rst;

    // PHT
    typedef struct packed {
        bit [PHT_CTR_WIDTH-1:0] ctr;
        bit [PHT_TAG_WIDTH-1:0] tag;
        bit [PHT_USEFUL_WIDTH-1:0] useful;
    } pht_entry;

    // pht_entry [PHT_DEPTH-1:0] PHT;


    // Query Index
    // Fold GHT input to a fix length, the same as index range
    // Using a CSR, described in PPM-Liked essay
    logic [PHT_ADDR_WIDTH-1:0] hashed_ght_input;
    logic [PHT_ADDR_WIDTH-1:0] query_index, query_index_delay;
    // Tag
    // Generate another hash different from above, as described in PPM-Liked essay
    logic [PHT_TAG_WIDTH-1:0] tag_hash_csr1;
    logic [PHT_TAG_WIDTH-2:0] tag_hash_csr2;
    logic [PHT_TAG_WIDTH-1:0] query_tag, query_tag_delay;
    // Result
    pht_entry query_result;

    // Update entry
    pht_entry update_entry;
    logic [PHT_ADDR_WIDTH-1:0] update_index;



    ////////////////////////////////////////////////////////////////////////////////////////////
    // Query logic
    ////////////////////////////////////////////////////////////////////////////////////////////
    // query_index is Fold(GHR) ^ PC[low] ^ PC[high]
    assign query_index = pc_i[0+:PHT_ADDR_WIDTH] ^ pc_i[0+PHT_ADDR_WIDTH+:PHT_ADDR_WIDTH] ^ hashed_ght_input;
    // query_tag is XORed from pc_i
    // assign query_tag = pc_i[31:31-PHT_TAG_WIDTH+1];
    assign query_tag = pc_i[2+:PHT_TAG_WIDTH] ^ tag_hash_csr1 ^ {tag_hash_csr2, 1'b0};

    always_ff @(posedge clk) begin
        query_index_delay <= query_index;
        query_tag_delay   <= query_tag;
    end

    // Output
    assign ctr_bits_o = query_result.ctr;
    assign useful_bits_o = query_result.useful;
    assign hit_index_o = query_index_delay;
    assign query_tag_o = query_tag_delay;
    assign origin_tag_o = query_result.tag;
    assign taken_o = (query_result.ctr[PHT_CTR_WIDTH-1] == 1'b1);
    assign tag_hit_o = (query_tag_delay == query_result.tag);


    ///////////////////////////////////////////////////////////////////////////////////////////
    // Update logic
    ///////////////////////////////////////////////////////////////////////////////////////////
    assign update_index = update_index_i;
    // Main update comb
    always_comb begin
        update_entry.tag = update_tag_i;
        // Update CTR bits
        if (update_ctr) begin
            case (update_ctr_bits_i)
                {PHT_CTR_WIDTH{1'b0}} : begin
                    update_entry.ctr =  inc_ctr ? {{PHT_CTR_WIDTH-1{1'b0}},1'b1} : {PHT_CTR_WIDTH{1'b0}};
                end
                {PHT_CTR_WIDTH{1'b1}} : begin
                    update_entry.ctr =  inc_ctr ? {PHT_CTR_WIDTH{1'b1}} : {{PHT_CTR_WIDTH-1{1'b1}},1'b0};
                end
                default: begin
                    update_entry.ctr = inc_ctr ? update_ctr_bits_i + 1 : update_ctr_bits_i - 1;
                end
            endcase
        end else update_entry.ctr = update_ctr_bits_i;

        // Update useful bits
        if (update_useful) begin
            case (update_useful_bits_i)
                {PHT_USEFUL_WIDTH{1'b1}} : begin
                    update_entry.useful = inc_useful ? {PHT_USEFUL_WIDTH{1'b1}} : update_useful_bits_i - 1;
                end
                {PHT_USEFUL_WIDTH{1'b0}} : begin
                    update_entry.useful =  inc_useful ? update_useful_bits_i + 1 : {PHT_USEFUL_WIDTH{1'b0}};
                end
                default: begin
                    update_entry.useful = inc_useful ? update_useful_bits_i + 1 : update_useful_bits_i - 1;
                end
            endcase
        end else update_entry.useful = update_useful_bits_i;
        // Alocate new entry 
        if (realloc_entry) begin
            update_entry.ctr = {1'b1, {(PHT_CTR_WIDTH - 1) {1'b0}}};  // Reset CTR
            update_entry.useful = 0;  // Clear useful
        end
    end


    // CSR hash
    csr_hash #(
        .INPUT_LENGTH (INPUT_GHR_LENGTH + 1),
        .OUTPUT_LENGTH(PHT_ADDR_WIDTH)
    ) ght_hash_csr_hash (
        .clk   (clk),
        .rst   (rst),
        .data_update_i(global_history_update_i),
        .data_i(global_history_i),
        .hash_o(hashed_ght_input)
    );
    csr_hash #(
        .INPUT_LENGTH (INPUT_GHR_LENGTH + 1),
        .OUTPUT_LENGTH(PHT_TAG_WIDTH)
    ) pc_hash_csr_hash1 (
        .clk   (clk),
        .rst   (rst),
        .data_update_i(global_history_update_i),
        .data_i(global_history_i),
        .hash_o(tag_hash_csr1)
    );
    csr_hash #(
        .INPUT_LENGTH (INPUT_GHR_LENGTH + 1),
        .OUTPUT_LENGTH(PHT_TAG_WIDTH - 1)
    ) pc_hash_csr_hash2 (
        .clk   (clk),
        .rst   (rst),
        .data_update_i(global_history_update_i),
        .data_i(global_history_i),
        .hash_o(tag_hash_csr2)
    );


    // Table
    // Port A as read port, Port B as write port

`ifdef BRAM_IP
    bram_bpu_tagged_predictor pht_table (
        .clka (clk),
        .clkb (clk),
        .ena  (1'b1),
        .enb  (1'b1),
        .wea  (1'b0),
        .web  (update_valid),
        .dina (0),
        .addra(query_index),
        .douta(query_result),
        .dinb (update_entry),
        .addrb(update_index),
        .doutb()
    );
`else
    bram #(
        .DATA_WIDTH($bits(pht_entry)),
        .DATA_DEPTH_EXP2(PHT_ADDR_WIDTH),
    ) pht_table (
        .clk  (clk),
        .ena  (1'b1),
        .enb  (1'b1),
        .wea  (1'b0),
        .web  (update_valid),
        .dina (0),
        .addra(query_index),
        .douta(query_result),
        .dinb (update_entry),
        .addrb(update_index),
        .doutb()
    );
`endif

endmodule
