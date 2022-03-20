`include "../../defines.v"

module mem_wb (
    input wire clk,
    input wire rst,

    input wire[`RegAddrBus] mem_wd,
    input wire mem_wreg,
    input wire[`RegBus] mem_wdata,
    input wire[`InstAddrBus] mem_inst_pc,
    input wire[`InstBus] mem_instr,
    input wire mem_inst_valid,

    output reg[`RegAddrBus] wb_wd,
    output reg wb_wreg,
    output reg[`RegBus] wb_wdata,

    output reg[`InstAddrBus] debug_commit_pc,
    output reg debug_commit_valid,
    output reg[`InstBus] debug_commit_instr
);

reg debug_commit_valid_0;
reg debug_commit_valid_1;

always @ (posedge clk)begin
    if (rst == `RstEnable)begin
        wb_wd    <= `NOPRegAddr;
        wb_wreg  <= `WriteDisable;
        wb_wdata <= `ZeroWord;
        debug_commit_instr <= `ZeroWord;
        debug_commit_pc <= `ZeroWord;
        debug_commit_valid <= `InstInvalid;
    end else begin
        wb_wd    <= mem_wd;
        wb_wreg  <= mem_wreg;
        wb_wdata <= mem_wdata;
        debug_commit_pc <= mem_inst_pc;
        debug_commit_valid_0 <= mem_inst_valid;
        debug_commit_valid_1 <= debug_commit_valid_0;
        debug_commit_valid <= debug_commit_valid_1;
        debug_commit_instr <= mem_instr;
    end
end
    
endmodule