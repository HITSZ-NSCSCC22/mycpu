`include "defines.v"
module id_ex (
    input wire clk,
    input wire rst,
    input wire stall,
    input wire excp_flush,
    input wire ertn_flush,

    input wire [`AluOpBus] id_aluop,
    input wire [`AluSelBus] id_alusel,
    input wire [`RegBus] id_reg1,
    input wire [`RegBus] id_reg2,
    input wire [`RegAddrBus] id_wd,
    input wire id_wreg,
    input wire id_inst_valid,
    input wire [`InstAddrBus] id_inst_pc,
    input wire [`RegBus] id_link_address,
    input wire [`RegBus] id_inst,
    input wire flush,
    input wire [1:0] id_excepttype,
    input wire [`RegBus] id_current_inst_address,
    input wire id_csr_we,
    input wire [13:0] id_csr_addr,
    input wire [`RegBus] id_csr_data,

    output reg [`AluOpBus] ex_aluop,
    output reg [`AluSelBus] ex_alusel,
    output reg [`RegBus] ex_reg1,
    output reg [`RegBus] ex_reg2,
    output reg [`RegAddrBus] ex_wd,
    output reg ex_wreg,
    output reg ex_inst_valid,
    output reg [`InstAddrBus] ex_inst_pc,
    output reg [`RegBus] ex_link_address,
    output reg [`RegBus] ex_inst,
    output reg [1:0] ex_excepttype,
    output reg [`RegBus] ex_current_inst_address,
    output reg ex_csr_we,
    output reg [13:0] ex_csr_addr,
    output reg [`RegBus] ex_csr_data,

    input wire [ `RegAddrBus] reg1_addr_i,
    input wire [ `RegAddrBus] reg2_addr_i,
    input wire [`InstAddrBus] pc_i_other,
    input wire [ `RegAddrBus] reg1_addr_i_other,
    input wire [ `RegAddrBus] reg2_addr_i_other,
    input wire [ `RegAddrBus] waddr_i_other,

    input stallreq_from_id,
    output reg stallreq,

    input wire excp_i,
    input wire [8:0] excp_num_i,
    output reg excp_o,
    output reg [8:0] excp_num_o
);


    //always @(*) begin
    //stallreq = stallreq_from_id | stallreq1 | stallreq7;
    //end

    always @(*) begin
        stallreq = stallreq_from_id | ((id_inst_pc == pc_i_other + 4) && ( (reg1_addr_i == waddr_i_other) | (reg2_addr_i == waddr_i_other)));
    end


    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            ex_aluop                <= `EXE_NOP_OP;
            ex_alusel               <= `EXE_RES_NOP;
            ex_reg1                 <= `ZeroWord;
            ex_reg2                 <= `ZeroWord;
            ex_wd                   <= `NOPRegAddr;
            ex_wreg                 <= `WriteDisable;
            ex_inst_pc              <= `ZeroWord;
            ex_inst_valid           <= `InstInvalid;
            ex_link_address         <= `ZeroWord;
            ex_inst                 <= `ZeroWord;
            ex_excepttype           <= 2'b00;
            ex_current_inst_address <= `ZeroWord;
            ex_csr_we               <= 1'b0;
            ex_csr_addr             <= 14'b0;
            ex_csr_data             <= `ZeroWord;
            excp_o                  <= 1'b0;
            excp_num_o              <= 9'b0;
        end else if (flush == 1'b1 || excp_flush == 1'b1 || ertn_flush == 1'b1) begin
            ex_aluop                <= `EXE_NOP_OP;
            ex_alusel               <= `EXE_RES_NOP;
            ex_reg1                 <= `ZeroWord;
            ex_reg2                 <= `ZeroWord;
            ex_wd                   <= `NOPRegAddr;
            ex_wreg                 <= `WriteDisable;
            ex_inst_pc              <= `ZeroWord;
            ex_inst_valid           <= `InstInvalid;
            ex_link_address         <= `ZeroWord;
            ex_inst                 <= `ZeroWord;
            ex_excepttype           <= 2'b00;
            ex_current_inst_address <= `ZeroWord;
            ex_csr_we               <= 1'b0;
            ex_csr_addr             <= 14'b0;
            ex_csr_data             <= `ZeroWord;
            excp_o                  <= 1'b0;
            excp_num_o              <= 9'b0;
        end else
        if (stall == `Stop || stallreq == `Stop) begin

        end else begin
            ex_aluop                <= id_aluop;
            ex_alusel               <= id_alusel;
            ex_reg1                 <= id_reg1;
            ex_reg2                 <= id_reg2;
            ex_wd                   <= id_wd;
            ex_wreg                 <= id_wreg;
            ex_inst_pc              <= id_inst_pc;
            ex_inst_valid           <= id_inst_valid;
            ex_link_address         <= id_link_address;
            ex_inst                 <= id_inst;
            ex_excepttype           <= id_excepttype;
            ex_current_inst_address <= id_current_inst_address;
            ex_csr_we               <= id_csr_we;
            ex_csr_addr             <= id_csr_addr;
            ex_csr_data             <= id_csr_data;
            excp_o                  <= excp_i;
            excp_num_o              <= excp_num_i;
        end
    end

endmodule
