//to keep PC and inst_o corresponding
`include "defines.v"
module if_buffer (
    input wire clk,
    input wire rst,
    input wire [`InstAddrBus] pc_i,
    input wire flush,

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
      else
        begin
          pc_o <= pc_i;
          pc_valid <= `InstValid;
        end
    end

endmodule
