// Gshared predictor as base predictor
`include "../defines.v"
`include "branch_predictor/defines.v"
`include "branch_predictor/folder_func.v"


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

    output wire taken,
    output wire tag_hit
  );

  // Reset
  wire rst_n = ~rst;

  // PHT
  // - entry: {3bits bimodal, xbits tag}
  reg[`PHT_TAG_WIDTH+2:0] PHT[`PHT_DEPTH];


  // Fold GHT input to a fix length, the same as index range
  wire [`PHT_DEPTH_LOG2-1:0] hashed_ght_input;
  folder_func
    #(
      .INPUT_LENGTH   (GLOBAL_HISTORY_LENGTH),
      .OUTPUT_LENGTH  (`PHT_DEPTH_LOG2),
      .MAX_FOLD_ROUND (4)
    )
    ght_hash(
      .var_i (global_history_i[GLOBAL_HISTORY_LENGTH-1:0]),
      .var_o (hashed_ght_input)
    );

  // Tag
  // wire [`PHT_TAG_WIDTH-1:0] hashed_pc_tag = pc_i[2+`PHT_TAG_WIDTH-1:2];
  wire [`PHT_TAG_WIDTH-1:0] hashed_pc_tag;
  folder_func
    #(
      .INPUT_LENGTH   (`RegWidth),
      .OUTPUT_LENGTH  (`PHT_TAG_WIDTH),
      .MAX_FOLD_ROUND (3)
    )
    pc_hash(
      .var_i(pc_i),
      .var_o (hashed_pc_tag)
    );



  // hash with pc, and concatenate to `PHT_DEPTH_LOG2
  // the low 2bits of pc is usually 0, so use upper bits
  wire [`PHT_DEPTH_LOG2-1:0] query_hashed_index = {hashed_ght_input ^ pc_i[2+`PHT_DEPTH_LOG2-1:2]};

  // Query logic //////////////////////////////////
  wire [2:0] query_result_bimodal = PHT[query_hashed_index][`PHT_TAG_WIDTH+2:`PHT_TAG_WIDTH];
  wire [`PHT_TAG_WIDTH-1:0] query_result_tag = PHT[query_hashed_index][`PHT_TAG_WIDTH-1:0];

  assign taken = (query_result_bimodal[2] == 1'b1);
  assign tag_hit = (hashed_pc_tag == query_result_tag);
  // assign tag_hit = 1;



  // Update logic //////////////////////////////////

  // This buffer is used to store the hashed index for update
  reg[`PHT_DEPTH_LOG2-1:0] hashed_index_buffer [`FEEDBACK_LATENCY];
  reg[`PHT_TAG_WIDTH-1:0] tag_buffer [`FEEDBACK_LATENCY];
  always @(posedge clk)
    begin
      hashed_index_buffer[0] <= query_hashed_index;
      tag_buffer[0] <= hashed_pc_tag;
    end
  genvar index_id;
  generate
    for (index_id = 1; index_id < `FEEDBACK_LATENCY; index_id = index_id + 1)
      begin
        always @(posedge clk)
          begin
            hashed_index_buffer[index_id] <= hashed_index_buffer[index_id - 1];
            tag_buffer[index_id] <= tag_buffer[index_id - 1];
          end
      end
  endgenerate

  // Select index from buffer and update
  wire [`PHT_DEPTH_LOG2-1:0] update_index = hashed_index_buffer[`FEEDBACK_LATENCY-1];
  wire [`PHT_TAG_WIDTH-1:0] update_tag = tag_buffer[`FEEDBACK_LATENCY-1];
  always @(posedge clk or negedge rst_n)
    begin
      if (!rst_n)
        begin
          // Reset all PHT to 01
          for (integer i = 0; i < `PHT_DEPTH; i = i + 1)
            begin
              PHT[i] = {3'b100,{`PHT_TAG_WIDTH{1'b0}}};
            end
        end
      else
        begin
          if (branch_valid)
            begin
              // 000,001,010,011 | 100,101,110,111

              case(PHT[update_index][`PHT_TAG_WIDTH+2:`PHT_TAG_WIDTH])
                3'b000:
                  begin
                    PHT[update_index][`PHT_TAG_WIDTH+2:`PHT_TAG_WIDTH] <= branch_taken ? 3'b001 : 3'b000;
                  end
                3'b111:
                  begin
                    PHT[update_index][`PHT_TAG_WIDTH+2:`PHT_TAG_WIDTH] <= branch_taken ? 3'b111 : 3'b110;
                  end
                default:
                  begin
                    PHT[update_index][`PHT_TAG_WIDTH+2:`PHT_TAG_WIDTH] <= branch_taken ? PHT[update_index][`PHT_TAG_WIDTH+2:`PHT_TAG_WIDTH] +1 : PHT[update_index][`PHT_TAG_WIDTH+2:`PHT_TAG_WIDTH] -1;
                  end
              endcase

              if (PHT[update_index][`PHT_TAG_WIDTH-1:0] != update_tag) // Miss tag
                begin // Do swap
                  PHT[update_index][`PHT_TAG_WIDTH-1:0]<= {update_tag};
                end
            end
        end
    end

endmodule
