`include "defines.sv"
`include "csr_defines.sv"
`include "core_types.sv"

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
// 2. Receives interrupt and packed into instr_info
// What ID NOT DO:
// 1. Determine whether a instruction dispatch in EXE or not
// 2. Calculate anything, such as branch target
// 3. CSR & GPR read is moved to dispatch stage
// 4. op1, op2 and imm is passed through to EXE, no selection made here
module id
    import core_types::*;
(
    // <- Instruction Buffer
    input instr_info_t instr_buffer_i,

    // -> Dispatch
    output id_dispatch_struct dispatch_o,

    // <- CSR
    input logic has_int,
    input logic [1:0] csr_plv

);

    // Input
    logic [`InstAddrBus] pc_i;
    logic [`InstBus] instr_i;
    logic is_last_in_block;
    assign pc_i = instr_buffer_i.valid ? instr_buffer_i.pc : 0;
    assign instr_i = instr_buffer_i.valid ? instr_buffer_i.instr : 0;
    assign is_last_in_block = instr_buffer_i.valid ? instr_buffer_i.is_last_in_block : 0;

    // Exception info
    logic excp;
    logic excp_ine;
    logic excp_ipe;
    logic [8:0] excp_num;  // IPE, INE, BREAK, SYSCALL, {4 frontend excp}, INT


    // Instruction info
    logic instr_valid;
    logic [`AluOpBus] instr_aluop;
    logic [`AluSelBus] instr_alusel;
    logic [1:0] instr_reg_read_valid;
    logic [`RegNumLog2*2-1:0] instr_reg_read_addr;
    logic instr_reg_write_valid;
    logic [`RegAddrBus] instr_reg_write_addr;
    logic [`RegBus] instr_imm;
    logic instr_use_imm;
    special_info_t instr_special_info;
    // Sub-decoder signals
    localparam SUB_DECODER_NUM = 9;
    logic sub_decoder_valid[SUB_DECODER_NUM];
    logic [`AluOpBus] sub_decoder_aluop[SUB_DECODER_NUM];
    logic [`AluSelBus] sub_decoder_alusel[SUB_DECODER_NUM];
    logic [1:0] sub_decoder_reg_read_valid[SUB_DECODER_NUM];
    logic [`RegNumLog2*2-1:0] sub_decoder_reg_read_addr[SUB_DECODER_NUM];
    logic sub_decoder_reg_write_valid[SUB_DECODER_NUM];
    logic [`RegAddrBus] sub_decoder_reg_write_addr[SUB_DECODER_NUM];
    logic [`RegBus] sub_decoder_imm[SUB_DECODER_NUM];
    logic sub_decoder_use_imm[SUB_DECODER_NUM];
    logic sub_decoder_kernel_instr[SUB_DECODER_NUM];
    special_info_t sub_decoder_special_info[SUB_DECODER_NUM];


    // Info about privilege instr
    logic instr_break, instr_syscall, instr_kernel_instr;
    // assign kernel_instr = instr_aluop == `EXE_CSRRD_OP | instr_aluop == `EXE_CSRWR_OP | instr_aluop == `EXE_CSRXCHG_OP |
    //                       instr_aluop == `EXE_TLBFILL_OP |instr_aluop == `EXE_TLBRD_OP |instr_aluop == `EXE_TLBWR_OP |
    //                       instr_aluop == `EXE_TLBSRCH_OP | instr_aluop == `EXE_ERTN_OP |instr_aluop == `EXE_IDLE_OP |
    //                       instr_aluop == `EXE_INVTLB_OP | instr_aluop == `EXE_CACOP_OP;

    // Sub-decoders in following order:
    // 2R, 3R, 2RI8, 2RI12, 2RI16, 1RI20, 2RI14, I26, Special
    decoder_2R u_decoder_2R (
        .instr_i              (instr_i),
        .decode_result_valid_o(sub_decoder_valid[0]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[0]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[0]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[0]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[0]),
        .use_imm              (sub_decoder_use_imm[0]),
        .aluop_o              (sub_decoder_aluop[0]),
        .alusel_o             (sub_decoder_alusel[0]),
        .kernel_instr         (sub_decoder_kernel_instr[0]),
        .special_info_o       (sub_decoder_special_info[0])
    );
    decoder_3R u_decoder_3R (
        .instr_i              (instr_i),
        .decode_result_valid_o(sub_decoder_valid[1]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[1]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[1]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[1]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[1]),
        .use_imm              (sub_decoder_use_imm[1]),
        .imm_o                (sub_decoder_imm[1]),
        .aluop_o              (sub_decoder_aluop[1]),
        .alusel_o             (sub_decoder_alusel[1]),
        .instr_break          (instr_break),
        .instr_syscall        (instr_syscall),
        .kernel_instr         (sub_decoder_kernel_instr[1]),
        .special_info_o       (sub_decoder_special_info[1])
    );
    decoder_2RI8 U_decoder_2RI8 (
        .instr_i              (instr_i),
        .decode_result_valid_o(sub_decoder_valid[2]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[2]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[2]),
        .use_imm              (sub_decoder_use_imm[2]),
        .imm_o                (sub_decoder_imm[2]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[2]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[2]),
        .aluop_o              (sub_decoder_aluop[2]),
        .alusel_o             (sub_decoder_alusel[2]),
        .special_info_o       (sub_decoder_special_info[2])
    );
    decoder_2RI12 u_decoder_2RI12 (
        .instr_i              (instr_i),
        .decode_result_valid_o(sub_decoder_valid[3]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[3]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[3]),
        .use_imm              (sub_decoder_use_imm[3]),
        .imm_o                (sub_decoder_imm[3]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[3]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[3]),
        .aluop_o              (sub_decoder_aluop[3]),
        .alusel_o             (sub_decoder_alusel[3]),
        .kernel_instr         (sub_decoder_kernel_instr[3]),
        .special_info_o       (sub_decoder_special_info[3])
    );
    decoder_2RI16 u_decoder_2RI16 (
        .instr_i              (instr_i),
        .decode_result_valid_o(sub_decoder_valid[4]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[4]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[4]),
        .use_imm              (sub_decoder_use_imm[4]),
        .imm_o                (sub_decoder_imm[4]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[4]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[4]),
        .aluop_o              (sub_decoder_aluop[4]),
        .alusel_o             (sub_decoder_alusel[4]),
        .kernel_instr         (sub_decoder_kernel_instr[4]),
        .special_info_o       (sub_decoder_special_info[4])
    );
    decoder_1RI20 U_decoder_1RI20 (
        .instr_i              (instr_i),
        .decode_result_valid_o(sub_decoder_valid[5]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[5]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[5]),
        .use_imm              (sub_decoder_use_imm[5]),
        .imm_o                (sub_decoder_imm[5]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[5]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[5]),
        .aluop_o              (sub_decoder_aluop[5]),
        .alusel_o             (sub_decoder_alusel[5]),
        .special_info_o       (sub_decoder_special_info[5])
    );
    decoder_2RI14 U_decoder_2RI14 (
        .instr_i              (instr_i),
        .decode_result_valid_o(sub_decoder_valid[6]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[6]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[6]),
        .use_imm              (sub_decoder_use_imm[6]),
        .imm_o                (sub_decoder_imm[6]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[6]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[6]),
        .aluop_o              (sub_decoder_aluop[6]),
        .alusel_o             (sub_decoder_alusel[6]),
        .special_info_o       (sub_decoder_special_info[6])
    );
    decoder_I26 U_decoder_I26 (
        .instr_i              (instr_i),
        .decode_result_valid_o(sub_decoder_valid[7]),
        .imm_o                (sub_decoder_imm[7]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[7]),
        .use_imm              (sub_decoder_use_imm[7]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[7]),
        .aluop_o              (sub_decoder_aluop[7]),
        .alusel_o             (sub_decoder_alusel[7]),
        .kernel_instr         (sub_decoder_kernel_instr[7]),
        .special_info_o       (sub_decoder_special_info[7])
    );
    decoder_CSR u_decoder_CSR (
        .instr_i              (instr_i),
        .decode_result_valid_o(sub_decoder_valid[8]),
        .reg_read_valid_o     (sub_decoder_reg_read_valid[8]),
        .reg_read_addr_o      (sub_decoder_reg_read_addr[8]),
        .use_imm              (sub_decoder_use_imm[8]),
        .imm_o                (sub_decoder_imm[8]),
        .reg_write_valid_o    (sub_decoder_reg_write_valid[8]),
        .reg_write_addr_o     (sub_decoder_reg_write_addr[8]),
        .aluop_o              (sub_decoder_aluop[8]),
        .alusel_o             (sub_decoder_alusel[8]),
        .kernel_instr         (sub_decoder_kernel_instr[8]),
        .special_info_o       (sub_decoder_special_info[8])
    );
    // Sub-decoder END

    // Generate instruction info, using OR
    always_comb begin : instr_info_comb
        instr_valid = 0;
        instr_use_imm = 0;
        instr_imm = 0;
        instr_aluop = 0;
        instr_alusel = 0;
        instr_reg_read_valid = 0;
        instr_reg_read_addr = 0;
        instr_reg_write_valid = 0;
        instr_reg_write_addr = 0;
        instr_special_info = 0;
        instr_kernel_instr = 0;
        for (integer i = 0; i < SUB_DECODER_NUM; i++) begin
            instr_valid = instr_valid | sub_decoder_valid[i];
            instr_use_imm = instr_use_imm | sub_decoder_use_imm[i];
            instr_imm = instr_imm | sub_decoder_imm[i];
            instr_aluop = instr_aluop | sub_decoder_aluop[i];
            instr_alusel = instr_alusel | sub_decoder_alusel[i];
            instr_reg_write_valid = instr_reg_write_valid | sub_decoder_reg_write_valid[i];
            instr_reg_write_addr = instr_reg_write_addr | sub_decoder_reg_write_addr[i];
            // Generate output to Regfile
            instr_reg_read_valid = instr_reg_read_valid | sub_decoder_reg_read_valid[i];
            instr_reg_read_addr = instr_reg_read_addr | sub_decoder_reg_read_addr[i];

            instr_special_info = instr_special_info | sub_decoder_special_info[i];
            instr_kernel_instr = instr_kernel_instr | sub_decoder_kernel_instr[i];
        end
    end

    // Generate output
    // 只要是 IB 输入的指令，那么一律认为是有效的
    // 如果在 ID 级发生了异常或在此之前就有异常，那么全部认为是 NOP， 但是是有效指令，以便进行异常处理
    assign dispatch_o.instr_info.valid = instr_buffer_i.valid;
    assign dispatch_o.use_imm = instr_valid ? instr_use_imm : 0;
    assign dispatch_o.imm = instr_valid ? instr_imm : 0;
    assign dispatch_o.aluop = instr_valid ? instr_aluop : 0;
    assign dispatch_o.alusel = instr_valid ? instr_alusel : 0;
    assign dispatch_o.reg_write_valid = instr_valid ? instr_reg_write_valid : 0;
    assign dispatch_o.reg_write_addr = instr_valid ? instr_reg_write_addr : 0;
    // Generate output to Regfile
    assign dispatch_o.reg_read_valid = instr_valid ? instr_reg_read_valid : 0;
    assign dispatch_o.reg_read_addr = instr_valid ? instr_reg_read_addr : 0;
    // Generate instr info pack
    assign dispatch_o.instr_info.pc = pc_i;
    assign dispatch_o.instr_info.excp = excp;
    assign dispatch_o.instr_info.excp_num = excp_num;
    assign dispatch_o.instr_info.instr = instr_i;
    assign dispatch_o.instr_info.is_last_in_block = is_last_in_block;
    assign dispatch_o.instr_info.ftq_id = instr_buffer_i.valid ? instr_buffer_i.ftq_id : 0;
    assign dispatch_o.instr_info.special_info = instr_valid ? instr_special_info : 0;


    assign excp_ine = ~instr_valid & instr_buffer_i.valid; // If IB input is valid, but no valid decode result, then INE is triggered
    assign excp_ipe = instr_kernel_instr && (csr_plv == 2'b11);

    assign excp = excp_ipe | instr_syscall | instr_break | instr_buffer_i.excp | excp_ine | has_int;
    assign excp_num = {
        excp_ipe, excp_ine, instr_break, instr_syscall, instr_buffer_i.excp_num[4:1], has_int
    };

endmodule
