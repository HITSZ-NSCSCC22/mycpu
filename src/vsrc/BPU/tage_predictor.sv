// TAGE predictor
// This is the main predictor

`include "defines.sv"
`include "core_config.sv"
`include "BPU/include/bpu_defines.sv"
`include "BPU/include/bpu_types.sv"

`include "utils/priority_encoder.sv"

// Components
`include "BPU/components/base_predictor.sv"
// `include "BPU/components/tagged_predictor.sv"


module tage_predictor
    import core_config::*;
    import bpu_types::*;
(
    input logic clk,
    input logic rst,

    // Input a PC to predict
    input logic [`RegBus] pc_i,

    // Update signals
    input base_predictor_update_info_t base_predictor_update_i,

    output logic [`RegBus] predicted_branch_target_o,
    output logic predict_branch_taken_o,
    output logic predict_valid_o,
    output logic [5*32-1:0] perf_tag_hit_counter
);

    localparam GHR_DEPTH = BPU_GHR_LENGTH;
    localparam TAG_COMPONENT_AMOUNT = BPU_TAG_COMPONENT_NUM;


    // Reset
    logic rst_n;
    assign rst_n = ~rst;

    // Extract packed signals
    // update-prefixed signals are updated related 
    logic update_valid = base_predictor_update_i.valid;
    logic update_predict_correct = 1;
    logic update_branch_taken = base_predictor_update_i.taken;
    logic update_is_conditional = 0;
    // logic [$clog2(TAG_COMPONENT_AMOUNT+1)-1:0] update_provider_id;
    // assign update_provider_id = branch_update_info_i.provider_id;
    logic [`RegBus] update_pc = base_predictor_update_i.pc;

    // Global History Register
    bit [GHR_DEPTH-1:0] GHR;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            GHR <= 0;
        end else if (update_valid) begin
            // Shift left for every valid branch
            GHR <= {GHR[GHR_DEPTH-2:0], update_branch_taken};
        end
    end


    // Base Predictor
    logic base_taken;
    logic base_update_ctr;
    base_predictor u_base_predictor (
        .clk          (clk),
        .rst          (rst),
        .pc_i         (pc_i),
        .update_valid (base_update_ctr),
        .update_info_i({update_pc, update_branch_taken}),
        .taken        (base_taken)
    );

    assign predict_branch_taken_o = base_taken;
    assign predict_valid_o = 0;

    /*


    // The provider id of the accepted prediction
    logic [$clog2(TAG_COMPONENT_AMOUNT+1)-1:0] pred_prediction_id;
    // The provider id of the last hit provider
    logic [$clog2(TAG_COMPONENT_AMOUNT+1)-1:0] altpred_prediction_id;
    // For example, provider 2,4 hit, and provider 1,3 missed
    // then pred is 4, and altpred is 2

    // Tagged Predictors
    // History length of each tagged predictor
    localparam integer provider_ghr_length[TAG_COMPONENT_AMOUNT] = '{5, 15, 44, 130};
    // Query structs
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_taken;
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_hit;
    logic query_tag_useful;
    assign query_tag_useful = (taken[pred_prediction_id] != taken[altpred_prediction_id]);
    // Update structs
    logic [  TAG_COMPONENT_AMOUNT:0] update_ctr;
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_update_ctr;
    assign tag_update_ctr  = update_ctr[TAG_COMPONENT_AMOUNT:1];
    assign base_update_ctr = update_ctr[0];
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_update_useful;
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_update_inc_useful;
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_update_realloc_entry;
    logic [TAGGED_PREDICTOR_USEFUL_WIDTH-1:0] tag_update_query_useful[TAG_COMPONENT_AMOUNT];

    generate
        genvar provider_id;
        for (
            provider_id = 0; provider_id < TAG_COMPONENT_AMOUNT; provider_id = provider_id + 1
        ) begin
            // Update Info
            typedef struct packed {
                logic [`RegBus] pc;

                // 0:            decrease, invalid, decrease, invalid, no reallocate
                // 1:            increase, valid, increase, valid, reallocate
                logic update_ctr;
                logic inc_ctr;
                logic update_useful;
                logic inc_useful;
                logic realloc_entry;
            } update_info_struct;
            update_info_struct update_info;
            assign update_info.pc = update_pc;
            assign update_info.update_ctr = tag_update_ctr[provider_id];
            assign update_info.inc_ctr = update_branch_taken;
            assign update_info.update_useful = tag_update_useful[provider_id];
            assign update_info.inc_useful = tag_update_inc_useful[provider_id];
            assign update_info.realloc_entry = tag_update_realloc_entry[provider_id];

            tagged_predictor #(
                .INPUT_GHR_LENGTH(provider_ghr_length[provider_id]),
                .PHT_DEPTH_EXP2  (11),
                .PHT_USEFUL_WIDTH(TAGGED_PREDICTOR_USEFUL_WIDTH),
                .PC_WIDTH        (`RegWidth)
            ) tag_predictor (
                .clk(clk),
                .rst(rst),
                .global_history_i(GHR[provider_ghr_length[provider_id]:0]),
                .pc_i(pc_i),
                .update_info_i(update_info),
                .update_query_useful_o(tag_update_query_useful[provider_id]),
                .taken_o(tag_taken[provider_id]),
                .tag_hit_o(tag_hit[provider_id])
            );
        end
    endgenerate

    // Update policy
    // CTR policy
    // Update on a correct prediction: update the ctr bits of the provider
    // Update on a wrong prediction: update the ctr bits of the provider, then allocate an entry in a longer history component
    // Useful policy
    // if pred != altpred, then the pred is useful, and the provider is updated when result come
    // if pred is correct, then increase useful counter, else decrese
    typedef struct packed {
        bit [`RegBus] pc;
        bit [$clog2(TAG_COMPONENT_AMOUNT+1)-1:0] pred_provider_id;
        bit useful;
        bit taken;
    } provider_history_entry;
    provider_history_entry provider_history_buffer[PROVIDER_HISTORY_BUFFER_SIZE];

    // Shift left
    assign provider_history_buffer[0] = {
        pc_i, pred_prediction_id, query_tag_useful, predict_branch_taken_o
    };
    always_ff @(posedge clk) begin : shift
        for (integer i = 1; i < PROVIDER_HISTORY_BUFFER_SIZE; i++) begin
            // verilator lint_off WIDTH 
            if (i == provider_history_matched_id + 1) begin
                provider_history_buffer[i] <= 0;
            end else begin
                provider_history_buffer[i] <= provider_history_buffer[i-1];
            end
            // verilator lint_on WIDTH 
        end
    end

    // Generate provider histry entry that matched update pc signal
    bit [PROVIDER_HISTORY_BUFFER_SIZE-1:0] provider_history_match;
    always_comb begin : provider_history_search  // match pc with update signals
        for (integer i = 0; i < PROVIDER_HISTORY_BUFFER_SIZE; i++) begin
            provider_history_match[i] = (branch_pc_i == provider_history_buffer[i].pc);
        end
    end

    // The entry id of the matched pc
    logic [$clog2(PROVIDER_HISTORY_BUFFER_SIZE)-1:0] provider_history_matched_id;
    fpa #(
        .LINES(PROVIDER_HISTORY_BUFFER_SIZE)
    ) u_fpa_provider_history_matched_id (
        .unitary_in(provider_history_match),
        .binary_out(provider_history_matched_id)
    );

    // Get the id of the desired allocate provider
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_update_query_useful_match;
    always_comb begin
        for (integer i = 0; i < TAG_COMPONENT_AMOUNT; i++) begin
            tag_update_query_useful_match[i] = (tag_update_query_useful[i] == 0);
        end
    end
    logic [$clog2(TAG_COMPONENT_AMOUNT+1)-1:0] tag_update_useful_zero_id;
    // Allocation policy, according to TAGE essay
    always_comb begin
        tag_update_useful_zero_id = 0;  // default 0
        for (integer i = TAG_COMPONENT_AMOUNT - 1; i >= 0; i--) begin
            if (tag_update_query_useful_match[i]) begin
                // 1/2 probability when longer history tag want to be selected
                if (tag_update_useful_pingpong_counter[i] != 2'b00) begin
                    // verilator lint_off WIDTH 
                    tag_update_useful_zero_id = i + 1;
                    // verilator lint_on WIDTH 
                end
            end
        end
    end

    // pingpong counter, is a random number array
    bit [31:0] LSFR;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            LSFR <= 32'h00000000;
        end else begin
            // LSFR pseudo random number generator
            LSFR <= {LSFR[30:0], LSFR[31] + LSFR[21] + LSFR[1] + LSFR[0] + 1'b1};
        end
    end
    bit [1:0] tag_update_useful_pingpong_counter[TAG_COMPONENT_AMOUNT];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (integer i = 0; i < TAG_COMPONENT_AMOUNT; i++) begin
                tag_update_useful_pingpong_counter[i] <= 2'b00;
            end
        end else begin
            tag_update_useful_pingpong_counter[0] <= LSFR[1:0];
            for (integer i = 1; i < TAG_COMPONENT_AMOUNT; i++) begin
                tag_update_useful_pingpong_counter[i] <= tag_update_useful_pingpong_counter[i-1];
            end
        end
    end



    assign update_provider_id = provider_history_buffer[provider_history_matched_id].pred_provider_id;

    // Fill update structs
    // update_ctr
    always_comb begin : update_ctr_policy
        // update_ctr, default 0
        for (integer i = 0; i < TAG_COMPONENT_AMOUNT + 1; i++) begin
            update_ctr[i] = 1'b0;
        end
        if (update_is_conditional) begin  // Only update on conditional branches
            update_ctr[update_provider_id] = 1'b1;  // One hot
        end
    end

    // tag_update_useful & tag_update_inc_useful & tag_update_realloc_entry
    always_comb begin : tag_update_policy
        // Default 0
        for (integer i = 0; i < TAG_COMPONENT_AMOUNT; i++) begin
            tag_update_useful[i] = 1'b0;
            tag_update_inc_useful[i] = 1'b0;
            tag_update_realloc_entry[i] = 1'b0;
        end
        if (update_is_conditional) begin  // Only update on conditional branches
            // If useful, update useful bits
            tag_update_useful[update_provider_id-1] = provider_history_buffer[provider_history_matched_id].useful;
            // Increase if correct, else decrease
            tag_update_inc_useful[update_provider_id-1] = (branch_taken_i == provider_history_buffer[provider_history_matched_id].taken);

            // Allocate new entry if failed
            if (branch_taken_i != provider_history_buffer[provider_history_matched_id].taken) begin
                // Allocate entry in longer history component
                if (tag_update_useful_zero_id > update_provider_id) begin  // Have found a slot to allocate
                    tag_update_realloc_entry[tag_update_useful_zero_id-1] = 1'b1;
                end else begin  // No slot to allocate, decrease all useful bits of longer history components
                    // verilator lint_off WIDTH
                    for (integer i = 0; i < TAG_COMPONENT_AMOUNT; i++) begin
                        if (i >= update_provider_id - 1) begin
                            tag_update_useful[i] = 1'b1;
                            tag_update_inc_useful[i] = 1'b0;
                        end
                    end
                    // verilator lint_on WIDTH 
                end
            end
        end
    end

    // Select the longest match provider
    fpa #(
        .LINES(5)
    ) pred_select (
        .unitary_in({tag_hit, 1'b1}),
        .binary_out(pred_prediction_id)
    );
    // Select altpred
    logic [TAG_COMPONENT_AMOUNT:0] altpred_pool;
    always_comb begin
        altpred_pool = {tag_hit, 1'b1};
        if (pred_prediction_id != 0) begin
            altpred_pool[pred_prediction_id] = 1'b0;
        end
    end
    fpa #(
        .LINES(5)
    ) altpred_select (
        .unitary_in(altpred_pool),
        .binary_out(altpred_prediction_id)
    );

    // Output logic
    logic [TAG_COMPONENT_AMOUNT:0] taken;
    assign taken = {tag_taken, base_taken};
    assign predict_branch_taken_o = taken[pred_prediction_id];

    // Counter
    generate
        genvar i;
        for (i = 0; i < 5; i = i + 1) begin
            always @(posedge clk) begin
                perf_tag_hit_counter[i*32+31:i*32] <= perf_tag_hit_counter[i*32+31:i*32] + {31'b0,(i == pred_prediction_id)};
            end
        end
    endgenerate

    */


endmodule  // tage_predictor
