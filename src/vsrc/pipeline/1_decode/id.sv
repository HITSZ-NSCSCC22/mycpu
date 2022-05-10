`include "defines.sv"
`include "instr_info.sv"
`include "csr_defines.sv"
`include "pipeline_defines.sv"

`include "pipeline/1_decode/decoder_2R.sv"
`include "pipeline/1_decode/decoder_3R.sv"
`include "pipeline/1_decode/decoder_2RI8.sv"
`include "pipeline/1_decode/decoder_2RI12.sv"
`include "pipeline/1_decode/decoder_2RI16.sv"
`include "pipeline/1_decode/decoder_1RI20.sv"
`include "pipeline/1_decode/decoder_2RI14.sv"
`include "pipeline/1_decode/decoder_CSR.sv"
`include "pipeline/1_decode/decoder_I26.sv"


// ID stage
// Should be totally cominational circuit
// What ID DO:
// 1. Extract information from the instruction
// 2. Do GPR and CSR read
// 3. Determine oprands for EXE
// What ID NOT DO:
// 1. Determine whether a instruction dispatch in EXE or not
// 2. Calculate anything, such as branch target
// TODO: move regfile read to dispatch stage
// 
module id (
    // <- Instruction Buffer
    input instr_buffer_info_t instr_buffer_i,

    input logic excp_i,
    input logic [3:0] excp_num_i,

    // -> Dispatch
    output id_dispatch_struct dispatch_o,

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
    localparam SUB_DECODER_NUM = 9;
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
    decoder_2RI8 U_decoder_2RI8 (
        .instr_info_i         (instr_buffer_i),
        .decode_result_valid_o(sub_decoder_valid[2]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[2]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[2]),
        .imm_o                (sub_decoder_imm[2]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[2]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[2]),
        .aluop_o              (sub_decoder_aluop[2]),
        .alusel_o             (sub_decoder_alusel[2])
    );
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

    decoder_1RI20 U_decoder_1RI20 (
        .instr_info_i         (instr_buffer_i),
        .decode_result_valid_o(sub_decoder_valid[5]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[5]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[5]),
        .imm_o                (sub_decoder_imm[5]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[5]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[5]),
        .aluop_o              (sub_decoder_aluop[5]),
        .alusel_o             (sub_decoder_alusel[5])
    );
    decoder_2RI14 U_decoder_2RI14 (
        .instr_info_i         (instr_buffer_i),
        .decode_result_valid_o(sub_decoder_valid[6]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[6]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[6]),
        .imm_o                (sub_decoder_imm[6]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[6]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[6]),
        .aluop_o              (sub_decoder_aluop[6]),
        .alusel_o             (sub_decoder_alusel[6])
    );
    decoder_I26 U_decoder_I26 (
        .instr_info_i         (instr_buffer_i),
        .decode_result_valid_o(sub_decoder_valid[7]),
        .imm_o                (sub_decoder_imm[7]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[7]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[7]),
        .aluop_o              (sub_decoder_aluop[7]),
        .alusel_o             (sub_decoder_alusel[7])
    );
    decoder_CSR u_decoder_CSR (
        .instr_info_i         (instr_buffer_i),
        .decode_result_valid_o(sub_decoder_valid[8]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[8]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[8]),
        .imm_o                (sub_decoder_imm[8]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[8]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[8]),
        .aluop_o              (sub_decoder_aluop[8])
    );
    // Sub-decoder END

    // Generate imm, using OR
    logic [`RegBus] imm;
    assign dispatch_o.use_imm = imm != 0;  // HACK: works for now
    assign dispatch_o.imm = imm;
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
        dispatch_o.aluop = 0;
        dispatch_o.alusel = 0;
        dispatch_o.reg_write_valid = 0;
        dispatch_o.reg_write_addr = 0;
        for (integer i = 0; i < SUB_DECODER_NUM; i++) begin
            dispatch_o.aluop = dispatch_o.aluop | sub_decoder_aluop[i];
            dispatch_o.alusel = dispatch_o.alusel | sub_decoder_alusel[i];
            dispatch_o.reg_write_valid = dispatch_o.reg_write_valid | sub_decoder_reg_write_valid[i];
            dispatch_o.reg_write_addr = dispatch_o.reg_write_addr | sub_decoder_reg_write_addr[i];
        end
    end
    // Generate output to Regfile
    always_comb begin
        dispatch_o.reg_read_valid = 0;
        dispatch_o.reg_read_addr  = 0;
        for (integer i = 0; i < SUB_DECODER_NUM; i++) begin
            dispatch_o.reg_read_valid = dispatch_o.reg_read_valid | sub_decoder_reg_read_valid[i];
            dispatch_o.reg_read_addr  = dispatch_o.reg_read_addr | sub_decoder_reg_read_addr[i];
        end
    end


    // Generate output
    assign dispatch_o.instr_info.valid = instr_valid;
    assign dispatch_o.instr_info.pc = pc_i;
    assign dispatch_o.instr_info.instr = inst_i;


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

    //logic pre_load;
    //assign pre_load = ((ex_aluop_i == `EXE_LB_OP) ||(ex_aluop_i == `EXE_LBU_OP)||(ex_aluop_i == `EXE_LH_OP) ||
  	//												(ex_aluop_i == `EXE_LHU_OP)||
  	//												(ex_aluop_i == `EXE_LW_OP) ||
  	//												(ex_aluop_i == `EXE_LWR_OP)||
  	//												(ex_aluop_i == `EXE_LWL_OP)||
  	//												(ex_aluop_i == `EXE_LL_OP) ||
  	//												(ex_aluop_i == `EXE_SC_OP)) ? 1'b1 : 1'b0;

    // TODO: ex_op generate rules not implemented yet



endmodule
