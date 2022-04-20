// TAGE predictor
// This is the main predictor

`include "../defines.v"
`include "branch_predictor/defines.v"
`include "branch_predictor/utils/fpa.sv"


module tage_predictor (
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

    // Global History Register
    bit [`GHR_BUS] GHR;
    always @(posedge clk) begin
        if (branch_valid_i) begin
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




    // Tagged Predictors
    localparam TAG_COMPONENT_AMOUNT = 4;
    logic [3:0] tag_taken;
    logic [3:0] tag_hit;
    logic [$clog2(TAG_COMPONENT_AMOUNT):0] accept_prediction_id;
    logic [4:0] tag_update_valid;
    localparam integer provider_ghr_length[TAG_COMPONENT_AMOUNT] = '{10, 20, 40, 80};

    generate
        genvar provider_id;
        for (
            provider_id = 0; provider_id < TAG_COMPONENT_AMOUNT; provider_id = provider_id + 1
        ) begin
            logic valid = (accept_prediction_id == provider_id) ? branch_valid_i : 0;
            tagged_predictor #(
                .INPUT_GHR_LENGTH(provider_ghr_length[provider_id]),
                .PHT_DEPTH_EXP2  (10)
            ) tag_predictor (
                .clk              (clk),
                .rst              (rst),
                .global_history_i (GHR[provider_ghr_length[provider_id]:0]),
                .pc_i             (pc_i),
                .update_valid     (tag_update_valid[provider_id+1]),
                .update_instr_info({branch_pc_i, branch_taken_i}),
                .taken            (tag_taken[provider_id]),
                .tag_hit          (tag_hit[provider_id])
            );
        end
    endgenerate

    // Update policy
    // Update on a correct prediction: update the ctr bits of the provider
    // Update on a wrong prediction: update the ctr bits of the provider, then allocate an entry in a longer history component
    // 
    // Buffer content: pc, accepted_provider_id, predicted_taken
    typedef struct packed {
        bit [`RegBus] pc;
        bit [$clog2(TAG_COMPONENT_AMOUNT+1)-1:0] accepted_provider_id;
        bit taken;
    } provider_history_entry;
    provider_history_entry provider_history_buffer[10];  // TODO: parameterize 10
    assign provider_history_buffer[0] = {pc_i, accept_prediction_id, predict_branch_taken_o};
    always_ff @(posedge clk) begin : shift
        for (integer i = 1; i < 10; i++) begin
            if (i == provider_history_matched_id + 1) begin
                provider_history_buffer[i] <= 0;
            end else provider_history_buffer[i] <= provider_history_buffer[i-1];
        end
    end
    bit [10-1:0] provider_history_match;
    always_comb begin : provider_history_search  // match pc with update signals
        for (integer i = 0; i < 10; i++) begin
            provider_history_match[i] = (branch_pc_i == provider_history_buffer[i].pc);
        end
    end

    logic [$clog2(10)-1:0] provider_history_matched_id;  // The entry id of the matched pc
    fpa #(
        .LINES(10)
    ) u_fpa_provider_history_matched_id (
        .unitary_in(provider_history_match),
        .binary_out(provider_history_matched_id)
    );

    logic [2:0] update_valid_id;
    assign update_valid_id = provider_history_buffer[provider_history_matched_id].accepted_provider_id;
    always_comb begin : update_policy
        for (integer i = 0; i < TAG_COMPONENT_AMOUNT + 1; i++) begin
            tag_update_valid[i] = 1'b0;
        end
        if (branch_taken_i == provider_history_buffer[provider_history_matched_id].taken) begin
            tag_update_valid[update_valid_id] = 1'b1;
        end else begin  // Wrong prediction
            tag_update_valid[update_valid_id] = 1'b1;
            if (update_valid_id < TAG_COMPONENT_AMOUNT) begin
                tag_update_valid[update_valid_id+1] = 1'b1;
            end
        end
    end


    fpa #(
        .LINES(5)
    ) u_fpa (
        .unitary_in({tag_hit, 1'b1}),
        .binary_out(accept_prediction_id)
    );

    logic [4:0] taken = {tag_taken, base_taken};
    assign predict_branch_taken_o = taken[accept_prediction_id];

    // Counter
    generate
        genvar i;
        for (i = 0; i < 5; i = i + 1) begin
            always @(posedge clk) begin
                perf_tag_hit_counter[i*32+31:i*32] <= perf_tag_hit_counter[i*32+31:i*32] + {31'b0,(i == accept_prediction_id)};
            end
        end
    endgenerate

endmodule  // tage_predictor
