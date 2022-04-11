`include "../../defines.v"
module id_ex (
    input wire clk,
    input wire rst,
    input wire stall,

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
    output reg[`RegBus] ex_current_inst_address,

    input wire[`RegAddrBus] reg1_addr_i,
    input wire[`RegAddrBus] reg2_addr_i,  
    input wire[`InstAddrBus] pc_i_other,
    input wire[`RegAddrBus] reg1_addr_i_other,
    input wire[`RegAddrBus] reg2_addr_i_other,
    input wire[`RegAddrBus] waddr_i_other,

    input stallreq_from_id,
    output reg stallreq
  );
  
  wire stallreq1;
  wire stallreq2;
  wire stallreq3;
  wire stallreq4;
  wire stallreq5;
  wire stallreq6;
  wire stallreq7;

  assign sallreq1 = id_inst_pc == pc_i_other + 4;
  assign sallreq3 = (reg1_addr_i == reg1_addr_i_other) && reg1_addr_i != 0;
  assign sallreq4 = (reg2_addr_i == reg2_addr_i_other) && reg2_addr_i != 0;
  assign sallreq5 = reg1_addr_i == waddr_i_other;
  assign sallreq6 = reg2_addr_i == waddr_i_other;
  assign sallreq7 = stallreq3 | stallreq4 | stallreq5 | stallreq6;
  
  //always @(*) begin
    //stallreq = stallreq_from_id | stallreq1 | stallreq7;
  //end

  always @(*) begin
    stallreq = stallreq_from_id | ((id_inst_pc == pc_i_other + 4) && (((reg1_addr_i == reg1_addr_i_other) && reg1_addr_i != 0 ) | ((reg2_addr_i == reg2_addr_i_other) && reg2_addr_i != 0)
               | (reg1_addr_i == waddr_i_other) | (reg2_addr_i == waddr_i_other)));
  end


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
      else if(stall == `Stop || stallreq == `Stop)
        begin

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
