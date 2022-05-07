`timescale 1ns / 1ns

`include "defines.sv"
`include "instr_info.sv"
`include "csr_defines.sv"



module id (
    input logic rst,

    // <- Instruction Buffer
    input instr_buffer_info_t instr_buffer_i,


    input logic excp_i,
    input logic [3:0] excp_num_i,

    // <- Regfile
    input logic [`RegBus] reg1_data_i,
    input logic [`RegBus] reg2_data_i,

    input instr_buffer_info_t instr_buffer_i_other,

    // <- EXE
    input logic ex_wreg_i_1,
    input logic [`RegAddrBus] ex_waddr_i_1,
    input logic [`RegBus] ex_wdata_i_1,
    input logic [`AluOpBus] ex_aluop_i_1,


    // <- ANOTHER_EXE
    input logic ex_wreg_i_2,
    input logic [`RegAddrBus] ex_waddr_i_2,
    input logic [`RegBus] ex_wdata_i_2,
    input logic [`AluOpBus] ex_aluop_i_2,

    // <- Mem
    input logic mem_wreg_i_1,
    input logic [`RegAddrBus] mem_waddr_i_1,
    input logic [`RegBus] mem_wdata_i_1,

    // <- ANOTHER_Mem
    input logic mem_wreg_i_2,
    input logic [`RegAddrBus] mem_waddr_i_2,
    input logic [`RegBus] mem_wdata_i_2,

    // -> Regfile
    output reg reg1_read_o,
    output reg reg2_read_o,

    // -> EXE
    output reg [`RegAddrBus] reg1_addr_o,
    output reg [`RegAddrBus] reg2_addr_o,
    output reg [`AluOpBus] aluop_o,
    output reg [`AluSelBus] alusel_o,
    output reg [`RegBus] reg1_o,
    output reg [`RegBus] reg2_o,
    output reg [`RegAddrBus] reg_waddr_o,
    output reg wreg_o,
    output reg inst_valid,
    output reg [`InstAddrBus] inst_pc,
    output logic [`RegBus] inst_o,
    output logic [`RegBus] current_inst_address_o,
    output reg csr_we,
    output csr_write_signal csr_signal_o,
    output logic excp_o,
    output logic [8:0] excp_num_o,

    // <- CSR
    input logic has_int,
    input logic [`RegBus] csr_data_i,
    input logic [1:0] csr_plv,

    // -> CSR
    output reg [13:0] csr_read_addr_o,

    // -> PC
    output reg branch_flag_o,
    output reg [`RegBus] branch_target_address_o,
    output reg [`RegBus] link_addr_o,
    output reg [`InstAddrBus] idle_pc,

    // ->Ctrl
    output logic stallreq,
    output reg   idle_stallreq
);

    logic [`InstAddrBus] pc_i;
    assign pc_i = instr_buffer_i.valid ? instr_buffer_i.pc : `ZeroWord;
    logic [`InstBus] inst_i;
    assign inst_i = instr_buffer_i.valid ? instr_buffer_i.instr : `ZeroWord;


    logic [ 5:0] opcode_6 = inst_i[31:26];
    logic [ 6:0] opcode_7 = inst_i[31:25];
    logic [ 7:0] opcode_8 = inst_i[31:24];
    logic [ 9:0] opcode_10 = inst_i[31:22];
    logic [13:0] opcode_14 = inst_i[31:18];
    logic [16:0] opcode_17 = inst_i[31:15];
    logic [21:0] opcode_22 = inst_i[31:10];
    logic [ 4:0] imm_5 = inst_i[14:10];
    logic [ 9:0] imm_10 = inst_i[9:0];
    logic [13:0] imm_14 = inst_i[23:10];
    logic [15:0] imm_16 = inst_i[25:10];
    logic [11:0] imm_12 = inst_i[21:10];
    logic [19:0] imm_20 = inst_i[24:5];
    logic [ 4:0] op1;
    assign op1 = inst_i[4:0];
    logic [4:0] op2 = inst_i[9:5];
    logic [4:0] op3 = inst_i[14:10];
    logic [4:0] op4 = inst_i[19:15];

    logic [5:0] opcode_1 = inst_i[31:26];
    logic [5:0] opcode_2 = inst_i[25:20];
    logic [4:0] opcode_3 = inst_i[19:15];
    logic [4:0] opcode_4 = inst_i[14:10];

    logic [`RegBus] pc_plus_4;

    assign pc_plus_4 = pc_i + 4;
    assign inst_o = inst_i;

    reg [`RegBus] imm;

    reg stallreq_for_reg1_loadrelate;
    reg stallreq_for_reg2_loadrelate;
    logic pre_inst_is_load;


    logic res_from_csr;
    logic excp_ine;
    logic excp_ipe;

    assign pre_inst_is_load = (((ex_aluop_i_1 == `EXE_LD_B_OP) ||
                             (ex_aluop_i_1 == `EXE_LD_H_OP) ||
                             (ex_aluop_i_1 == `EXE_LD_W_OP) ||
                             (ex_aluop_i_1 == `EXE_LD_BU_OP) ||
                             (ex_aluop_i_1 == `EXE_LD_HU_OP) ||
                             (ex_aluop_i_1 == `EXE_ST_B_OP) ||
                             (ex_aluop_i_1 == `EXE_ST_H_OP) ||
                             (ex_aluop_i_1 == `EXE_ST_W_OP))||(
                             (ex_aluop_i_2 == `EXE_LD_B_OP) ||
                             (ex_aluop_i_2 == `EXE_LD_H_OP) ||
                             (ex_aluop_i_2 == `EXE_LD_W_OP) ||
                             (ex_aluop_i_2 == `EXE_LD_BU_OP) ||
                             (ex_aluop_i_2 == `EXE_LD_HU_OP) ||
                             (ex_aluop_i_2 == `EXE_ST_B_OP) ||
                             (ex_aluop_i_2 == `EXE_ST_H_OP) ||
                             (ex_aluop_i_2 == `EXE_ST_W_OP)) && (pc_i == instr_buffer_i_other.pc + 4)) ? 1'b1 : 1'b0;

    reg inst_syscall;
    reg inst_break;
    reg kernel_inst;



    assign current_inst_address_o = pc_i;


    assign excp_ine = (inst_valid == `InstInvalid) && instr_buffer_i.valid;
    assign excp_ipe = kernel_inst && (csr_plv == 2'b11);

    assign excp_o = excp_ipe | inst_syscall | inst_break | excp_i | excp_ine | has_int;
    assign excp_num_o = {excp_ipe, excp_ine, inst_break, inst_syscall, excp_num_i, has_int};


    always @(*) begin
        if (rst == `RstEnable) stallreq_for_reg1_loadrelate = `NoStop;
        else if (pre_inst_is_load == 1'b1 && ex_waddr_i_1 == reg1_addr_o && reg1_read_o == 1'b1)
            stallreq_for_reg1_loadrelate = `Stop;
    end

    always @(*) begin

        if (rst == `RstEnable) stallreq_for_reg2_loadrelate = `NoStop;
        else if (pre_inst_is_load == 1'b1 && ex_waddr_i_1 == reg2_addr_o && reg2_read_o == 1'b1)
            stallreq_for_reg2_loadrelate = `Stop;
    end

    //如果这条指令与另一条相邻且存在依赖就直接暂停
    assign stallreq = stallreq_for_reg1_loadrelate | stallreq_for_reg2_loadrelate;

    always @(*) begin
        inst_pc = pc_i;
    end

    always @(*) begin
        if (rst == `RstEnable) begin
            aluop_o                 = `EXE_NOP_OP;
            alusel_o                = `EXE_RES_NOP;
            reg_waddr_o             = `NOPRegAddr;
            wreg_o                  = `WriteDisable;
            inst_valid              = `InstInvalid;
            reg1_read_o             = 1'b0;
            reg2_read_o             = 1'b0;
            reg1_addr_o             = `NOPRegAddr;
            reg2_addr_o             = `NOPRegAddr;
            imm                     = 32'h0;
            branch_flag_o           = `NotBranch;
            branch_target_address_o = `ZeroWord;
            link_addr_o             = `ZeroWord;
            inst_break              = `False_v;
            inst_syscall            = `False_v;
            idle_stallreq           = 1'b0;
        end else begin
            aluop_o                 = `EXE_NOP_OP;
            alusel_o                = `EXE_RES_NOP;
            reg_waddr_o             = op1;
            wreg_o                  = `WriteDisable;
            inst_valid              = `InstInvalid;
            reg1_read_o             = 1'b0;
            reg2_read_o             = 1'b0;
            reg1_addr_o             = op2;
            reg2_addr_o             = op3;
            imm                     = `ZeroWord;
            branch_flag_o           = `NotBranch;
            branch_target_address_o = `ZeroWord;
            link_addr_o             = `ZeroWord;
            idle_stallreq           = 1'b0;
            case (opcode_1)

                `EXE_SPECIAL: begin
                    case (opcode_2)
                        `EXE_CSR_RELATED: begin
                            case (op2)
                                `EXE_CSRRD: begin
                                    wreg_o            = `WriteEnable;
                                    aluop_o           = `EXE_CSRRD_OP;
                                    reg1_read_o       = 1'b1;
                                    reg2_read_o       = 1'b0;
                                    imm               = {18'b0, imm_14};
                                    csr_signal_o.we   = 1'b1;
                                    csr_signal_o.addr = imm_14;
                                    csr_signal_o.data = `ZeroWord;
                                    reg_waddr_o       = op1;
                                    inst_valid        = `InstValid;
                                    res_from_csr      = 1'b1;
                                    kernel_inst       = 1'b1;
                                end
                                `EXE_CSRWR: begin
                                    wreg_o            = `WriteEnable;
                                    aluop_o           = `EXE_CSRWR_OP;
                                    reg1_read_o       = 1'b1;
                                    reg2_read_o       = 1'b0;
                                    imm               = {18'b0, imm_14};
                                    csr_signal_o.we   = 1'b1;
                                    csr_signal_o.addr = imm_14;
                                    csr_signal_o.data = reg1_data_i;
                                    reg1_addr_o       = op1;
                                    reg_waddr_o       = op1;
                                    inst_valid        = `InstValid;
                                    res_from_csr      = 1'b1;
                                    kernel_inst       = 1'b1;
                                end
                                default: begin
                                    wreg_o            = `WriteEnable;
                                    aluop_o           = `EXE_CSRXCHG_OP;
                                    reg1_read_o       = 1'b0;
                                    reg2_read_o       = 1'b0;
                                    imm               = {18'b0, imm_14};
                                    csr_signal_o.we   = 1'b1;
                                    csr_signal_o.addr = imm_14;
                                    csr_signal_o.data = reg1_data_i;
                                    reg_waddr_o       = op1;
                                    inst_valid        = `InstValid;
                                    res_from_csr      = 1'b1;
                                    kernel_inst       = 1'b1;
                                end
                            endcase
                        end
                    endcase
                end

                default: begin
                end
            endcase
        end
    end

    always @(*) begin
        if (rst == `RstEnable) reg1_o = `ZeroWord;
        else if (opcode_2[5:4] == 2'b00)
            reg1_o = csr_data_i;  // EXE_CSR_RELATED, TODO: replace magic number
        else if ((reg1_read_o == 1'b1) && (reg1_addr_o == 0)) reg1_o = `ZeroWord;
        else if ((reg1_read_o == 1'b1) && (ex_wreg_i_2 == 1'b1) && (ex_waddr_i_2 == reg1_addr_o))
            reg1_o = ex_wdata_i_2;
        else if ((reg1_read_o == 1'b1) && (mem_wreg_i_2 == 1'b1) && (mem_waddr_i_2 == reg1_addr_o))
            reg1_o = mem_wdata_i_2;
        else if ((reg1_read_o == 1'b1) && (ex_wreg_i_1 == 1'b1) && (ex_waddr_i_1 == reg1_addr_o))
            reg1_o = ex_wdata_i_1;
        else if ((reg1_read_o == 1'b1) && (mem_wreg_i_1 == 1'b1) && (mem_waddr_i_1 == reg1_addr_o))
            reg1_o = mem_wdata_i_1;
        else if (reg1_read_o == 1'b1) reg1_o = reg1_data_i;
        else if (reg1_read_o == 1'b0) reg1_o = imm;
        else reg1_o = `ZeroWord;
    end

    always @(*) begin
        if (rst == `RstEnable) reg2_o = `ZeroWord;
        else if (opcode_2[5:4] == 2'b00) reg2_o = `ZeroWord;
        else if ((reg2_read_o == 1'b1) && (reg2_addr_o == 0)) reg2_o = `ZeroWord;
        else if ((reg2_read_o == 1'b1) && (ex_wreg_i_2 == 1'b1) && (ex_waddr_i_2 == reg2_addr_o))
            reg2_o = ex_wdata_i_2;
        else if ((reg2_read_o == 1'b1) && (mem_wreg_i_2 == 1'b1) && (mem_waddr_i_2 == reg2_addr_o))
            reg2_o = mem_wdata_i_2;
        else if ((reg2_read_o == 1'b1) && (ex_wreg_i_1 == 1'b1) && (ex_waddr_i_1 == reg2_addr_o))
            reg2_o = ex_wdata_i_1;
        else if ((reg2_read_o == 1'b1) && (mem_wreg_i_1 == 1'b1) && (mem_waddr_i_1 == reg2_addr_o))
            reg2_o = mem_wdata_i_1;
        else if (reg2_read_o == 1'b1) reg2_o = reg2_data_i;
        else if (reg2_read_o == 1'b0) reg2_o = imm;
        else reg2_o = `ZeroWord;
    end

endmodule
