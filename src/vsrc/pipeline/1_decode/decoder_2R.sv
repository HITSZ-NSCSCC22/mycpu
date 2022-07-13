`include "defines.sv"
`include "core_types.sv"
`include "core_config.sv"

// decoder_2R is the decoder for 2R-type instructions
// 2R-type {opcode[22], rj[5], rd[5]}
// mainly TLB instructions
// all combinational circuit
module decoder_2R
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

    output logic use_imm,
    output logic [ALU_OP_WIDTH-1:0] aluop_o,
    output logic [ALU_SEL_WIDTH-1:0] alusel_o,

    // Special info
    output logic kernel_instr,
    output special_info_t special_info_o
);

    logic [DATA_WIDTH-1:0] instr;
    assign instr   = instr_i;
    assign use_imm = 1'b0;

    logic [4:0] rj, rd;
    assign rj = instr[9:5];
    assign rd = instr[4:0];

    always_comb begin
        reg_read_valid_o      = 2'b00;
        reg_read_addr_o       = 0;
        reg_write_valid_o     = 0;
        reg_write_addr_o      = 0;
        alusel_o              = 0;
        aluop_o               = 0;
        kernel_instr          = 0;
        special_info_o        = 0;
        decode_result_valid_o = 0;
        case (instr[31:10])
            `EXE_TLBWR: begin
                decode_result_valid_o       = 1;
                aluop_o                     = `EXE_TLBWR_OP;
                kernel_instr                = 1;
                special_info_o.is_pri       = 1;
                special_info_o.need_refetch = 1;
            end
            `EXE_TLBFILL: begin
                decode_result_valid_o       = 1;
                aluop_o                     = `EXE_TLBFILL_OP;
                kernel_instr                = 1;
                special_info_o.is_pri       = 1;
                special_info_o.need_refetch = 1;
            end
            `EXE_TLBRD: begin
                decode_result_valid_o = 1;
                aluop_o               = `EXE_TLBRD_OP;
                kernel_instr          = 1;
                special_info_o.is_pri = 1;
            end
            `EXE_TLBSRCH: begin
                decode_result_valid_o = 1;
                aluop_o               = `EXE_TLBSRCH_OP;
                kernel_instr          = 1;
                special_info_o.is_pri = 1;
            end
            `EXE_ERTN: begin
                decode_result_valid_o           = 1;
                aluop_o                         = `EXE_ERTN_OP;
                kernel_instr                    = 1;
                special_info_o.redirect         = 1;
                special_info_o.is_pri           = 1;
                special_info_o.not_commit_instr = 1;
                special_info_o.need_refetch     = 1;
            end
            `EXE_RDCNTIDV_W: begin
                decode_result_valid_o = 1;
                alusel_o = `EXE_RES_CSR;
                special_info_o.is_pri = 1;
                if (rd == 0) begin
                    reg_write_valid_o = 1;
                    reg_write_addr_o = rj;
                    aluop_o = `EXE_RDCNTID_OP;
                end else if (rj == 0) begin
                    reg_write_valid_o = 1;
                    reg_write_addr_o = rd;
                    aluop_o = `EXE_RDCNTVL_OP;
                end else decode_result_valid_o = 0;
            end
            `EXE_RDCNTVH_W: begin
                decode_result_valid_o = 1;
                reg_write_valid_o = 1;
                reg_write_addr_o = rd;
                aluop_o = `EXE_RDCNTVH_OP;
                alusel_o = `EXE_RES_CSR;
                special_info_o.is_pri = 1;
            end
            default: begin
            end
        endcase
    end

endmodule
