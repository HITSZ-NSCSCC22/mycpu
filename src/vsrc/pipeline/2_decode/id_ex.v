`include "../../defines.v"
module id_ex (
    input wire clk,
    input wire rst,
    input wire [6:0]stall,

    input wire[`AluOpBus] id_aluop,
    input wire[`AluSelBus] id_alusel,
    input wire[`RegBus] id_reg1,
    input wire[`RegBus] id_reg2,
    input wire[`RegAddrBus] id_wd,
    input wire id_wreg,
    input wire id_inst_valid,
    input wire[`InstAddrBus] id_inst_pc,
    input wire[`RegBus] id_link_address,
    input wire[`RegBus] id_inst,
    input wire flush,
    input wire[1:0] id_excepttype,
    input wire[`RegBus] id_current_inst_address,

    output reg[`AluOpBus] ex_aluop,
    output reg[`AluSelBus] ex_alusel,
    output reg[`RegBus] ex_reg1,
    output reg[`RegBus] ex_reg2,
    output reg[`RegAddrBus] ex_wd,
    output reg ex_wreg,
    output reg ex_inst_valid,
    output reg[`InstAddrBus] ex_inst_pc,
    output reg[`RegBus] ex_link_address,
    output reg[`RegBus] ex_inst,
    output reg[1:0]ex_excepttype,
    output reg[`RegBus] ex_current_inst_address
  );

  always @(posedge clk)
    begin
      if(rst == `RstEnable)
        begin
          ex_aluop  <= `EXE_NOP_OP;
          ex_alusel <= `EXE_RES_NOP;
          ex_reg1   <= `ZeroWord;
          ex_reg2   <= `ZeroWord;
          ex_wd     <= `NOPRegAddr;
          ex_wreg   <= `WriteDisable;
          ex_inst_pc <= `ZeroWord;
          ex_inst_valid <= `InstInvalid;
          ex_link_address <= `ZeroWord;
          ex_inst <= `ZeroWord;
          ex_excepttype <= 2'b00;
          ex_current_inst_address <= `ZeroWord;
        end
      else if(flush == 1'b1)
        begin
          ex_aluop  <= `EXE_NOP_OP;
          ex_alusel <= `EXE_RES_NOP;
          ex_reg1   <= `ZeroWord;
          ex_reg2   <= `ZeroWord;
          ex_wd     <= `NOPRegAddr;
          ex_wreg   <= `WriteDisable;
          ex_inst_pc <= `ZeroWord;
          ex_inst_valid <= `InstInvalid;
          ex_link_address <= `ZeroWord;
          ex_inst <= `ZeroWord;
          ex_excepttype <= 2'b00;
          ex_current_inst_address <= `ZeroWord;
        end
      else if(stall[3] == `Stop&&stall[4]==0)
        begin
          ex_aluop  <= `EXE_NOP_OP;
          ex_alusel <= `EXE_RES_NOP;
          ex_reg1   <= `ZeroWord;
          ex_reg2   <= `ZeroWord;
          ex_wd     <= `NOPRegAddr;
          ex_wreg   <= `WriteDisable;
          ex_inst_pc <= `ZeroWord;
          ex_inst_valid <= `InstInvalid;
          ex_link_address <= `ZeroWord;
          ex_inst <= `ZeroWord;
          ex_excepttype <= 2'b00;
          ex_current_inst_address <= `ZeroWord;
        end
      else if(stall[3]==`Stop)
      begin
          ex_aluop  <= ex_aluop;
          ex_alusel <= ex_alusel;
          ex_reg1   <= ex_reg1;
          ex_reg2   <= ex_reg2;
          ex_wd     <= ex_wd;
          ex_wreg   <= ex_wreg;
          ex_inst_pc <= ex_inst_pc;
          ex_inst_valid <= ex_inst_valid;
          ex_link_address <= ex_link_address;
          ex_inst <= ex_inst;
          ex_excepttype <= ex_excepttype;
          ex_current_inst_address <= ex_current_inst_address;
      end
      else
        begin
          ex_aluop  <= id_aluop;
          ex_alusel <= id_alusel;
          ex_reg1   <= id_reg1;
          ex_reg2   <= id_reg2;
          ex_wd     <= id_wd;
          ex_wreg   <= id_wreg;
          ex_inst_pc <= id_inst_pc;
          ex_inst_valid <= id_inst_valid;
          ex_link_address <= id_link_address;
          ex_inst <= id_inst;
          ex_excepttype <= id_excepttype;
          ex_current_inst_address <= id_current_inst_address;
        end
    end

endmodule
