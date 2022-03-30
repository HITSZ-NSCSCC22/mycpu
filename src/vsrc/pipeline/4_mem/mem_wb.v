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

    input wire mem_LLbit_we,
    input wire mem_LLbit_value,

    input wire flush,

    output reg[`RegAddrBus] wb_wd,
    output reg wb_wreg,
    output reg[`RegBus] wb_wdata,

    output reg[`InstAddrBus] debug_commit_pc,
    output reg debug_commit_valid,
    output reg[`InstBus] debug_commit_instr,

    output reg wb_LLbit_we,
    output reg wb_LLbit_value
  );

  reg debug_commit_valid_0;
  reg debug_commit_valid_1;
  reg [`InstBus] debug_commit_pc_0;

  always @ (posedge clk)
    begin
      if (rst == `RstEnable)
        begin
          wb_wd    <= `NOPRegAddr;
          wb_wreg  <= `WriteDisable;
          wb_wdata <= `ZeroWord;
          wb_LLbit_we <= 1'b0;
          wb_LLbit_value <= 1'b0;
          debug_commit_instr <= `ZeroWord;
          debug_commit_pc <= `ZeroWord;
          debug_commit_valid <= `InstInvalid;
        end
      else if(flush == 1'b1)
        begin
          wb_wd    <= `NOPRegAddr;
          wb_wreg  <= `WriteDisable;
          wb_wdata <= `ZeroWord;
          wb_LLbit_we <= 1'b0;
          wb_LLbit_value <= 1'b0;
          debug_commit_instr <= `ZeroWord;
          debug_commit_pc <= `ZeroWord;
          debug_commit_valid <= `InstInvalid;
        end
      else 
        begin
          wb_wd    <= mem_wd;
          wb_wreg  <= mem_wreg;
          wb_wdata <= mem_wdata;
          wb_LLbit_we <= mem_LLbit_we;
          wb_LLbit_value <= mem_LLbit_value;
          debug_commit_pc <= mem_inst_pc;
          // debug_commit_pc <= debug_commit_pc_0;
          debug_commit_valid <= ~mem_inst_valid;
          // debug_commit_valid_1 <= debug_commit_valid_0;
          // debug_commit_valid <= ~debug_commit_valid_1;
          debug_commit_instr <= mem_instr;
        end
    end

endmodule
