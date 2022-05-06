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
                `EXE_JIRL: begin
                    wreg_o                  = `WriteEnable;
                    aluop_o                 = `EXE_JIRL_OP;
                    alusel_o                = `EXE_RES_JUMP;
                    reg1_read_o             = 1'b1;
                    reg2_read_o             = 1'b0;
                    link_addr_o             = pc_plus_4;
                    branch_flag_o           = `Branch;
                    branch_target_address_o = reg1_o + {{14{imm_16[15]}}, imm_16, 2'b0};
                    reg_waddr_o             = op1;
                    inst_valid              = `InstValid;
                end
                `EXE_B: begin
                    wreg_o                  = `WriteDisable;
                    aluop_o                 = `EXE_B_OP;
                    alusel_o                = `EXE_RES_JUMP;
                    reg1_read_o             = 1'b0;
                    reg2_read_o             = 1'b0;
                    branch_flag_o           = `Branch;
                    branch_target_address_o = pc_i + {{4{imm_10[9]}}, imm_10, imm_16, 2'b0};
                    inst_valid              = `InstValid;
                end
                `EXE_BL: begin
                    wreg_o                  = `WriteEnable;
                    aluop_o                 = `EXE_BL_OP;
                    alusel_o                = `EXE_RES_JUMP;
                    reg1_read_o             = 1'b0;
                    reg2_read_o             = 1'b0;
                    branch_flag_o           = `Branch;
                    link_addr_o             = pc_plus_4;
                    branch_target_address_o = pc_i + {{4{imm_10[9]}}, imm_10, imm_16, 2'b0};
                    reg_waddr_o             = 5'b1;
                    inst_valid              = `InstValid;
                end
                `EXE_BEQ: begin
                    wreg_o      = `WriteDisable;
                    aluop_o     = `EXE_BEQ_OP;
                    alusel_o    = `EXE_RES_JUMP;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b1;
                    reg1_addr_o = op2;
                    reg2_addr_o = op1;
                    if (reg1_o == reg2_o) begin
                        branch_flag_o = `Branch;
                        branch_target_address_o = pc_i + {{14{imm_16[15]}}, imm_16, 2'b0};
                    end
                    inst_valid = `InstValid;
                end
                `EXE_BNE: begin
                    wreg_o      = `WriteDisable;
                    aluop_o     = `EXE_BNE_OP;
                    alusel_o    = `EXE_RES_JUMP;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b1;
                    reg1_addr_o = op2;
                    reg2_addr_o = op1;
                    if (reg1_o != reg2_o) begin
                        branch_flag_o = `Branch;
                        branch_target_address_o = pc_i + {{14{imm_16[15]}}, imm_16, 2'b0};
                    end
                    inst_valid = `InstValid;
                end
                `EXE_BLT: begin
                    wreg_o      = `WriteDisable;
                    aluop_o     = `EXE_BLT_OP;
                    alusel_o    = `EXE_RES_JUMP;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b1;
                    reg1_addr_o = op2;
                    reg2_addr_o = op1;
                    if ({~reg1_o[31], reg1_o[30:0]} < {~reg2_o[31], reg2_o[30:0]}) begin
                        branch_flag_o = `Branch;
                        branch_target_address_o = pc_i + {{14{imm_16[15]}}, imm_16, 2'b0};
                    end
                    inst_valid = `InstValid;
                end
                `EXE_BGE: begin
                    wreg_o      = `WriteDisable;
                    aluop_o     = `EXE_BGE_OP;
                    alusel_o    = `EXE_RES_JUMP;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b1;
                    reg1_addr_o = op2;
                    reg2_addr_o = op1;
                    if ({~reg1_o[31], reg1_o[30:0]} >= {~reg2_o[31], reg2_o[30:0]}) begin
                        branch_flag_o = `Branch;
                        branch_target_address_o = pc_i + {{14{imm_16[15]}}, imm_16, 2'b0};
                    end
                    inst_valid = `InstValid;
                end
                `EXE_BLTU: begin
                    wreg_o      = `WriteDisable;
                    aluop_o     = `EXE_BLTU_OP;
                    alusel_o    = `EXE_RES_JUMP;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b1;
                    reg1_addr_o = op2;
                    reg2_addr_o = op1;
                    if (reg1_o < reg2_o) begin
                        branch_flag_o = `Branch;
                        branch_target_address_o = pc_i + {{14{imm_16[15]}}, imm_16, 2'b0};
                    end
                    inst_valid = `InstValid;
                end
                `EXE_BGEU: begin
                    wreg_o      = `WriteDisable;
                    aluop_o     = `EXE_BGEU_OP;
                    alusel_o    = `EXE_RES_JUMP;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b1;
                    reg1_addr_o = op2;
                    reg2_addr_o = op1;
                    if (reg1_o >= reg2_o) begin
                        branch_flag_o = `Branch;
                        branch_target_address_o = pc_i + {{14{imm_16[15]}}, imm_16, 2'b0};
                    end
                    inst_valid = `InstValid;
                end
                `EXE_LU12I_W: begin
                    wreg_o      = `WriteEnable;
                    aluop_o     = `EXE_LUI_OP;
                    alusel_o    = `EXE_RES_MOVE;
                    reg1_read_o = 1'b0;
                    reg2_read_o = 1'b0;
                    imm         = {imm_20, 12'b0};
                    reg_waddr_o = op1;
                    inst_valid  = `InstValid;
                end
                `EXE_PCADDU12I: begin
                    wreg_o      = `WriteEnable;
                    aluop_o     = `EXE_PCADD_OP;
                    alusel_o    = `EXE_RES_MOVE;
                    reg1_read_o = 1'b0;
                    reg2_read_o = 1'b0;
                    imm         = {imm_20, 12'b0};
                    reg_waddr_o = op1;
                    inst_valid  = `InstValid;
                end
                `EXE_ATOMIC_MEM: begin
                    casez (opcode_2)
                        `EXE_LL_W: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_LL_OP;
                            alusel_o    = `EXE_RES_LOAD_STORE;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_SC_W: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_SC_OP;
                            alusel_o    = `EXE_RES_LOAD_STORE;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b1;
                            reg2_addr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        default: begin
                        end
                    endcase
                end
                `EXE_MEM_RELATED: begin
                    casez (opcode_2)
                        `EXE_LD_B: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_LD_B_OP;
                            alusel_o    = `EXE_RES_LOAD_STORE;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_LD_H: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_LD_H_OP;
                            alusel_o    = `EXE_RES_LOAD_STORE;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_LD_W: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_LD_W_OP;
                            alusel_o    = `EXE_RES_LOAD_STORE;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_ST_B: begin
                            wreg_o      = `WriteDisable;
                            aluop_o     = `EXE_ST_B_OP;
                            alusel_o    = `EXE_RES_LOAD_STORE;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b1;
                            reg2_addr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_ST_H: begin
                            wreg_o      = `WriteDisable;
                            aluop_o     = `EXE_ST_H_OP;
                            alusel_o    = `EXE_RES_LOAD_STORE;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b1;
                            reg2_addr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_ST_W: begin
                            wreg_o      = `WriteDisable;
                            aluop_o     = `EXE_ST_W_OP;
                            alusel_o    = `EXE_RES_LOAD_STORE;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b1;
                            reg2_addr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_LD_BU: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_LD_BU_OP;
                            alusel_o    = `EXE_RES_LOAD_STORE;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_LD_HU: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_LD_HU_OP;
                            alusel_o    = `EXE_RES_LOAD_STORE;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        default: begin
                        end
                    endcase
                end

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
                        `EXE_OTHER: begin
                            case (opcode_3)
                                `EXE_TLB_RELATED: begin
                                    case (opcode_22)
                                        `EXE_TLBFILL: begin
                                            wreg_o      = `WriteDisable;
                                            aluop_o     = `EXE_TLBFILL_OP;
                                            reg1_read_o = 1'b0;
                                            reg2_read_o = 1'b0;
                                            inst_valid  = `InstValid;
                                            kernel_inst = 1'b1;
                                        end
                                        `EXE_TLBRD: begin
                                            wreg_o      = `WriteDisable;
                                            aluop_o     = `EXE_TLBRD_OP;
                                            reg1_read_o = 1'b0;
                                            reg2_read_o = 1'b0;
                                            inst_valid  = `InstValid;
                                            kernel_inst = 1'b1;
                                        end
                                        `EXE_TLBSRCH: begin
                                            wreg_o      = `WriteDisable;
                                            aluop_o     = `EXE_TLBSRCH_OP;
                                            reg1_read_o = 1'b0;
                                            reg2_read_o = 1'b0;
                                            inst_valid  = `InstValid;
                                            kernel_inst = 1'b1;
                                        end
                                        `EXE_TLBWR: begin
                                            wreg_o      = `WriteDisable;
                                            aluop_o     = `EXE_TLBWR_OP;
                                            reg1_read_o = 1'b0;
                                            reg2_read_o = 1'b0;
                                            inst_valid  = `InstValid;
                                            kernel_inst = 1'b1;
                                        end
                                        `EXE_ERTN: begin
                                            wreg_o      = `WriteDisable;
                                            aluop_o     = `EXE_ERTN_OP;
                                            reg1_read_o = 1'b0;
                                            reg2_read_o = 1'b0;
                                            inst_valid  = `InstValid;
                                            kernel_inst = 1'b1;
                                        end
                                        default: begin
                                        end
                                    endcase
                                end
                                default: begin
                                    case (opcode_17)
                                        `EXE_IDLE: begin
                                            wreg_o        = `WriteDisable;
                                            aluop_o       = `EXE_IDLE_OP;
                                            reg1_read_o   = 1'b0;
                                            reg2_read_o   = 1'b0;
                                            idle_stallreq = 1;
                                            idle_pc       = pc_i + 32'h4;
                                            inst_valid    = `InstValid;
                                            kernel_inst   = 1'b1;
                                        end
                                        `EXE_INVTLB: begin
                                            wreg_o      = `WriteDisable;
                                            aluop_o     = `EXE_INVTLB_OP;
                                            reg1_read_o = 1'b0;
                                            reg2_read_o = 1'b0;
                                            inst_valid  = `InstValid;
                                            kernel_inst = 1'b1;
                                        end
                                        default: begin
                                        end
                                    endcase
                                end
                            endcase
                        end
                        default: begin
                        end
                    endcase
                end

                `EXE_ARITHMETIC: begin
                    casez (opcode_2)
                        `EXE_SLTI: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_SLT_OP;
                            alusel_o    = `EXE_RES_ARITH;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            imm         = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_SLTUI: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_SLTU_OP;
                            alusel_o    = `EXE_RES_ARITH;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            imm         = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_ADDI_W: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_ADD_OP;
                            alusel_o    = `EXE_RES_ARITH;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            imm         = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_ANDI: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_AND_OP;
                            alusel_o    = `EXE_RES_LOGIC;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            imm         = {20'h0, imm_12};
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_ORI: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_OR_OP;
                            alusel_o    = `EXE_RES_LOGIC;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            imm         = {20'h0, imm_12};
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_XORI: begin
                            wreg_o      = `WriteEnable;
                            aluop_o     = `EXE_XOR_OP;
                            alusel_o    = `EXE_RES_LOGIC;
                            reg1_read_o = 1'b1;
                            reg2_read_o = 1'b0;
                            imm         = {20'h0, imm_12};
                            reg_waddr_o = op1;
                            inst_valid  = `InstValid;
                        end
                        `EXE_LONG_ARITH: begin
                            case (opcode_3)
                                `EXE_ADD_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_ADD_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_SUB_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_SUB_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_SLT: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_SLT_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_SLTU: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_SLTU_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_NOR: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_NOR_OP;
                                    alusel_o    = `EXE_RES_LOGIC;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_AND: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_AND_OP;
                                    alusel_o    = `EXE_RES_LOGIC;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_OR: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_OR_OP;
                                    alusel_o    = `EXE_RES_LOGIC;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_XOR: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_XOR_OP;
                                    alusel_o    = `EXE_RES_LOGIC;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_SLL_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_SLL_OP;
                                    alusel_o    = `EXE_RES_SHIFT;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_SRL_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_SRL_OP;
                                    alusel_o    = `EXE_RES_SHIFT;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_SRA_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_SRA_OP;
                                    alusel_o    = `EXE_RES_SHIFT;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_MUL_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_MUL_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_MULH_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_MULH_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_MULH_WU: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_MULHU_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                default: begin
                                end

                            endcase
                        end
                        `EXE_DIV_ARITH: begin
                            casez (opcode_3)
                                `EXE_DIV_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_DIV_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_MOD_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_MOD_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_DIV_WU: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_DIV_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_MOD_WU: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_MOD_OP;
                                    alusel_o    = `EXE_RES_ARITH;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b1;
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_BREAK: begin
                                    wreg_o      = `WriteDisable;
                                    aluop_o     = `EXE_BREAK_OP;
                                    alusel_o    = `EXE_RES_NOP;
                                    reg1_read_o = 1'b0;
                                    reg2_read_o = 1'b0;
                                    inst_valid  = `InstValid;
                                    inst_break  = `True_v;
                                end
                                `EXE_SYSCALL: begin
                                    wreg_o       = `WriteEnable;
                                    aluop_o      = `EXE_SYSCALL_OP;
                                    alusel_o     = `EXE_RES_NOP;
                                    reg1_read_o  = 1'b0;
                                    reg2_read_o  = 1'b0;
                                    inst_valid   = `InstValid;
                                    inst_syscall = `True_v;
                                end
                                default: begin
                                end
                            endcase
                        end
                        `EXE_SHIFT_ARITH: begin
                            casez (opcode_3)
                                `EXE_SLLI_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_SLL_OP;
                                    alusel_o    = `EXE_RES_SHIFT;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b0;
                                    imm         = {27'b0, imm_5};
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_SRLI_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_SRL_OP;
                                    alusel_o    = `EXE_RES_SHIFT;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b0;
                                    imm         = {27'b0, imm_5};
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                `EXE_SRAI_W: begin
                                    wreg_o      = `WriteEnable;
                                    aluop_o     = `EXE_SRA_OP;
                                    alusel_o    = `EXE_RES_SHIFT;
                                    reg1_read_o = 1'b1;
                                    reg2_read_o = 1'b0;
                                    imm         = {27'b0, imm_5};
                                    reg_waddr_o = op1;
                                    inst_valid  = `InstValid;
                                end
                                default: begin
                                end
                            endcase
                        end
                        default: begin

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
