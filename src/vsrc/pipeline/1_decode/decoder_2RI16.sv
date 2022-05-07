`include "defines.sv"
`include "instr_info.sv"

// decoder_2RI16 is the decoder for 2RI16-type instructions
// 2RI16-type {opcode[6], imm[16] ,rj[5], rd[5]}
// branch instructions
// all combinational circuit
module decoder_2RI16 #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter GPR_NUM = 32,
    parameter ALU_OP_WIDTH = 8,
    parameter ALU_SEL_WIDTH = 3
) (
    input instr_buffer_info_t instr_info_i,

    // indicates current decoder module result is valid or not
    // 1 means valid
    output logic decode_result_valid_o,

    // GPR read
    // 1 means valid, {rj, rk}
    output logic [1:0] reg_read_valid_o,
    output logic [$clog2(GPR_NUM)*2-1:0] reg_read_addr_o,

    // Generate imm
    // sext.w(imm_16) << 2
    output logic [DATA_WIDTH-1:0] imm_o,

    // GPR write
    // 1 means valid, {rd}
    output logic reg_write_valid_o,
    output logic [$clog2(GPR_NUM)-1:0] reg_write_addr_o,


    // ALU info
    output logic [ ALU_OP_WIDTH-1:0] aluop_o,
    output logic [ALU_SEL_WIDTH-1:0] alusel_o

);

    logic [DATA_WIDTH-1:0] instr;
    assign instr = instr_info_i.instr;

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
        reg_write_valid_o = 0;
        reg_write_addr_o = 0;
        reg_read_valid_o = 2'b11;
        reg_read_addr_o = {rd, rj};
        imm_o = {{14{imm_16[15]}}, imm_16, 2'b0};
        case (instr[31:26])
            `EXE_JIRL: begin
                aluop_o = `EXE_JIRL_OP;
                alusel_o = `EXE_RES_JUMP;
                reg_write_valid_o = 1;
                reg_write_addr_o = rd;
                reg_read_valid_o = 2'b01;
                reg_read_addr_o = {5'b0, rj};
            end
            `EXE_BEQ: begin
                aluop_o  = `EXE_BEQ_OP;
                alusel_o = `EXE_RES_JUMP;
            end
            `EXE_BNE: begin
                aluop_o  = `EXE_BNE_OP;
                alusel_o = `EXE_RES_JUMP;
            end
            `EXE_BLT: begin
                aluop_o  = `EXE_BLT_OP;
                alusel_o = `EXE_RES_JUMP;
            end
            `EXE_BGE: begin
                aluop_o  = `EXE_BGE_OP;
                alusel_o = `EXE_RES_JUMP;
            end
            `EXE_BLTU: begin
                aluop_o  = `EXE_BLTU_OP;
                alusel_o = `EXE_RES_JUMP;
            end
            `EXE_BGEU: begin
                aluop_o  = `EXE_BGEU_OP;
                alusel_o = `EXE_RES_JUMP;
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
