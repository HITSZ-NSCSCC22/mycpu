// TAGE predictor
// This is the main predictor

`include "../defines.v"
`include "branch_predictor/defines.v"


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



  // Tagged Predictors
  wire[3:0] taken;
  wire[3:0] tag_hit;
  reg[1:0] accept_prediction_id;
  localparam integer provider_ghr_length[4] = '{5,10,20,40};

  generate
    genvar provider_id;
    for (provider_id = 0; provider_id <4; provider_id = provider_id +1)
      begin
        gshared_predictor
          #(
            .GLOBAL_HISTORY_LENGTH (provider_ghr_length[0])
          )
          t1(
            .clk              (clk              ),
            .rst              (rst              ),
            .global_history_i (GHR ),
            .pc_i             (pc_i             ),
            .branch_valid     (branch_valid_i     ),
            .branch_taken     (branch_taken_i     ),
            .taken            (taken[provider_id]),
            .tag_hit (tag_hit[provider_id])
          );
      end
  endgenerate


  always @(*)
    begin
      casez (tag_hit)
        4'b1???:
          accept_prediction_id = 3;
        4'b01??:
          accept_prediction_id = 2;
        4'b001?:
          accept_prediction_id = 1;
        4'b0001:
          accept_prediction_id = 0;
        default:
          accept_prediction_id = 0;
      endcase
    end

  assign predict_branch_taken_o = taken[accept_prediction_id];

endmodule //tage_predictor
