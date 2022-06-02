`include "defines.sv"
`include "instr_info.sv"

// decoder_2R is the decoder for 2R-type instructions
// 2R-type {opcode[22], rj[5], rd[5]}
// mainly TLB instructions
// all combinational circuit
module decoder_2R #(
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

    // TLB instructions do not read GPR

    // TLB instructions do not modify GPR

    // TLB instructions do not use ALU
    output logic use_imm,
    output logic [ALU_OP_WIDTH-1:0] aluop_o

);

    logic [DATA_WIDTH-1:0] instr;
    assign instr   = instr_info_i.instr;
    assign use_imm = 1'b0;

    always_comb begin
        case (instr[31:10])
            `EXE_TLBWR: begin
                decode_result_valid_o = 1;
                aluop_o               = `EXE_TLBWR_OP;
            end
            `EXE_TLBFILL: begin
                decode_result_valid_o = 1;
                aluop_o = `EXE_TLBFILL_OP;

            end
            `EXE_TLBRD: begin
                decode_result_valid_o = 1;
                aluop_o = `EXE_TLBRD_OP;

            end
            `EXE_TLBSRCH: begin
                decode_result_valid_o = 1;
                aluop_o = `EXE_TLBSRCH_OP;
            end

            `EXE_ERTN: begin
                decode_result_valid_o = 1;
                aluop_o = `EXE_ERTN_OP;
            end
            default: begin
                decode_result_valid_o = 0;
                aluop_o = 0;
            end
        endcase
    end

endmodule
