`include "defines.sv"
`include "instr_info.sv"
`include "csr_defines.sv"

`include "pipeline/2_decode/decoder_2R.sv"
`include "pipeline/2_decode/decoder_3R.sv"
`include "pipeline/2_decode/decoder_2RI12.sv"
`include "pipeline/2_decode/decoder_2RI16.sv"


// ID stage
// Should be totally cominational circuit
// What ID DO:
// 1. Extract information from the instruction
// 2. Do GPR and CSR read
// 3. Determine oprands for EXE
// What ID NOT DO:
// 1. Determine whether a instruction dispatch in EXE or not
// 2. Calculate anything, such as branch target
//
module id #(
    parameter EXE_STAGE_WIDTH = 2,
    parameter MEM_STAGE_WIDTH = 2
) (
    // <- Instruction Buffer
    input instr_buffer_info_t instr_buffer_i,

    input logic excp_i,
    input logic [3:0] excp_num_i,

    // <-> Regfile
    output logic [1:0] regfile_reg_read_valid_o,  // Read valid for 2 regs
    output logic [`RegNumLog2*2-1:0] regfile_reg_read_addr_o,  // Read addr, {reg2, reg1}
    input logic [`RegBus][1:0] regfile_reg_read_data_i,  // Read result

    // <- EXE
    // Data forwarding
    input logic ex_write_reg_valid_i[EXE_STAGE_WIDTH],
    input logic [`RegAddrBus] ex_write_reg_addr_i[EXE_STAGE_WIDTH],
    input logic [`RegBus] ex_write_reg_data_i[EXE_STAGE_WIDTH],
    input logic [`AluOpBus] ex_aluop_i[EXE_STAGE_WIDTH],

    // <- Mem
    // Data forwarding
    input logic mem_write_reg_valid_i[MEM_STAGE_WIDTH],
    input logic [`RegAddrBus] mem_write_reg_addr_i[MEM_STAGE_WIDTH],
    input logic [`RegBus] mem_write_reg_data_i[MEM_STAGE_WIDTH],


    // -> EXE
    output reg [`AluOpBus] ex_aluop_o,
    output reg [`AluSelBus] ex_alusel_o,
    output reg [`RegBus] ex_op1_o,
    output reg [`RegBus] ex_op2_o,
    output reg ex_reg_write_valid_o,
    output reg [`RegAddrBus] ex_reg_write_addr_o,
    output instr_buffer_info_t ex_instr_info_o,  // Instruction info passed to EXE
    output reg ex_csr_we_o,
    output csr_write_signal ex_csr_signal_o,

    output logic broadcast_excp_o,
    output logic [8:0] broadcast_excp_num_o,

    // <- CSR
    input logic has_int,
    input logic [`RegBus] csr_data_i,
    input logic [1:0] csr_plv,

    // -> CSR
    output reg [13:0] csr_read_addr_o
);

    logic [`InstAddrBus] pc_i;
    assign pc_i = instr_buffer_i.valid ? instr_buffer_i.pc : `ZeroWord;
    logic [`InstBus] inst_i;
    assign inst_i = instr_buffer_i.valid ? instr_buffer_i.instr : `ZeroWord;

    logic instr_break, instr_syscall, kernel_instr;

    // Sub-decoder section
    localparam SUB_DECODER_NUM = 7;
    logic sub_decoder_valid[SUB_DECODER_NUM];
    logic [`AluOpBus] sub_decoder_aluop[SUB_DECODER_NUM];
    logic [`AluSelBus] sub_decoder_alusel[SUB_DECODER_NUM];
    logic [1:0] sub_decoder_reg_read_valid[SUB_DECODER_NUM];
    logic [`RegNumLog2*2-1:0] sub_decoder_reg_read_addr[SUB_DECODER_NUM];
    logic sub_decoder_reg_write_valid[SUB_DECODER_NUM];
    logic [`RegAddrBus] sub_decoder_reg_write_addr[SUB_DECODER_NUM];
    logic [`RegBus] sub_decoder_imm[SUB_DECODER_NUM];

    // Sub-decoders in following order:
    // 2R, 3R, 2RI8, 2RI12, 2RI16, I26, Special
    decoder_2R u_decoder_2R (
        .instr_info_i         (instr_buffer_i),
        .decode_result_valid_o(sub_decoder_valid[0]),
        .aluop_o              (sub_decoder_aluop[0])
    );
    decoder_3R u_decoder_3R (
        .instr_info_i         (instr_buffer_i),
        .decode_result_valid_o(sub_decoder_valid[1]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[1]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[1]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[1]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[1]),
        .aluop_o              (sub_decoder_aluop[1]),
        .alusel_o             (sub_decoder_alusel[1]),
        .instr_break          (instr_break),
        .instr_syscall        (instr_syscall)
    );
    // FIXME: 2RI8 not implemented
    decoder_2RI12 u_decoder_2RI12 (
        .instr_info_i         (instr_buffer_i),
        .decode_result_valid_o(sub_decoder_valid[3]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[3]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[3]),
        .imm_o                (sub_decoder_imm[3]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[3]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[3]),
        .aluop_o              (sub_decoder_aluop[3]),
        .alusel_o             (sub_decoder_alusel[3])
    );
    decoder_2RI16 u_decoder_2RI16 (
        .instr_info_i         (instr_buffer_i),
        .decode_result_valid_o(sub_decoder_valid[4]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[4]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[4]),
        .imm_o                (sub_decoder_imm[4]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[4]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[4]),
        .aluop_o              (sub_decoder_aluop[4]),
        .alusel_o             (sub_decoder_alusel[4])
    );
    // FIXME: I16 and Special not implemented

    // Sub-decoder END

    // Generate imm, using OR
    logic [`RegBus] imm;
    always_comb begin
        imm = 0;
        for (integer i = 0; i < SUB_DECODER_NUM; i++) begin
            imm = imm | sub_decoder_imm[i];
        end
    end
    // Generate instr_valid, using OR
    logic instr_valid;
    always_comb begin
        instr_valid = 0;
        for (integer i = 0; i < SUB_DECODER_NUM; i++) begin
            instr_valid = instr_valid | sub_decoder_valid[i];
        end
    end
    // Generate output to EXE
    always_comb begin
        ex_aluop_o = 0;
        ex_alusel_o = 0;
        ex_reg_write_valid_o = 0;
        ex_reg_write_addr_o = 0;
        for (integer i = 0; i < SUB_DECODER_NUM; i++) begin
            ex_aluop_o = ex_aluop_o | sub_decoder_aluop[i];
            ex_alusel_o = ex_alusel_o | sub_decoder_alusel[i];
            ex_reg_write_valid_o = ex_reg_write_valid_o | sub_decoder_reg_write_valid[i];
            ex_reg_write_addr_o = ex_reg_write_addr_o | sub_decoder_reg_write_addr[i];
        end
    end
    // Generate output to Regfile
    always_comb begin
        regfile_reg_read_valid_o = 0;
        regfile_reg_read_addr_o  = 0;
        for (integer i = 0; i < SUB_DECODER_NUM; i++) begin
            regfile_reg_read_valid_o = regfile_reg_read_valid_o | sub_decoder_reg_read_valid[i];
            regfile_reg_read_addr_o  = regfile_reg_read_addr_o | sub_decoder_reg_read_addr[i];
        end
    end


    // Generate output
    assign ex_instr_info_o.valid = instr_valid;
    assign ex_instr_info_o.pc = pc_i;
    assign ex_instr_info_o.instr = inst_i;


    // TODO: add explanation
    logic res_from_csr;
    logic excp_ine;
    logic excp_ipe;

    assign excp_ine = (instr_valid == `InstInvalid) && instr_buffer_i.valid;
    assign excp_ipe = kernel_instr && (csr_plv == 2'b11);

    assign broadcast_excp_o = excp_ipe | instr_syscall | instr_break | excp_i | excp_ine | has_int;
    assign broadcast_excp_num_o = {
        excp_ipe, excp_ine, instr_break, instr_syscall, excp_num_i, has_int
    };

    // TODO: ex_op generate rules not implemented yet



endmodule
