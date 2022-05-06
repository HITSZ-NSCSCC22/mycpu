`include "defines.sv"
`include "csr_defines.sv"

module ex_mem (
    input logic clk,
    input logic rst,
    input logic stall,
    input logic excp_flush,
    input logic ertn_flush,

    input logic [`RegAddrBus] ex_wd,
    input logic ex_wreg,
    input logic [`RegBus] ex_wdata,
    input logic ex_inst_valid,
    input logic [`InstAddrBus] ex_inst_pc,
    input logic [`AluOpBus] ex_aluop,
    input logic [`RegBus] ex_mem_addr,
    input logic [`RegBus] ex_reg2,
    input logic flush,
    input logic [1:0] ex_excepttype,
    input logic [`RegBus] ex_current_inst_address,
    input csr_write_signal ex_csr_signal_o,
    input logic excp_i,
    input logic [9:0] excp_num_i,

    output reg [`RegAddrBus] mem_wd,
    output reg mem_wreg,
    output reg [`RegBus] mem_wdata,
    output reg mem_inst_valid,
    output reg [`InstAddrBus] mem_inst_pc,
    output reg [`AluOpBus] mem_aluop,
    output reg [`RegBus] mem_mem_addr,
    output reg [`RegBus] mem_reg2,
    output reg [1:0] mem_excepttype,
    output reg [`RegBus] mem_current_inst_address,
    output csr_write_signal mem_csr_signal_i,
    output reg excp_o,
    output reg [9:0] excp_num_o
);

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
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
            mem_csr_signal_i <= 47'b0;
            excp_o <= 1'b0;
            excp_num_o <= 10'b0;
        end else if (flush == 1'b1 || excp_flush == 1'b1 || ertn_flush == 1'b1) begin
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
            mem_csr_signal_i <= 47'b0;
            excp_o <= 1'b0;
            excp_num_o <= 10'b0;
        end else
        if (stall == `Stop) begin
        end else begin
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
            mem_csr_signal_i <= ex_csr_signal_o;
            excp_o <= excp_i;
            excp_num_o <= excp_num_i;
        end
    end

endmodule
