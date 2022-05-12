`include "defines.sv"
`include "instr_info.sv"

// decoder_I26 is the decoder for I26-type instructions
// I26-type {opcode[6], imm[14] ,rj[5], rd[5]}
// for B and BL instructions
// all combinational circuit
module decoder_I26 #(
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

    // B and BL instructions do not read GPR

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


    // imm26
    logic [25:0] imm_26;
    assign imm_26 = {instr[9:0], instr[25:10]};

    always_comb begin
        // Default decode
        decode_result_valid_o = 1;
        reg_write_valid_o = 0;
        reg_write_addr_o = 0;
        imm_o = {{4{imm_26[25]}}, imm_26, 2'b0};
        case (instr[31:26])
            `EXE_B: begin
                aluop_o  = `EXE_B_OP;
                alusel_o = `EXE_RES_JUMP;
            end
            `EXE_BL: begin
                aluop_o = `EXE_BL_OP;
                alusel_o = `EXE_RES_JUMP;
                reg_write_valid_o = 1;
                reg_write_addr_o = 5'b1;
            end
            default: begin
                decode_result_valid_o = 0;
                aluop_o = 0;
                alusel_o = 0;
                imm_o = 0;
            end
        endcase
    end

endmodule