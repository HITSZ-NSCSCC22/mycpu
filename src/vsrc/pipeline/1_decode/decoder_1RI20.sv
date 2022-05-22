`include "defines.sv"
`include "instr_info.sv"

// decoder_1RI20 is the decoder for 1RI20-type instructions
// 1RI20-type {opcode[7], imm[20] , rd[5]}
// LU12i PCADDU12i
// all combinational circuit
module decoder_1RI20 #(
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
    output logic use_imm,
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

    // 2 Registers
    logic [4:0] rd;
    assign rd = instr[4:0];

    // imm12
    logic [19:0] imm_20;
    assign imm_20 = instr[24:5];

    always_comb begin
        decode_result_valid_o = 1;
        aluop_o = 0;
        alusel_o = 0;
        reg_write_valid_o = 1;
        reg_write_addr_o = rd;
        reg_read_valid_o = 2'b00;
        reg_read_addr_o = 10'b0;
        use_imm = 1'b1;
        imm_o = {imm_20, 12'b0};
        case (instr[31:25])
            `EXE_LU12I_W: begin
                aluop_o  = `EXE_LUI_OP;
                alusel_o = `EXE_RES_MOVE;
            end
            `EXE_PCADDU12I: begin
                aluop_o  = `EXE_PCADD_OP;
                alusel_o = `EXE_RES_MOVE;
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
