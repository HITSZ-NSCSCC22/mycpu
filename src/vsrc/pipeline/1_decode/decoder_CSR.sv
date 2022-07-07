`include "defines.sv"
`include "core_types.sv"
`include "core_config.sv"

// decoder_CSR is the decoder for CSR instructions
// CSR {opcode[8], csr_num[14] ,rj[5], rd[5]}
// CSR instructions
// all combinational circuit
module decoder_CSR
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
    logic [13:0] csr_num;
    assign csr_num = instr[23:10];

    always_comb begin
        // Default decode
        decode_result_valid_o = 1;
        reg_write_valid_o     = 1;
        reg_write_addr_o      = rd;
        reg_read_valid_o      = 2'b00;
        reg_read_addr_o       = 10'b0;
        use_imm               = 1'b0;
        imm_o                 = {18'b0, csr_num};
        kernel_instr          = 0;
        special_info_o        = 0;
        case (instr[31:24])
            `EXE_SPECIAL: begin
                case (rj)
                    `EXE_CSRRD: begin
                        aluop_o = `EXE_CSRRD_OP;
                        alusel_o = `EXE_RES_CSR;
                        special_info_o.is_pri = 1;
                        special_info_o.is_csr = 1;
                        special_info_o.csr_rstat = csr_num == 5;
                        kernel_instr = 1;
                    end
                    `EXE_CSRWR: begin
                        aluop_o = `EXE_CSRWR_OP;
                        alusel_o = `EXE_RES_CSR;
                        reg_read_valid_o = 2'b01;
                        reg_read_addr_o = {5'b0, rd};
                        special_info_o.is_pri = 1;
                        special_info_o.is_csr = 1;
                        special_info_o.csr_rstat = csr_num == 5;
                        special_info_o.need_refetch = 1;  // May change mode or trigger soft intrpt
                        kernel_instr = 1;
                    end
                    default: begin  // EXE_CSRXCHG
                        aluop_o = `EXE_CSRXCHG_OP;
                        alusel_o = `EXE_RES_CSR;
                        reg_read_valid_o = 2'b11;
                        reg_read_addr_o = {rj, rd};
                        special_info_o.is_pri = 1;
                        special_info_o.is_csr = 1;
                        special_info_o.csr_rstat = csr_num == 5;
                        special_info_o.need_refetch = 1;  // May change mode
                        kernel_instr = 1;
                    end
                endcase
            end
            default: begin
                decode_result_valid_o = 0;
                aluop_o = 0;
                alusel_o = 0;
                reg_write_valid_o = 0;
                reg_write_addr_o = 0;
                imm_o = 0;
            end
        endcase
    end

endmodule
