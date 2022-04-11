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
  wire t1_taken;
  wire t1_hit;
  wire t2_taken;
  wire t2_hit;
  wire t3_taken;
  wire t3_hit;
  wire t4_taken;
  wire t4_hit;

  gshared_predictor
    #(
      .GLOBAL_HISTORY_LENGTH (5)
    )
    t1(
      .clk              (clk              ),
      .rst              (rst              ),
      .global_history_i (GHR ),
      .pc_i             (pc_i             ),
      .branch_valid     (branch_valid_i     ),
      .branch_taken     (branch_taken_i     ),
      .taken            (t1_taken            ),
      .tag_hit (t1_hit)
    );

  gshared_predictor
    #(
      .GLOBAL_HISTORY_LENGTH (10)
    )
    t2(
      .clk              (clk              ),
      .rst              (rst              ),
      .global_history_i (GHR ),
      .pc_i             (pc_i             ),
      .branch_valid     (branch_valid_i     ),
      .branch_taken     (branch_taken_i     ),
      .taken            (t2_taken            ),
      .tag_hit(t2_hit)
    );

  gshared_predictor
    #(
      .GLOBAL_HISTORY_LENGTH (20)
    )
    t3(
      .clk              (clk              ),
      .rst              (rst              ),
      .global_history_i (GHR ),
      .pc_i             (pc_i             ),
      .branch_valid     (branch_valid_i     ),
      .branch_taken     (branch_taken_i     ),
      .taken            (t3_taken            ),
      .tag_hit(t3_hit)
    );

  gshared_predictor
    #(
      .GLOBAL_HISTORY_LENGTH (40)
    )
    t4(
      .clk              (clk              ),
      .rst              (rst              ),
      .global_history_i (GHR ),
      .pc_i             (pc_i             ),
      .branch_valid     (branch_valid_i     ),
      .branch_taken     (branch_taken_i     ),
      .taken            (t4_taken            ),
      .tag_hit (t4_hit)
    );


  always @(posedge clk)
    begin
      if (t4_hit)
        begin
          predict_branch_taken_o <= t4_taken;
          perf_tag_hit_counter[31:0] <= perf_tag_hit_counter[31:0] +1;
        end
      else if(t3_hit)
        begin
          predict_branch_taken_o <= t3_taken;
          perf_tag_hit_counter[2*32-1:32] <= perf_tag_hit_counter[2*32-1:32] +1;
        end
      else if(t2_hit)
        begin
          predict_branch_taken_o <= t2_taken;
          // perf_tag_hit_counter[2] <= perf_tag_hit_counter[2] +1;
        end
      else if(t1_hit)
        begin
          predict_branch_taken_o <= t1_taken;
          // perf_tag_hit_counter[3] <= perf_tag_hit_counter[3] +1;
        end
      else
        begin
          predict_branch_taken_o <= 1;
          // perf_tag_hit_counter[4] <= perf_tag_hit_counter[4] +1;
        end
    end

endmodule //tage_predictor
