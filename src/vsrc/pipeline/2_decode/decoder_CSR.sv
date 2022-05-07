`include "defines.sv"
`include "instr_info.sv"

// decoder_CSR is the decoder for CSR instructions
// CSR {opcode[8], csr_num[14] ,rj[5], rd[5]}
// CSR instructions
// all combinational circuit
module decoder_CSR #(
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
    output logic [DATA_WIDTH-1:0] imm_o,

    // GPR write
    // 1 means valid, {rd}
    output logic reg_write_valid_o,
    output logic [$clog2(GPR_NUM)-1:0] reg_write_addr_o,


    // ALU info
    output logic [ ALU_OP_WIDTH-1:0] aluop_o

);

    logic [DATA_WIDTH-1:0] instr;
    assign instr = instr_info_i.instr;

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
        reg_write_valid_o = 1;
        reg_write_addr_o = rd;
        reg_read_valid_o = 2'b00;
        reg_read_addr_o = 10'b0;
        imm_o = {18'b0,csr_num};
        case (instr[31:24])
            `EXE_SPECIAL:begin
                case (rj)
                    `EXE_CSRRD:begin
                        aluop_o = `EXE_CSRRD_OP;
                    end 
                    `EXE_CSRWR:begin
                        aluop_o = `EXE_CSRWR_OP;
                        reg_read_valid_o = 2'b01;
                        reg_read_addr_o = {5'b0,rd};
                    end
                    default:begin // EXE_CSRXCHG
                        aluop_o = `EXE_CSRXCHG_OP;
                        reg_read_valid_o = 2'b11;
                        reg_read_addr_o = {rj,rd};
                    end 
                endcase
            end
            default: begin
                decode_result_valid_o = 0;
            end
        endcase
    end

endmodule