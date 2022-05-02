`include "../../defines.v"
module if_id (
    input wire clk,
    input wire rst,

    input wire branch_flag_i,
    input wire[`InstAddrBus] if_pc_i,
    input wire[`InstAddrBus] if_inst_i,
    input wire if_inst_valid,
    input wire flush,
    input wire stall, // current stage stall, hold output
    output reg[`InstAddrBus] id_pc_o,
    output reg[`InstBus] id_inst_o,

    input wire excp_i,
    input wire [3:0] excp_num_i,
    output reg excp_o,
    output reg [3:0] excp_num_o
  );


  always @(posedge clk)
    begin
      if(rst == `RstEnable)
        begin
          id_pc_o <= `ZeroWord;
          id_inst_o <= `ZeroWord;
          excp_o <= 1'b0;
          excp_num_o <= 4'b0;
        end
      else if(flush == 1'b1)
        begin
          id_pc_o <= `ZeroWord;
          id_inst_o <= `ZeroWord;
          excp_o <= 1'b0;
          excp_num_o <= 4'b0;
        end
      else if(branch_flag_i || if_inst_valid == `InstInvalid)
        begin
          id_pc_o <= `ZeroWord;
          id_inst_o <= `ZeroWord;
          excp_o <= 1'b0;
          excp_num_o <= 4'b0;
        end
      else if(stall == `Stop)
        begin
          id_inst_o <= id_inst_o;
          id_pc_o <= id_pc_o;
          excp_o <= excp_i;
          excp_num_o <= excp_num_i;
        end
      else
        begin
          id_inst_o <= if_inst_i;
          id_pc_o <= if_pc_i;
          excp_o <= excp_i;
          excp_num_o <= excp_num_i;
        end
    end

endmodule
