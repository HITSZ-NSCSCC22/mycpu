//to keep PC and inst_o corresponding
`include "defines.v"
module if_buffer (
    input wire clk,
    input wire rst,
    input wire [`InstAddrBus] pc_i,
    input wire flush,
    input wire[6:0] stall,

    input wire branch_flag_i,
    output reg [`InstAddrBus] pc_o,
    output reg pc_valid
  );

  always @(posedge clk)
    begin
      if(rst)
        begin
          pc_o <= `ZeroWord;
          pc_valid <= `InstInvalid;
        end
      else if(branch_flag_i == `Branch)
        begin
          pc_o <= `ZeroWord;
          pc_valid <= `InstInvalid;
        end
      else if(flush == 1'b1)
        begin
          pc_o <= `ZeroWord;
          pc_valid <= `InstInvalid;
        end
      else if(stall[1] == `Stop && stall[2] == `NoStop)
        begin
          pc_o <= `ZeroWord;
          pc_valid <= `InstInvalid;
        end
      else if(stall[1] == `NoStop)
        begin
          pc_o <= pc_i;
          pc_valid <= `InstValid;
        end
    end

endmodule
