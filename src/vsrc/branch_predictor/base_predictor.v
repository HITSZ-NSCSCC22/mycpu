// Base Predictor is a pure PC-indexed bimodal table

module base_predictor #(
    parameter TABLE_DEPTH_EXP2 = 10,
    parameter CTR_WIDTH = 2,
    parameter PC_WIDTH = 32
  ) (
    input wire clk,
    input wire rst,
    input wire [PC_WIDTH-1:0] pc_i,

    // Update signals
    input wire update_valid,
    input wire[PC_WIDTH:0] update_instr_info,
    // update_instr_info
    // [pc, taken]

    // Query output signals
    output wire taken
  );

  // Table
  reg[CTR_WIDTH-1:0] PHT[2**TABLE_DEPTH_EXP2];

  // Reset signal
  wire rst_n = ~rst;

  // Reset
  always @(negedge rst_n)
    begin
      if (!rst_n)
        begin
          for (integer i= 0; i< 2**TABLE_DEPTH_EXP2; i = i + 1)
            begin
              PHT[i] = {1'b1, {CTR_WIDTH-1{1'b0}}};
            end
        end
    end

  // Query logic
  wire[TABLE_DEPTH_EXP2-1:0] query_index = pc_i[2+TABLE_DEPTH_EXP2-1:2];
  wire[CTR_WIDTH-1:0] query_entry = PHT[query_index];

  assign taken = (query_entry[CTR_WIDTH-1] == 1'b1);

  // Update logic
  wire[PC_WIDTH-1:0] update_pc = update_instr_info[PC_WIDTH:1];
  wire[TABLE_DEPTH_EXP2-1:0] update_index = update_pc[TABLE_DEPTH_EXP2+1:2];
  wire update_taken = update_instr_info[0];
  always @(posedge clk)
    begin
      if (update_valid)
        begin
          if (PHT[update_index] == {CTR_WIDTH{1'b1}})
            begin
              PHT[update_index] <= update_taken? PHT[update_index] : PHT[update_index]-1;
            end
          else if(PHT[update_index] == {CTR_WIDTH{1'b0}})
            begin
              PHT[update_index] <= update_taken? PHT[update_index] +1: PHT[update_index];
            end
          else
            begin
              PHT[update_index] <= update_taken? PHT[update_index] +1: PHT[update_index]-1;
            end
        end
    end
endmodule
