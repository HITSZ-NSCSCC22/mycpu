`include "defines.v"
module pc_reg (
    input wire clk,
    input wire rst,

    input wire branch_flag_i,
    input wire[`RegBus] branch_target_address,

    output reg[`InstAddrBus] pc,
    output reg ce
  );

  always @(posedge clk)
    begin
      if(ce == `ChipDisable)
        pc <= 32'h1c000000;
      else if(branch_flag_i == `Branch)
        pc <= branch_target_address;
      else
        pc <= pc + 32'h4;
    end

  always @(posedge clk)
    begin
      if(rst == `RstEnable)
        ce <= `ChipDisable;
      else
        ce <= `ChipEnable;
    end

endmodule
