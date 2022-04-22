// TAGE predictor
// This is the main predictor

`include "../defines.v"
`include "branch_predictor/defines.sv"
`include "branch_predictor/utils/fpa.sv"


module tage_predictor #(
    parameter PROVIDER_HISTORY_BUFFER_SIZE  = 10,
    parameter TAGGED_PREDICTOR_USEFUL_WIDTH = 2
) (
    input logic clk,
    input logic rst,
    input logic [`RegBus] pc_i,

    // Update signals
    input logic branch_valid_i,
    input logic branch_taken_i,
    input logic [`RegBus] branch_pc_i,
    input logic [`RegBus] branch_target_address_i,

    output logic [`RegBus] predicted_branch_target_o,
    output logic predict_branch_taken_o,
    output logic predict_valid,
    output logic [5*32-1:0] perf_tag_hit_counter
);

`ifdef DUMP_WAVEFORM
    initial begin
        $dumpfile("logs/wave.vcd");
        $dumpvars(0, tage_predictor);
    end
`endif


    // Reset
    logic rst_n;
    assign rst_n = ~rst;

    // Global History Register
    bit [`GHR_BUS] GHR;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            GHR <= 0;
        end else if (branch_valid_i) begin
            // Shift left for every valid branch
            GHR <= {GHR[`GHR_DEPTH-2:0], branch_taken_i};
        end
    end


    // BTB
    logic btb_hit;
    btb u_btb (
        .clk                    (clk),
        .rst                    (rst),
        .query_pc_i             (pc_i),
        .update_valid           (branch_valid_i),
        .update_pc_i            (branch_pc_i),
        .update_branch_target_i (branch_target_address_i),
        .branch_target_address_o(predicted_branch_target_o),
        .btb_hit                (btb_hit)
    );

    // Base Predictor
    logic base_taken;
    base_predictor #(
        .TABLE_DEPTH_EXP2(12),
        .CTR_WIDTH       (2),
        .PC_WIDTH        (`RegWidth)
    ) u_base_predictor (
        .clk              (clk),
        .rst              (rst),
        .pc_i             (pc_i),
        .update_valid     (tag_update_valid[0]),
        .update_instr_info({branch_pc_i, branch_taken_i}),
        .taken            (base_taken)
    );


    // The provider id of the accepted prediction
    logic [$clog2(TAG_COMPONENT_AMOUNT):0] pred_prediction_id;
    // The provider id of the last hit provider
    logic [$clog2(TAG_COMPONENT_AMOUNT):0] altpred_prediction_id;
    // For example, provider 2,4 hit, and provider 1,3 missed
    // then pred is 4, and altpred is 2

    // Tagged Predictors
    localparam TAG_COMPONENT_AMOUNT = 4;
    // History length of each tagged predictor
    localparam integer provider_ghr_length[TAG_COMPONENT_AMOUNT] = '{5, 10, 40, 130};
    // Query structs
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_taken;
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_hit;
    logic query_tag_useful;
    assign query_tag_useful = (taken[pred_prediction_id] != taken[altpred_prediction_id]);
    // Update structs
    logic [TAG_COMPONENT_AMOUNT:0] tag_update_valid;  // Including base predictor
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_update_useful;
    logic [TAG_COMPONENT_AMOUNT-1:0] tag_update_useful_inc;
    logic [TAGGED_PREDICTOR_USEFUL_WIDTH-1:0] tag_update_query_useful[TAG_COMPONENT_AMOUNT];


    generate
        genvar provider_id;
        for (
            provider_id = 0; provider_id < TAG_COMPONENT_AMOUNT; provider_id = provider_id + 1
        ) begin
            typedef struct packed {
                logic [`RegWidth-1:0] pc;
                logic taken;
                logic inc;
                logic useful;
            } update_info_struct;
            update_info_struct update_info;
            assign update_info.pc = branch_pc_i;
            assign update_info.taken = branch_taken_i;
            assign update_info.inc = tag_update_useful_inc[provider_id];
            assign update_info.useful = tag_update_useful[provider_id];

            tagged_predictor #(
                .INPUT_GHR_LENGTH(provider_ghr_length[provider_id]),
                .PHT_DEPTH_EXP2  (10),
                .PHT_USEFUL_WIDTH(TAGGED_PREDICTOR_USEFUL_WIDTH),
                .PC_WIDTH        (`RegWidth)
            ) tag_predictor (
                .clk(clk),
                .rst(rst),
                .global_history_i(GHR[provider_ghr_length[provider_id]:0]),
                .pc_i(pc_i),
                .update_valid(tag_update_valid[provider_id+1]),
                .update_instr_info(update_info),
                .update_query_useful_o(tag_update_query_useful[provider_id]),
                .taken(tag_taken[provider_id]),
                .tag_hit(tag_hit[provider_id])
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
        for (integer i = 1; i < 10; i++) begin
            if (i == provider_history_matched_id + 1) begin
                provider_history_buffer[i] <= 0;
            end else provider_history_buffer[i] <= provider_history_buffer[i-1];
        end
    end

    // Generate provider histry entry that matched update pc siganl
    bit [PROVIDER_HISTORY_BUFFER_SIZE-1:0] provider_history_match;
    always_comb begin : provider_history_search  // match pc with update signals
        for (integer i = 0; i < PROVIDER_HISTORY_BUFFER_SIZE; i++) begin
            provider_history_match[i] = (branch_pc_i == provider_history_buffer[i].pc);
        end
    end

    logic [$clog2(
PROVIDER_HISTORY_BUFFER_SIZE
)-1:0] provider_history_matched_id;  // The entry id of the matched pc
    fpa #(
        .LINES(PROVIDER_HISTORY_BUFFER_SIZE)
    ) u_fpa_provider_history_matched_id (
        .unitary_in(provider_history_match),
        .binary_out(provider_history_matched_id)
    );

    logic [TAG_COMPONENT_AMOUNT-1:0] tag_update_query_useful_match;
    always_comb begin
        for (integer i = 0; i < TAG_COMPONENT_AMOUNT; i++) begin
            tag_update_query_useful_match[i] = tag_update_query_useful[i] == 0;
        end
    end
    logic [$clog2(TAG_COMPONENT_AMOUNT+1)-1:0] tag_update_useful_zero_id;
    fpa #(
        .LINES(TAG_COMPONENT_AMOUNT + 1)
    ) u_fpa_tag_update_useful_match (
        .unitary_in({tag_update_query_useful_match, 1'b1}),
        .binary_out(tag_update_useful_zero_id)
    );


    logic [2:0] update_valid_id;
    assign update_valid_id = provider_history_buffer[provider_history_matched_id].pred_provider_id;

    // Fill update structs
    always_comb begin : update_policy
        // Default
        for (integer i = 0; i < TAG_COMPONENT_AMOUNT + 1; i++) begin
            tag_update_valid[i] = 1'b0;
            tag_update_useful[i] = 1'b0;
            tag_update_useful_inc[i] = 1'b0;
        end

        // Useful
        tag_update_useful[update_valid_id-1] = provider_history_buffer[provider_history_matched_id].useful;

        // Valid
        if (branch_taken_i == provider_history_buffer[provider_history_matched_id].taken) begin
            tag_update_valid[update_valid_id] = 1'b1;
            tag_update_useful_inc[update_valid_id-1] = 1'b1;
        end else begin  // Wrong prediction
            tag_update_valid[update_valid_id] = 1'b1;
            tag_update_useful_inc[update_valid_id-1] = 1'b0;

            // Allocate entry in longer history component
            if (tag_update_useful_zero_id > update_valid_id) begin
                tag_update_valid[tag_update_useful_zero_id] = 1'b1;
            end else if (update_valid_id < TAG_COMPONENT_AMOUNT) begin
                tag_update_valid[update_valid_id+1] = 1'b1;
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
        altpred_pool[pred_prediction_id] = 1'b0;
    end
    fpa #(
        .LINES(5)
    ) altpred_select (
        .unitary_in(altpred_pool),
        .binary_out(altpred_prediction_id)
    );

    // Output logic
    logic [4:0] taken;
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

endmodule  // tage_predictor
