
`include "pipeline_defines.sv"

module dispatch #(
    parameter DECODE_WIDTH = 2
) (
    input logic clk,
    input logic rst,

    // <- ID
    input id_dispatch_struct [DECODE_WIDTH-1:0] id_i,

    // <-> Regfile
    output logic [DECODE_WIDTH-1:0][1:0] regfile_reg_read_valid_o,  // Read valid for 2 regs
    output logic [DECODE_WIDTH-1:0][`RegNumLog2*2-1:0] regfile_reg_read_addr_o,  // Read addr, {reg2, reg1}
    input logic [DECODE_WIDTH-1:0][1:0][`RegBus] regfile_reg_read_data_i,  // Read result

    // Dispatch Port
    output dispatch_ex_struct [DECODE_WIDTH-1:0] exe_o
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    generate
        for (genvar i = 0; i < DECODE_WIDTH; i++) begin : reg_read_comb
            always_comb begin
                // Reg read
                regfile_reg_read_valid_o[i] = id_i[i].reg_read_valid;
                regfile_reg_read_addr_o[i]  = id_i[i].reg_read_addr;
            end
        end
    endgenerate

    generate
        for (genvar i = 0; i < DECODE_WIDTH; i++) begin
            always_ff @(posedge clk or negedge rst_n) begin : dispatch_ff
                if (!rst_n) begin
                    exe_o <= 0;
                end else begin

                    // Pass through to EXE 
                    // TODO: add dispatch logic
                    exe_o[i].instr_info <= id_i[i].instr_info;
                    exe_o[i].aluop <= id_i[i].aluop;
                    exe_o[i].alusel <= id_i[i].alusel;
                    exe_o[i].reg_write_addr <= id_i[i].reg_write_addr;
                    exe_o[i].reg_write_valid <= id_i[i].reg_write_valid;
                    exe_o[i].csr_we <= id_i[i].csr_we;
                    exe_o[i].csr_signal <= id_i[i].csr_signal;

                    exe_o[i].oprand1 <= regfile_reg_read_data_i[i][0];
                    exe_o[i].oprand2 <= id_i[i].use_imm ? id_i[i].imm : regfile_reg_read_data_i[i][1];
                    exe_o[i].imm <= id_i[i].imm;
                    exe_o[i].branch_com_result[0] <= regfile_reg_read_data_i[i][0] == regfile_reg_read_data_i[i][1];
                    exe_o[i].branch_com_result[1] <= regfile_reg_read_data_i[i][0] != regfile_reg_read_data_i[i][1];
                    exe_o[i].branch_com_result[2] <= ({~regfile_reg_read_data_i[i][0][31],regfile_reg_read_data_i[i][0][30:0]} < {~regfile_reg_read_data_i[i][0][31],regfile_reg_read_data_i[i][1][30:0]});
                    exe_o[i].branch_com_result[3] <= ({~regfile_reg_read_data_i[i][0][31],regfile_reg_read_data_i[i][0][30:0]} >= {~regfile_reg_read_data_i[i][0][31],regfile_reg_read_data_i[i][1][30:0]});
                    exe_o[i].branch_com_result[4] <= regfile_reg_read_data_i[i][0] < regfile_reg_read_data_i[i][1];
                    exe_o[i].branch_com_result[5] <= regfile_reg_read_data_i[i][0] >= regfile_reg_read_data_i[i][1];
                end
            end
        end
    endgenerate

endmodule
