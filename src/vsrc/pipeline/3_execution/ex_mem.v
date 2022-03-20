`include "../../defines.v"

module ex_mem (
    input wire clk,
    input wire rst,

    input wire[`RegAddrBus] ex_wd,
    input wire ex_wreg,
    input wire[`RegBus] ex_wdata,
    input wire ex_inst_valid,
    input wire[`InstBus] ex_inst,
    input wire[`InstAddrBus] ex_inst_pc,

    output reg[`RegAddrBus] mem_wd,
    output reg mem_wreg,
    output reg[`RegBus] mem_wdata,
    output reg mem_inst_valid,
    output reg[`InstBus] mem_inst,
    output reg[`InstAddrBus] mem_inst_pc
);

always @ (posedge clk)begin
    if (rst == `RstEnable)begin
        mem_wd    <= `NOPRegAddr;
        mem_wreg  <= `WriteDisable;
        mem_wdata <= `ZeroWord;
        mem_inst <= `ZeroWord;
        mem_inst_pc <= `ZeroWord;
        mem_inst_valid <= `InstInvalid;
    end else begin
        mem_wd    <= ex_wd;
        mem_wreg  <= ex_wreg;
        mem_wdata <= ex_wdata;
        mem_inst <= ex_inst;
        mem_inst_pc <= ex_inst_pc;
        mem_inst_valid <= ex_inst_valid;
    end
end
    
endmodule