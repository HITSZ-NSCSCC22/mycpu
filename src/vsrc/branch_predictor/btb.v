// Branch Target Buffer
`include "branch_predictor/defines.v"
`include "../defines.v"


module btb (
    input wire clk,
    input wire rst,
    input wire [`RegBus] query_pc_i,

    // Update signals
    input wire update_valid,
    input wire [`RegBus] update_pc_i,
    input wire [`RegBus] update_branch_target_i,

    output wire [`RegBus] branch_target_address_o,
    output wire btb_hit
  );


  /** A entry in BTB looks like this:
    [tag[`BTB_TAG_LENGTH], target[30]]
    - target: target[31:2], lower 2bit is usually 0
  */
  reg [`BTB_ENTRY_BUS] btb_entries[`BTB_DEPTH];


  // Query logic ////////////////////////////////////

  // pc_i[2+2x`BTB_DEPTH_LOG2:2] is first hashed into `BTB_DEPTH_LOG2 as an index
  // use a 2-stage XOR for now
  wire[`BTB_DEPTH_LOG2-1:0] query_hashed_index = (query_pc_i[`BTB_DEPTH_LOG2+1:2] ^ query_pc_i[`BTB_DEPTH_LOG2+`BTB_DEPTH_LOG2+1:`BTB_DEPTH_LOG2+2]) ^ query_pc_i[`BTB_DEPTH_LOG2+1:2];

  // Extract the entry
  wire[`BTB_ENTRY_BUS] btb_entry = btb_entries[query_hashed_index];

  // Mark hit flag, use the lower bits of query_pc_i as tag
  assign btb_hit = (btb_entry[`BTB_ENTRY_LENGTH-1:`BTB_ENTRY_LENGTH-`BTB_TAG_LENGTH] == query_pc_i[`BTB_TAG_LENGTH+1:2]);

  // Output branch_target_address_o if btb_hit
  assign branch_target_address_o = btb_hit ? {btb_entry[`BTB_ENTRY_LENGTH-`BTB_TAG_LENGTH-1:0],2'b0} : 32'b0;


  // Update logic /////////////////////////////////

  // Also hashed in the same way as query_hashed_index
  wire[`BTB_DEPTH_LOG2-1:0] update_hashed_index = (update_pc_i[`BTB_DEPTH_LOG2+1:2] ^ update_pc_i[`BTB_DEPTH_LOG2+`BTB_DEPTH_LOG2+1:`BTB_DEPTH_LOG2+2]) ^ update_pc_i[`BTB_DEPTH_LOG2+1:2];

  // update each cycle
  always @(posedge clk)
    begin
      if (update_valid)
        begin
          btb_entries[update_hashed_index] <= {btb_entry[`BTB_ENTRY_LENGTH-1:`BTB_ENTRY_LENGTH-`BTB_TAG_LENGTH],update_branch_target_i[`RegWidth-1:2]};
        end
    end

endmodule
