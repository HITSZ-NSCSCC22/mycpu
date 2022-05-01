//to keep PC and inst_o corresponding
`include "defines.v"
module if_buffer (
    input wire clk,
    input wire rst,
    input wire [`InstAddrBus] pc_i,
    input wire flush,
    input wire [6:0]stall,
    input wire [31:0]inst_i,

    output reg [31:0]inst_o,
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
          inst_o<=0;
        end
      else if(branch_flag_i == `Branch)
        begin
          pc_o <= `ZeroWord;
          pc_valid <= `InstInvalid;
          inst_o<=0;
        end
      else if(flush == 1'b1)
        begin
          pc_o <= `ZeroWord;
          pc_valid <= `InstInvalid;
          inst_o<=0;
        end
      else if(stall[1] == `Stop&&stall[2]==`Stop) // Stall, hold output
        begin
          pc_o <= pc_o;
          pc_valid <= pc_valid;
          inst_o<=inst_o;
        end
      else if(stall[1]==`Stop&&stall[2]==0)
      begin
          pc_o <= 0;
          pc_valid <= 0;
          inst_o<=0;
      end
      else
        begin
          pc_o <= pc_i;
          pc_valid <= `InstValid;
          inst_o<=inst_i;
        end
    end

endmodule
