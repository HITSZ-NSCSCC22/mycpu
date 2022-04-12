// TAGE predictor
// This is the main predictor

`include "../defines.v"
`include "branch_predictor/defines.v"
`include "branch_predictor/utils/fpa.v"


module tage_predictor (
    input wire clk,
    input wire rst,
    input wire [`RegBus] pc_i,

    // Update signals
    input wire branch_valid_i,
    input wire branch_taken_i,
    input wire [`RegBus] branch_pc_i,
    input wire [`RegBus] branch_target_address_i,

    // Prediction
    output wire [`RegBus] predicted_branch_target_o,
    output reg predict_branch_taken_o,
    output wire predict_valid,

    // Counter
    output reg [5*32-1:0] perf_tag_hit_counter
  );

`ifdef DUMP_WAVEFORM

  initial
    begin
      $dumpfile("logs/wave.vcd");
      $dumpvars(0, tage_predictor);
    end
`endif

  // Global History Register
  reg [`GHR_BUS] GHR;
  always @(posedge clk)
    begin
      if (branch_valid_i)
        begin
          // Shift left for every valid branch
          GHR <= {GHR[`GHR_DEPTH-2:0],branch_taken_i};
        end
    end


  // BTB
  wire btb_hit;
  btb u_btb(
        .clk                     (clk                     ),
        .rst                     (rst                     ),
        .query_pc_i              (pc_i              ),
        .update_valid            (branch_valid_i            ),
        .update_pc_i             (branch_pc_i             ),
        .update_branch_target_i  (branch_target_address_i  ),
        .branch_target_address_o (predicted_branch_target_o ),
        .btb_hit                 (btb_hit                 )
      );

  // Base Predictor
  wire base_taken;
  base_predictor
    #(
      .TABLE_DEPTH_EXP2 (12),
      .CTR_WIDTH        (2),
      .PC_WIDTH         (`RegWidth)
    )
    u_base_predictor(
      .clk               (clk               ),
      .rst               (rst               ),
      .pc_i              (pc_i              ),
      .update_valid      (branch_valid_i    ),
      .update_instr_info ({branch_pc_i, branch_taken_i}),
      .taken             (base_taken        )
    );




  // Tagged Predictors
  wire[3:0] tag_taken;
  wire[3:0] tag_hit;
  reg[2:0] accept_prediction_id;
  localparam integer provider_ghr_length[4] = '{5,10,20,40};

  generate
    genvar provider_id;
    for (provider_id = 0; provider_id <4; provider_id = provider_id +1)
      begin
        wire valid = (accept_prediction_id == provider_id) ? branch_valid_i : 0;
        gshared_predictor
          #(
            .INPUT_GHR_LENGTH(provider_ghr_length[provider_id]),
            .PHT_DEPTH_EXP2(12)
          )
          tag_predictor(
            .clk              (clk              ),
            .rst              (rst              ),
            .global_history_i (GHR[provider_ghr_length[provider_id]-1:0]),
            .pc_i             (pc_i             ),
            .update_valid(branch_valid_i),
            .update_instr_info({branch_pc_i, branch_taken_i}),
            .taken            (tag_taken[provider_id]),
            .tag_hit (tag_hit[provider_id])
          );
      end
  endgenerate


  fpa
    #(
      .LINES (5)
    )
    u_fpa(
      .unitary_in ({tag_hit, 1'b0}),
      .binary_out (accept_prediction_id)
    );

  wire[4:0] taken = {tag_taken, base_taken};
  assign predict_branch_taken_o = taken[accept_prediction_id];

  // Counter
  generate
    genvar i;
    for (i=0;
         i<5;
         i=i+1)
      begin
        always @(posedge clk)
          begin
            perf_tag_hit_counter[i*32+31:i*32] <= perf_tag_hit_counter[i*32+31:i*32] + {31'b0,(i == accept_prediction_id)};
          end
      end
  endgenerate

endmodule //tage_predictor
