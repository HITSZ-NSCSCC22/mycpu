`include "../../defines.v"

module ex_mem (
    input wire clk,
    input wire rst,
    input wire[5:0] stall,

    input wire[`RegAddrBus] ex_wd,
    input wire ex_wreg,
    input wire[`RegBus] ex_wdata,
    input wire ex_inst_valid,
    input wire[`InstAddrBus] ex_inst_pc,
    input wire[`AluOpBus] ex_aluop,
    input wire[`RegBus] ex_mem_addr,
    input wire[`RegBus] ex_reg2,
    input wire flush,
    input wire[1:0] ex_excepttype,
    input wire[`RegBus] ex_current_inst_address,

    output reg[`RegAddrBus] mem_wd,
    output reg mem_wreg,
    output reg[`RegBus] mem_wdata,
    output reg mem_inst_valid,
    output reg[`InstAddrBus] mem_inst_pc,
    output reg[`AluOpBus] mem_aluop,
    output reg[`RegBus] mem_mem_addr,
    output reg[`RegBus] mem_reg2,
    output reg[1:0] mem_excepttype,
    output reg[`RegBus] mem_current_inst_address
);

always @ (posedge clk)begin
    if (rst == `RstEnable)begin
        mem_wd    <= `NOPRegAddr;
        mem_wreg  <= `WriteDisable;
        mem_wdata <= `ZeroWord;
        mem_inst_pc <= `ZeroWord;
        mem_inst_valid <= `InstInvalid;
        mem_aluop <= `EXE_NOP_OP;
        mem_mem_addr <= `ZeroWord;
        mem_reg2 <= `ZeroWord;
        mem_excepttype <= 2'b00;
        mem_current_inst_address <= `ZeroWord;
    end else if(flush == 1'b1)begin
        mem_wd    <= `NOPRegAddr;
        mem_wreg  <= `WriteDisable;
        mem_wdata <= `ZeroWord;
        mem_inst_pc <= `ZeroWord;
        mem_inst_valid <= `InstInvalid;
        mem_aluop <= `EXE_NOP_OP;
        mem_mem_addr <= `ZeroWord;
        mem_reg2 <= `ZeroWord;
        mem_excepttype <= 2'b00;
        mem_current_inst_address <= `ZeroWord;
    end else if(stall[4] == `Stop &&stall[5] == `NoStop)begin
        mem_wd    <= `NOPRegAddr;
        mem_wreg  <= `WriteDisable;
        mem_wdata <= `ZeroWord;
        mem_inst_pc <= `ZeroWord;
        mem_inst_valid <= `InstInvalid;
        mem_aluop <= `EXE_NOP_OP;
        mem_mem_addr <= `ZeroWord;
        mem_reg2 <= `ZeroWord;
        mem_excepttype <= 2'b00;
        mem_current_inst_address <= `ZeroWord;
    end else if(stall[4] == `NoStop) begin
        mem_wd    <= ex_wd;
        mem_wreg  <= ex_wreg;
        mem_wdata <= ex_wdata;
        mem_inst_pc <= ex_inst_pc;
        mem_inst_valid <= ex_inst_valid;
        mem_aluop <= ex_aluop;
        mem_mem_addr <= ex_mem_addr;
        mem_reg2 <= ex_reg2;
        mem_excepttype <= ex_excepttype;
        mem_current_inst_address <= ex_current_inst_address;
    end
end
    
endmodule