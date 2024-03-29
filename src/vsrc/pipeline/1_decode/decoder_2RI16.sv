`include "defines.sv"
`include "core_types.sv"
`include "core_config.sv"

// decoder_2RI16 is the decoder for 2RI16-type instructions
// 2RI16-type {opcode[6], imm[16] ,rj[5], rd[5]}
// branch instructions
// all combinational circuit
module decoder_2RI16
    import core_types::*;
    import core_config::*;
#(
    parameter ALU_OP_WIDTH  = 8,
    parameter ALU_SEL_WIDTH = 3
) (
    input logic [INSTR_WIDTH-1:0] instr_i,

    // indicates current decoder module result is valid or not
    // 1 means valid
    output logic decode_result_valid_o,

    // GPR read
    // 1 means valid, {rj, rk}
    output logic [1:0] reg_read_valid_o,
    output logic [$clog2(GPR_NUM)*2-1:0] reg_read_addr_o,

    // Generate imm
    // sext.w(imm_16) << 2
    output logic use_imm,
    output logic [DATA_WIDTH-1:0] imm_o,

    // GPR write
    // 1 means valid, {rd}
    output logic reg_write_valid_o,
    output logic [$clog2(GPR_NUM)-1:0] reg_write_addr_o,


    // ALU info
    output logic [ ALU_OP_WIDTH-1:0] aluop_o,
    output logic [ALU_SEL_WIDTH-1:0] alusel_o,

    // Special info
    output logic kernel_instr,
    output special_info_t special_info_o
);

    logic [DATA_WIDTH-1:0] instr;
    assign instr = instr_i;

    // 3 Registers
    logic [4:0] rd, rj;
    assign rd = instr[4:0];
    assign rj = instr[9:5];

    // imm16
    logic [15:0] imm_16;
    assign imm_16 = instr[25:10];

    always_comb begin
        // Default decode
        decode_result_valid_o = 1;
        reg_write_valid_o     = 0;
        reg_write_addr_o      = 0;
        reg_read_valid_o      = 2'b11;
        reg_read_addr_o       = {rd, rj};
        use_imm               = 1'b0;
        imm_o                 = {{14{imm_16[15]}}, imm_16, 2'b0};
        kernel_instr          = 0;
        special_info_o        = 0;
        case (instr[31:26])
            `EXE_JIRL: begin
                aluop_o = `EXE_JIRL_OP;
                alusel_o = `EXE_RES_JUMP;
                reg_write_valid_o = 1;
                reg_write_addr_o = rd;
                reg_read_valid_o = 2'b01;
                reg_read_addr_o = {5'b0, rj};
                special_info_o.is_pri = 1;
                special_info_o.is_branch = 1;
                // Consider 'jirl $r1, $rX, 0' is a function call
                // Consider 'jirl $r0, $r1, 0' is a function call return
                // Other    'jirl $r0, $rX, 0' is not a function call return, but just a relay
                special_info_o.branch_type = (rd == 0 & rj == 1) ? BRANCH_TYPE_RET : 
                                                (rd == 1) ? BRANCH_TYPE_CALL :
                                                BRANCH_TYPE_UNCOND;
            end
            `EXE_BEQ: begin
                aluop_o = `EXE_BEQ_OP;
                alusel_o = `EXE_RES_JUMP;
                special_info_o.is_pri = 1;
                special_info_o.is_branch = 1;
                special_info_o.branch_type = BRANCH_TYPE_COND;
            end
            `EXE_BNE: begin
                aluop_o = `EXE_BNE_OP;
                alusel_o = `EXE_RES_JUMP;
                special_info_o.is_pri = 1;
                special_info_o.is_branch = 1;
                special_info_o.branch_type = BRANCH_TYPE_COND;
            end
            `EXE_BLT: begin
                aluop_o = `EXE_BLT_OP;
                alusel_o = `EXE_RES_JUMP;
                special_info_o.is_pri = 1;
                special_info_o.is_branch = 1;
                special_info_o.branch_type = BRANCH_TYPE_COND;
            end
            `EXE_BGE: begin
                aluop_o = `EXE_BGE_OP;
                alusel_o = `EXE_RES_JUMP;
                special_info_o.is_pri = 1;
                special_info_o.is_branch = 1;
                special_info_o.branch_type = BRANCH_TYPE_COND;
            end
            `EXE_BLTU: begin
                aluop_o = `EXE_BLTU_OP;
                alusel_o = `EXE_RES_JUMP;
                special_info_o.is_pri = 1;
                special_info_o.is_branch = 1;
                special_info_o.branch_type = BRANCH_TYPE_COND;
            end
            `EXE_BGEU: begin
                aluop_o = `EXE_BGEU_OP;
                alusel_o = `EXE_RES_JUMP;
                special_info_o.is_pri = 1;
                special_info_o.is_branch = 1;
                special_info_o.branch_type = BRANCH_TYPE_COND;
            end
            default: begin
                decode_result_valid_o = 0;
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                reg_read_valid_o = 0;
                reg_read_addr_o = 0;
                aluop_o = 0;
                alusel_o = 0;
                imm_o = 0;
            end
        endcase
    end

endmodule
