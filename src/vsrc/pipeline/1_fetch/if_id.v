`include "../../defines.v"
module if_id (
    input wire clk,
    input wire rst,

    input wire branch_flag_i,
    input wire[`InstAddrBus] if_pc_i,
    input wire[`InstAddrBus] if_inst_i,
    input wire if_inst_valid,
    input wire flush,
    output reg[`InstAddrBus] id_pc_o,
    output reg[`InstBus] id_inst_o
  );


  always @(posedge clk)
    begin
      if(rst == `RstEnable)
        begin
          id_pc_o <= `ZeroWord;
          id_inst_o <= `ZeroWord;
        end
      else if(flush == 1'b1)
        begin
          id_pc_o <= `ZeroWord;
          id_inst_o <= `ZeroWord;
        end
      else if(branch_flag_i || if_inst_valid == `InstInvalid)
        begin
          id_pc_o <= `ZeroWord;
          id_inst_o <= `ZeroWord;
        end
      else
        begin
          id_inst_o <= if_inst_i;
          id_pc_o <= if_pc_i;
        end
    end

endmodule
