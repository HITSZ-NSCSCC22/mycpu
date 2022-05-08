`include "pipeline_defines.sv"

module mem_wb (
    input wire clk,
    input wire rst,
    input wire stall,

    input mem_wb_struct mem_signal_o,

    input wire mem_LLbit_we,
    input wire mem_LLbit_value,

    input wire flush,


    output wb_reg wb_reg_o,

    output csr_write_signal wb_csr_signal_o,

    output reg [`InstAddrBus] debug_commit_pc,
    output reg debug_commit_valid,
    output reg [`InstBus] debug_commit_instr,

    output reg wb_LLbit_we,
    output reg wb_LLbit_value,

    input wire excp_i,
    input wire [15:0] excp_num,

    //to csr
    output wire [31:0] csr_era,
    output wire [8:0] csr_esubcode,
    output wire [5:0] csr_ecode,
    output wire excp_flush,
    output wire ertn_flush,
    output wire va_error,
    output wire [31:0] bad_va,
    output wire excp_tlbrefill,
    output wire excp_tlb,
    output wire [18:0] excp_tlb_vppn
);

    reg wb_valid;

    assign csr_era = mem_signal_o.instr_info.pc;
    assign excp_flush = excp_i;
    assign ertn_flush = mem_signal_o.aluop == `EXE_ERTN_OP;


    assign csr_ecode = excp_num[0] ? `ECODE_INT : excp_num[1] ? `ECODE_ADEF : excp_num[2] ? `ECODE_TLBR : excp_num[3] ? `ECODE_PIF : 
                    excp_num[4] ? `ECODE_PPI : excp_num[5] ? `ECODE_SYS :excp_num[6] ? `ECODE_BRK : excp_num[7] ? `ECODE_INE :
                     excp_num[8] ? `ECODE_IPE :excp_num[9] ? `ECODE_ALE : excp_num[10] ? `ECODE_ADEM : excp_num[11] ? `ECODE_TLBR :
                     excp_num[12] ? `ECODE_PME :excp_num[13] ? `ECODE_PPI : excp_num[14] ? `ECODE_PIS :excp_num[15] ? `ECODE_PIL : 6'b0 ;

    assign va_error = excp_num[0] ? 1'b0 : excp_num[1] ? wb_valid : excp_num[2] ? wb_valid : excp_num[3] ? wb_valid : 
                    excp_num[4] ? wb_valid : excp_num[5] ? 1'b0 :excp_num[6] ? 1'b0 : excp_num[7] ? 1'b0 :
                    excp_num[8] ? 1'b0 :excp_num[9] ? wb_valid : excp_num[10] ? wb_valid : excp_num[11] ? wb_valid :
                    excp_num[12] ? wb_valid :excp_num[13] ? wb_valid : excp_num[14] ? wb_valid :excp_num[15] ? wb_valid : 1'b0 ;

    assign bad_va   = excp_num[0] ? 32'b0 : excp_num[1] ? mem_signal_o.instr_info.pc : excp_num[2] ? mem_signal_o.instr_info.pc : excp_num[3] ? mem_signal_o.instr_info.pc : 
                    excp_num[4] ? mem_signal_o.instr_info.pc : excp_num[5] ? 32'b0 :excp_num[6] ? 32'b0 : excp_num[7] ? 32'b0 :
                    excp_num[8] ? 32'b0 :excp_num[9] ? wb_reg_o.wdata : excp_num[10] ? wb_reg_o.wdata : excp_num[11] ? wb_reg_o.wdata :
                    excp_num[12] ? wb_reg_o.wdata :excp_num[13] ? wb_reg_o.wdata : excp_num[14] ? wb_reg_o.wdata :excp_num[15] ? wb_reg_o.wdata : 32'b0 ;

    assign csr_esubcode = excp_num[0] ? 9'b0 : excp_num[1] ? `ESUBCODE_ADEF : excp_num[2] ? 9'b0 : excp_num[3] ? 9'b0 : 
                    excp_num[4] ? 9'b0 : excp_num[5] ? 9'b0 :excp_num[6] ? 9'b0 : excp_num[7] ? 9'b0 :
                    excp_num[8] ? 9'b0 :excp_num[9] ? 9'b0 : excp_num[10] ? `ESUBCODE_ADEM : excp_num[11] ? 9'b0 :
                    excp_num[12] ? 9'b0 :excp_num[13] ? 9'b0 : excp_num[14] ? 9'b0 :excp_num[15] ? 9'b0 : 9'b0 ;

    assign excp_tlbrefill = excp_num[0] ? 1'b0 : excp_num[1] ? 1'b0 : excp_num[2] ? wb_valid : excp_num[3] ? 1'b0 : 
                    excp_num[4] ? 1'b0 : excp_num[5] ? 1'b0 :excp_num[6] ? 1'b0 : excp_num[7] ? 1'b0 :
                    excp_num[8] ? 1'b0 :excp_num[9] ? 1'b0 : excp_num[10] ? 1'b0 : excp_num[11] ? wb_valid :
                    excp_num[12] ? 1'b0 :excp_num[13] ? 1'b0 : excp_num[14] ? 1'b0 :excp_num[15] ? 1'b0 : 1'b0 ;

    assign excp_tlb = excp_num[0] ? 1'b0 : excp_num[1] ? 1'b0 : excp_num[2] ? wb_valid : excp_num[3] ? wb_valid : 
                    excp_num[4] ? wb_valid : excp_num[5] ? 1'b0 :excp_num[6] ? 1'b0 : excp_num[7] ? 1'b0 :
                    excp_num[8] ? 1'b0 :excp_num[9] ? 1'b0 : excp_num[10] ? 1'b0 : excp_num[11] ? wb_valid :
                    excp_num[12] ? wb_valid :excp_num[13] ? wb_valid : excp_num[14] ? wb_valid :excp_num[15] ? wb_valid : 1'b0 ;

    assign excp_tlb_vppn = excp_num[0] ? 19'b0 : excp_num[1] ? 19'b0 : excp_num[2] ? mem_signal_o.instr_info.pc[31:13] : excp_num[3] ? mem_signal_o.instr_info.pc[31:13] : 
                   excp_num[4] ? mem_signal_o.instr_info.pc[31:13] : excp_num[5] ? 19'b0 :excp_num[6] ? 19'b0 : excp_num[7] ? 19'b0 :
                    excp_num[8] ? 19'b0 :excp_num[9] ? 19'b0 : excp_num[10] ? 19'b0 : excp_num[11] ? wb_reg_o.wdata[31:13] :
                    excp_num[12] ? wb_reg_o.wdata[31:13] :excp_num[13] ? wb_reg_o.wdata[31:13] : excp_num[14] ? wb_reg_o.wdata[31:13] :excp_num[15] ? wb_reg_o.wdata[31:13] : 19'b0 ;


    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            wb_reg_o.waddr    <= `NOPRegAddr;
            wb_reg_o.we  <= `WriteDisable;
            wb_reg_o.wdata <= `ZeroWord;
            wb_reg_o.pc <= `ZeroWord;
            wb_valid <= 1'b0;
            wb_LLbit_we <= 1'b0;
            wb_LLbit_value <= 1'b0;
            wb_csr_signal_o <= 47'b0;
            debug_commit_instr <= `ZeroWord;
            debug_commit_pc <= `ZeroWord;
            debug_commit_valid <= `InstInvalid;
        end else if (flush == 1'b1 || excp_i == 1'b1 || mem_signal_o.aluop == `EXE_ERTN_OP) begin
            wb_reg_o.waddr    <= `NOPRegAddr;
            wb_reg_o.we  <= `WriteDisable;
            wb_reg_o.wdata <= `ZeroWord;
            wb_reg_o.pc <= `ZeroWord;
            wb_valid <= 1'b0;
            wb_LLbit_we <= 1'b0;
            wb_LLbit_value <= 1'b0;
            wb_csr_signal_o <= 47'b0;
            debug_commit_instr <= `ZeroWord;
            debug_commit_pc <= `ZeroWord;
            debug_commit_valid <= `InstInvalid;
        end else if (stall == `Stop) begin
            debug_commit_pc <= `ZeroWord;
            debug_commit_instr <= `ZeroWord;
            debug_commit_valid <= `InstInvalid;
        end else begin
            wb_reg_o.waddr    <= mem_signal_o.waddr;
            wb_reg_o.we  <= mem_signal_o.wreg;
            wb_reg_o.wdata <= mem_signal_o.wdata;
            wb_reg_o.pc <= mem_signal_o.instr_info.pc;
            wb_valid <= 1'b1;
            wb_LLbit_we <= mem_LLbit_we;
            wb_LLbit_value <= mem_LLbit_value;
            wb_csr_signal_o <= mem_signal_o.csr_signal;
            debug_commit_pc <= mem_signal_o.instr_info.pc;
            debug_commit_valid <= mem_signal_o.instr_info.valid;
            debug_commit_instr <= mem_signal_o.instr_info.instr;
        end
    end


endmodule
