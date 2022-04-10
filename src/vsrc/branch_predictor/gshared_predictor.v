// Gshared predictor as base predictor
`include "../defines.v"
`include "branch_predictor/defines.v"


module gshared_predictor #(
    parameter GLOBAL_HISTORY_LENGTH = 4
  ) (
    input wire clk,
    input wire rst,
    input wire [`GHR_BUS] global_history_i,
    input wire [`RegBus] pc_i,

    // Update signals
    input wire branch_valid,
    input wire branch_taken,

    output wire taken
  );

  // PHT, each entry is a bimodal predictor
  reg[1:0] PHT[`PHT_DEPTH];

  wire [`MAX_GHT_LENGTH-1:0] global_history_hashing[`MAX_GHT_LENGTH_LOG2];
  // Concat GHT input to desired length
  assign global_history_hashing[0] = {{(`MAX_GHT_LENGTH - GLOBAL_HISTORY_LENGTH){1'b0}}, global_history_i[GLOBAL_HISTORY_LENGTH-1:0]};

  // Fold GHT input from `MAX_GHT_LENGTH to 1
  genvar i;
  generate
    for (i = `MAX_GHT_LENGTH_LOG2-1; i >1; i = i-1)
      begin
        wire [`MAX_GHT_LENGTH-1:0] global_history_hashing_folder = global_history_hashing[`MAX_GHT_LENGTH_LOG2-1-i];

        wire [`MAX_GHT_LENGTH-1:0] op1 = {{(`MAX_GHT_LENGTH-2**i){1'b0}},global_history_hashing_folder[2**i-1:0]};
        wire [`MAX_GHT_LENGTH-1:0] op2 ={{(`MAX_GHT_LENGTH-2**i){1'b0}},global_history_hashing_folder[2**i*2-1:2**i]};

        assign global_history_hashing[`MAX_GHT_LENGTH_LOG2-i] = op1 ^ op2;
      end
  endgenerate
  // Select 8 as index
  wire [7:0] hashed_ght_input = global_history_hashing[`MAX_GHT_LENGTH - 4][7:0];

  // hash with pc, and concatenate to `PHT_DEPTH_LOG2
  wire [`PHT_DEPTH_LOG2-1:0] query_hashed_index = {hashed_ght_input ^ pc_i[9:2]}[`PHT_DEPTH_LOG2-1:0];

  // Query logic //////////////////////////////////
  wire [1:0] query_entry = PHT[query_hashed_index];
  assign taken = (query_entry == 2'b11) | (query_entry == 2'b01);

  // Update logic //////////////////////////////////

  // This buffer is used to store the hashed index for update
  reg[`PHT_DEPTH_LOG2-1:0] hashed_index_buffer [`FEEDBACK_LATENCY];
  always @(posedge clk)
    begin
      hashed_index_buffer[0] <= query_hashed_index;
    end
  genvar index_id;
  generate
    for (index_id = 1; index_id < `FEEDBACK_LATENCY; index_id = index_id + 1)
      begin
        always @(posedge clk)
          begin
            hashed_index_buffer[index_id] <= hashed_index_buffer[index_id - 1];
          end
      end
  endgenerate

  // Select index from buffer and update
  wire [`PHT_DEPTH_LOG2-1:0] update_index = hashed_index_buffer[`FEEDBACK_LATENCY-1];
  always @(posedge clk)
    begin
      if (branch_valid)
        begin
          case (PHT[update_index]) // 00,10 | 01,11
            2'b00:
              begin
                PHT[update_index] <= branch_taken ? 2'b10: 2'b00;
              end
            2'b10:
              begin
                PHT[update_index] <= branch_taken ? 2'b01: 2'b00;
              end
            2'b01:
              begin
                PHT[update_index] <= branch_taken ? 2'b11: 2'b10;
              end
            2'b11:
              begin
                PHT[update_index] <= branch_taken ? 2'b11: 2'b01;
              end
          endcase
        end
    end

endmodule
