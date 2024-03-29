`include "defines.sv"
`include "core_types.sv"
`include "core_config.sv"

// decoder_2RI8 is the decoder for 2RI12-type instructions
// 2RI8-type {opcode[14], imm[8] ,rj[5], rd[5]}
// arithmetic instructions & memory instructions
// all combinational circuit
module decoder_2RI8
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
    output special_info_t special_info_o
);

    logic [DATA_WIDTH-1:0] instr;
    assign instr = instr_i;

    // 2 Registers
    logic [4:0] rd, rj;
    assign rd = instr[4:0];
    assign rj = instr[9:5];

    // imm8
    logic [7:0] imm_8;
    assign imm_8 = instr[17:10];

    always_comb begin
        // Default decode
        decode_result_valid_o = 1;
        aluop_o               = 0;
        alusel_o              = 0;
        reg_write_valid_o     = 1;
        reg_write_addr_o      = rd;
        reg_read_valid_o      = 2'b01;
        reg_read_addr_o       = {5'b0, rj};
        use_imm               = 1'b1;
        imm_o                 = {27'b0, imm_8[4:0]};
        special_info_o        = 0;
        case (instr[31:18])
            `EXE_SLLI_W: begin
                aluop_o  = `EXE_SLL_OP;
                alusel_o = `EXE_RES_SHIFT;
            end
            `EXE_SRLI_W: begin
                aluop_o  = `EXE_SRL_OP;
                alusel_o = `EXE_RES_SHIFT;
            end
            `EXE_SRAI_W: begin
                aluop_o  = `EXE_SRA_OP;
                alusel_o = `EXE_RES_SHIFT;
            end
            default: begin
                use_imm = 1'b0;
                decode_result_valid_o = 0;
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                reg_read_valid_o = 0;
                reg_read_addr_o = 0;
                imm_o = 0;
            end
        endcase
    end

endmodule
