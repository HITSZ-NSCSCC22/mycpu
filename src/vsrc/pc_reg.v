`include "defines.v"
module pc_reg (
    input wire clk,
    input wire rst,
    input wire stall1,
    input wire stall2,

    input wire branch_flag_i_1,
    input wire[`RegBus] branch_target_address_1,

    input wire branch_flag_i_2,
    input wire[`RegBus] branch_target_address_2,

    input wire flush,
    input wire[`RegBus] new_pc,

    output reg[`InstAddrBus] pc_1,
    output reg[`InstAddrBus] pc_2,
    output reg ce
  );

  always @(posedge clk)
    begin
      if(ce == `ChipDisable)
        pc_1 <= 32'h1c000000;
      else if(flush == 1'b1)
        pc_1 <= new_pc;
      else if(stall1 == `Stop) // Hold output
        begin
          pc_1 <= pc_1;
        end
      else
        begin
          if(branch_flag_i_1 == `Branch)
            pc_1 <= branch_target_address_1;
          else if(branch_flag_i_2 == `Branch)
            pc_1 <= branch_target_address_2;
          else
            pc_1 <= pc_1 + 32'h8;
        end
    end

    always @(posedge clk)
    begin
      if(ce == `ChipDisable)
        pc_2 <= 32'h1c000004;
      else if(flush == 1'b1)
        pc_2 <= new_pc + 4'h4;
      else if(stall2 == `Stop) // Hold output
        begin
          pc_2 <= pc_2;
        end
      else
        begin
          if(branch_flag_i_1 == `Branch)
            pc_2 <= branch_target_address_1 + 4'h4;
          if(branch_flag_i_2 == `Branch)
            pc_2 <= branch_target_address_2 + 4'h4;
          else
            pc_2 <= pc_2 + 32'h8;
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
