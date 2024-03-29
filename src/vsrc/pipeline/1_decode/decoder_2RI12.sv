`include "defines.sv"
`include "core_types.sv"
`include "core_config.sv"

// decoder_2RI12 is the decoder for 2RI12-type instructions
// 2RI12-type {opcode[10], imm[12] ,rj[5], rd[5]}
// arithmetic instructions & memory instructions
// all combinational circuit
module decoder_2RI12
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
    output logic kernel_instr,
    output special_info_t special_info_o
);

    logic [DATA_WIDTH-1:0] instr;
    assign instr = instr_i;

    // 2 Registers
    logic [4:0] rd, rj;
    assign rd = instr[4:0];
    assign rj = instr[9:5];

    // imm12
    logic [11:0] imm_12;
    assign imm_12 = instr[21:10];

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
        imm_o                 = 0;
        kernel_instr          = 0;
        special_info_o        = 0;
        case (instr[31:22])
            `EXE_SLTI: begin
                aluop_o  = `EXE_SLT_OP;
                alusel_o = `EXE_RES_ARITH;
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
            end
            `EXE_SLTUI: begin
                aluop_o  = `EXE_SLTU_OP;
                alusel_o = `EXE_RES_ARITH;
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
            end
            `EXE_ADDI_W: begin
                aluop_o  = `EXE_ADD_OP;
                alusel_o = `EXE_RES_ARITH;
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
            end
            `EXE_ANDI: begin
                aluop_o  = `EXE_AND_OP;
                alusel_o = `EXE_RES_LOGIC;
                imm_o    = {20'b0, imm_12};  // Zero Extension
            end
            `EXE_ORI: begin
                aluop_o  = `EXE_OR_OP;
                alusel_o = `EXE_RES_LOGIC;
                imm_o    = {20'b0, imm_12};  // Zero Extension
            end
            `EXE_XORI: begin
                aluop_o  = `EXE_XOR_OP;
                alusel_o = `EXE_RES_LOGIC;
                imm_o    = {20'b0, imm_12};  // Zero Extension
            end
            `EXE_LD_B: begin
                use_imm = 1'b0;
                aluop_o  = `EXE_LD_B_OP;
                alusel_o = `EXE_RES_LOAD_STORE;
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                special_info_o.mem_load = 1;
                special_info_o.mem_b_op = 1;
            end
            `EXE_LD_H: begin
                use_imm = 1'b0;
                aluop_o  = `EXE_LD_H_OP;
                alusel_o = `EXE_RES_LOAD_STORE;
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                special_info_o.mem_load = 1;
                special_info_o.mem_h_op = 1;
            end
            `EXE_LD_W: begin
                use_imm = 1'b0;
                aluop_o  = `EXE_LD_W_OP;
                alusel_o = `EXE_RES_LOAD_STORE;
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                special_info_o.mem_load = 1;
            end
            `EXE_ST_B: begin
                use_imm = 1'b0;
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                aluop_o  = `EXE_ST_B_OP;
                alusel_o = `EXE_RES_LOAD_STORE;
                reg_write_valid_o = 0;
                reg_read_valid_o = 2'b11;
                reg_read_addr_o = {rd, rj};
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                special_info_o.mem_store = 1;
                special_info_o.mem_b_op = 1;
            end
            `EXE_ST_H: begin
                use_imm = 1'b0;
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                aluop_o  = `EXE_ST_H_OP;
                alusel_o = `EXE_RES_LOAD_STORE;
                reg_write_valid_o = 0;
                reg_read_valid_o = 2'b11;
                reg_read_addr_o = {rd, rj};
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                special_info_o.mem_store = 1;
                special_info_o.mem_h_op = 1;
            end
            `EXE_ST_W: begin
                use_imm = 1'b0;
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                aluop_o  = `EXE_ST_W_OP;
                alusel_o = `EXE_RES_LOAD_STORE;
                reg_write_valid_o = 0;
                reg_read_valid_o = 2'b11;
                reg_read_addr_o = {rd, rj};
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                special_info_o.mem_store = 1;
            end
            `EXE_LD_BU: begin
                use_imm = 1'b0;
                aluop_o  = `EXE_LD_BU_OP;
                alusel_o = `EXE_RES_LOAD_STORE;
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                special_info_o.mem_load = 1;
                special_info_o.mem_b_op = 1;
            end
            `EXE_LD_HU: begin
                use_imm = 1'b0;
                aluop_o  = `EXE_LD_HU_OP;
                alusel_o = `EXE_RES_LOAD_STORE;
                imm_o    = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                special_info_o.mem_load = 1;
                special_info_o.mem_h_op = 1;
            end
            `EXE_PRELD: begin
                use_imm = 1'b0;
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                reg_read_valid_o = 0;
                reg_read_addr_o = 0;
                aluop_o = `EXE_NOP_OP;
                alusel_o = `EXE_RES_NOP;
            end
            `EXE_CACOP: begin
                reg_write_valid_o           = 0;
                reg_write_addr_o            = 0;
                reg_read_valid_o            = 2'b01;
                reg_read_addr_o             = {5'b0, rj};
                use_imm                     = 1'b1;
                aluop_o                     = `EXE_CACOP_OP;
                alusel_o                    = `EXE_RES_NOP;
                imm_o                       = {{20{imm_12[11]}}, imm_12};  // Signed Extension
                kernel_instr                = 1;
                special_info_o.is_pri       = 1;
                special_info_o.need_refetch = 1;  // CACOP may invalid ICache
            end
            default: begin
                use_imm = 1'b0;
                decode_result_valid_o = 0;
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                reg_read_valid_o = 0;
                reg_read_addr_o = 0;
            end
        endcase
    end

endmodule
