`include "defines.sv"
`include "core_types.sv"
`include "core_config.sv"

// decoder_2RI14 is the decoder for 2RI14-type instructions
// 2RI14-type {opcode[8], imm[14] ,rj[5], rd[5]}
// for CSR instructions 
// all combinational circuit
module decoder_2RI14
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
    output special_info_t special_info_o
);

    logic [DATA_WIDTH-1:0] instr;
    assign instr = instr_i;

    // 2 Registers
    logic [4:0] rd, rj;
    assign rd = instr[4:0];
    assign rj = instr[9:5];

    // imm14
    logic [13:0] imm_14;
    assign imm_14 = instr[23:10];

    always_comb begin
        decode_result_valid_o = 1;
        reg_write_valid_o     = 1;
        reg_write_addr_o      = rd;
        reg_read_valid_o      = 2'b00;
        reg_read_addr_o       = 10'b0;
        use_imm               = 1'b1;
        imm_o                 = 0;
        special_info_o        = 0;
        case (instr[31:24])
            `EXE_LL_W: begin
                aluop_o = `EXE_LL_OP;
                alusel_o = `EXE_RES_MOVE;
                reg_read_valid_o = 2'b01;
                reg_read_addr_o = {5'b0, rj};
                use_imm = 1'b0;
                imm_o = {{18{imm_14[13]}}, imm_14} << 2;  // Signed Extension and << 2
                special_info_o.mem_load = 1;
                special_info_o.is_pri = 1;
            end
            `EXE_SC_W: begin
                aluop_o = `EXE_SC_OP;
                alusel_o = `EXE_RES_MOVE;
                reg_read_valid_o = 2'b11;
                reg_read_addr_o = {rd, rj};
                use_imm = 1'b0;
                imm_o = {{18{imm_14[13]}}, imm_14} << 2;  // Signed Extension and << 2

                // If LLbit is 1, then SC.W is executed, and is both load and store
                special_info_o.mem_load = 1;
                special_info_o.mem_store = 1;
                special_info_o.is_pri = 1;
            end
            default: begin
                use_imm = 1'b0;
                decode_result_valid_o = 0;
                aluop_o = `EXE_NOP_OP;
                alusel_o = `EXE_RES_NOP;
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
            end
        endcase
    end


endmodule
