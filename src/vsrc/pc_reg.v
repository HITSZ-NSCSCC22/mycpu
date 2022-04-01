`include "defines.v"
module pc_reg (
    input wire clk,
    input wire rst,
    input wire stall,

    input wire branch_flag_i,
    input wire[`RegBus] branch_target_address,

    input wire flush,
    input wire[`RegBus] new_pc,

    output reg[`InstAddrBus] pc,
    output reg ce
  );

  always @(posedge clk)
    begin
      if(ce == `ChipDisable)
        pc <= 32'h1c000000;
      else if(flush == 1'b1)
        pc <= new_pc;
      else if(stall == `Stop) // Hold output
        begin
          pc <= pc;
        end
      else
        begin
          if(branch_flag_i == `Branch)
            pc <= branch_target_address;
          else
            pc <= pc + 32'h4;
        end
    end

  always @(posedge clk)
    begin
      if(rst == `RstEnable)
        ce <= `ChipDisable;
      else
        ce <= `ChipEnable;
    end

endmodule
