`include "defines.sv"
`include "core_types.sv"
`include "core_config.sv"

// decoder_3R is the decoder for 3R-type instructions
// 3R-type {opcode[17], rk[5] ,rj[5], rd[5]}
// arithmetic instructions and break and syscall
// See also "defines.sv"
// all combinational circuit
module decoder_3R
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

    // GPR write
    // 1 means valid, {rd}
    output logic reg_write_valid_o,
    output logic [$clog2(GPR_NUM)-1:0] reg_write_addr_o,

    // Only invtlb used imm
    output logic use_imm,
    output logic [DATA_WIDTH-1:0] imm_o,

    // ALU info
    output logic [ ALU_OP_WIDTH-1:0] aluop_o,
    output logic [ALU_SEL_WIDTH-1:0] alusel_o,

    // Special, 1 means valid
    output logic instr_break,
    output logic instr_syscall,

    // Special info
    output logic kernel_instr,
    output special_info_t special_info_o
);

    logic [DATA_WIDTH-1:0] instr;
    assign instr = instr_i;

    // 3 Registers
    logic [4:0] rd, rk, rj;
    assign rd = instr[4:0];
    assign rj = instr[9:5];
    assign rk = instr[14:10];

    always_comb begin
        // Default decode
        decode_result_valid_o = 1;
        aluop_o               = 0;
        alusel_o              = 0;
        reg_write_valid_o     = 1;
        reg_write_addr_o      = rd;
        reg_read_valid_o      = 2'b11;
        reg_read_addr_o       = {rk, rj};
        use_imm               = 1'b0;
        imm_o                 = 0;
        instr_break           = 0;
        instr_syscall         = 0;
        kernel_instr          = 0;
        special_info_o        = 0;
        case (instr[31:15])
            // These two do not need GPR
            `EXE_BREAK: begin
                aluop_o                         = `EXE_BREAK_OP;
                reg_write_valid_o               = 0;
                reg_write_addr_o                = 0;
                reg_read_valid_o                = 2'b00;
                reg_read_addr_o                 = 0;
                instr_break                     = 1;
                special_info_o.redirect         = 1;
                special_info_o.is_pri           = 1;
                special_info_o.not_commit_instr = 1;
            end
            `EXE_SYSCALL: begin
                aluop_o                         = `EXE_SYSCALL_OP;
                reg_write_valid_o               = 0;
                reg_write_addr_o                = 0;
                reg_read_valid_o                = 2'b00;
                reg_read_addr_o                 = 0;
                instr_syscall                   = 1;
                special_info_o.redirect         = 1;
                special_info_o.is_pri           = 1;
                special_info_o.not_commit_instr = 1;
            end
            `EXE_ADD_W: begin
                aluop_o  = `EXE_ADD_OP;
                alusel_o = `EXE_RES_ARITH;
            end
            `EXE_SUB_W: begin
                aluop_o  = `EXE_SUB_OP;
                alusel_o = `EXE_RES_ARITH;
            end
            `EXE_SLT: begin
                aluop_o  = `EXE_SLT_OP;
                alusel_o = `EXE_RES_ARITH;
            end
            `EXE_SLTU: begin
                aluop_o  = `EXE_SLTU_OP;
                alusel_o = `EXE_RES_ARITH;
            end
            `EXE_NOR: begin
                aluop_o  = `EXE_NOR_OP;
                alusel_o = `EXE_RES_LOGIC;
            end
            `EXE_AND: begin
                aluop_o  = `EXE_AND_OP;
                alusel_o = `EXE_RES_LOGIC;
            end
            `EXE_OR: begin
                aluop_o  = `EXE_OR_OP;
                alusel_o = `EXE_RES_LOGIC;
            end
            `EXE_XOR: begin
                aluop_o  = `EXE_XOR_OP;
                alusel_o = `EXE_RES_LOGIC;
            end
            `EXE_ORN: begin
                aluop_o  = `EXE_ORN_OP;
                alusel_o = `EXE_RES_LOGIC;
            end
            `EXE_ANDN: begin
                aluop_o  = `EXE_ANDN_OP;
                alusel_o = `EXE_RES_LOGIC;
            end
            `EXE_SLL_W: begin
                aluop_o  = `EXE_SLL_OP;
                alusel_o = `EXE_RES_SHIFT;
            end
            `EXE_SRL_W: begin
                aluop_o  = `EXE_SRL_OP;
                alusel_o = `EXE_RES_SHIFT;
            end
            `EXE_SRA_W: begin
                aluop_o  = `EXE_SRA_OP;
                alusel_o = `EXE_RES_SHIFT;
            end
            `EXE_MUL_W: begin
                aluop_o               = `EXE_MUL_OP;
                alusel_o              = `EXE_RES_ARITH;
                special_info_o.is_pri = 1;
            end
            `EXE_MULH_W: begin
                aluop_o               = `EXE_MULH_OP;
                alusel_o              = `EXE_RES_ARITH;
                special_info_o.is_pri = 1;
            end
            `EXE_MULH_WU: begin
                aluop_o               = `EXE_MULHU_OP;
                alusel_o              = `EXE_RES_ARITH;
                special_info_o.is_pri = 1;
            end
            `EXE_DIV_W: begin
                aluop_o               = `EXE_DIV_OP;
                alusel_o              = `EXE_RES_ARITH;
                special_info_o.is_pri = 1;
            end
            `EXE_DIV_WU: begin
                aluop_o               = `EXE_DIVU_OP;
                alusel_o              = `EXE_RES_ARITH;
                special_info_o.is_pri = 1;
            end
            `EXE_MOD_W: begin
                aluop_o               = `EXE_MOD_OP;
                alusel_o              = `EXE_RES_ARITH;
                special_info_o.is_pri = 1;
            end
            `EXE_MOD_WU: begin
                aluop_o               = `EXE_MODU_OP;
                alusel_o              = `EXE_RES_ARITH;
                special_info_o.is_pri = 1;
            end
            `EXE_IDLE: begin
                aluop_o                         = `EXE_IDLE_OP;
                alusel_o                        = `EXE_RES_NOP;
                special_info_o.redirect         = 1;
                special_info_o.is_pri           = 1;
                special_info_o.not_commit_instr = 1;
            end
            `EXE_DBAR, `EXE_IBAR: begin
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                reg_read_valid_o = 2'b00;
                reg_read_addr_o = 0;
                use_imm = 1'b0;
                imm_o = 0;
                aluop_o = `EXE_NOP_OP;
                alusel_o = `EXE_RES_NOP;
                special_info_o.need_refetch = 1;
            end
            `EXE_INVTLB: begin
                aluop_o = `EXE_INVTLB_OP;
                alusel_o = `EXE_RES_NOP;
                // instr[4:0] as imm, not reg id
                use_imm = 0;
                imm_o = {27'b0, instr[4:0]};
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                special_info_o.is_pri = 1;
                special_info_o.need_refetch = 1;
            end
            default: begin  // Means no match in the current decoder
                decode_result_valid_o = 0;
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                reg_read_valid_o = 0;
                reg_read_addr_o = 0;
            end
        endcase
    end

endmodule
