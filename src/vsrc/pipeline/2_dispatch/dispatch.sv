
`include "pipeline_defines.sv"

module dispatch #(
    parameter DECODE_WIDTH = 2,
    parameter EXE_STAGE_WIDTH = 2,
    parameter MEM_STAGE_WIDTH = 2
) (
    input logic clk,
    input logic rst,

    // <- ID
    input id_dispatch_struct [DECODE_WIDTH-1:0] id_i,

    // <- Ctrl
    input logic stall,
    input logic flush,

    // <-> Regfile, wire
    output logic [DECODE_WIDTH-1:0][1:0] regfile_reg_read_valid_o,  // Read valid for 2 regs
    output logic [DECODE_WIDTH-1:0][1:0][`RegAddrBus] regfile_reg_read_addr_o,  // Read addr, {reg2, reg1}
    input logic [DECODE_WIDTH-1:0][1:0][`RegBus] regfile_reg_read_data_i,  // Read result

    // <- EXE
    // Data forwarding
    input ex_dispatch_struct ex_data_forward[EXE_STAGE_WIDTH],

    // <- Mem
    // Data forwarding
    input mem_dispatch_struct mem_data_forward[MEM_STAGE_WIDTH],

    // -> Instruction Buffer, wire
    output logic [DECODE_WIDTH-1:0] ib_accept_o,

    // Dispatch Port
    output dispatch_ex_struct [DECODE_WIDTH-1:0] exe_o
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    // Dispatch flag
    logic [EXE_STAGE_WIDTH-1:0] do_we_issue;
    assign ib_accept_o = do_we_issue & {id_i[1].instr_info.valid, id_i[0].instr_info.valid};

    // Stall
    always_comb begin
        if (id_i[1].reg_read_addr[0] == id_i[0].reg_write_addr && id_i[1].reg_read_valid[0] && id_i[0].reg_write_valid) begin
            // If P1 instr read reg1 && P0 instr write reg && reg addr is the same
            // Only P0 is issued
            do_we_issue = 2'b01;
        end else if (id_i[1].reg_read_addr[1] == id_i[0].reg_write_addr && id_i[1].reg_read_valid[1] && id_i[0].reg_write_valid) begin
            // If P1 instr read reg2 && P0 instr write reg && reg addr is the same
            // Only P0 is issued
            do_we_issue = 2'b01;
        end else begin
            do_we_issue = 2'b11;  // No data dependecies, can be issued
        end
    end

    // Reg read, -> Regfile
    generate
        for (genvar i = 0; i < DECODE_WIDTH; i++) begin : reg_read_comb
            always_comb begin
                regfile_reg_read_valid_o[i] = id_i[i].reg_read_valid;
                regfile_reg_read_addr_o[i]  = id_i[i].reg_read_addr;
            end
        end
    endgenerate

    // Data dependecies
    logic [1:0][`RegBus] oprand1, oprand2;

    generate
        for (genvar i = 0; i < DECODE_WIDTH; i++) begin
            always_comb begin
                begin
                    if(ex_data_forward[1].reg_valid == `WriteEnable && ex_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][0] && id_i[i].reg_read_valid[0])
                        oprand1[i] = ex_data_forward[1].reg_data;
                    else if(ex_data_forward[0].reg_valid == `WriteEnable && ex_data_forward[0].reg_addr == regfile_reg_read_addr_o[i][0] && id_i[i].reg_read_valid[0])
                        oprand1[i] = ex_data_forward[0].reg_data;
                    else if(mem_data_forward[1].reg_valid == `WriteEnable && mem_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][0] && id_i[i].reg_read_valid[0])
                        oprand1[i] = mem_data_forward[1].reg_data;
                    else if(mem_data_forward[0].reg_valid == `WriteEnable && mem_data_forward[0].reg_addr == regfile_reg_read_addr_o[i][0] && id_i[i].reg_read_valid[0])
                        oprand1[i] = mem_data_forward[0].reg_data;
                    else oprand1[i] = regfile_reg_read_data_i[i][0];
                end
            end
        end
    endgenerate

    generate
        for (genvar i = 0; i < DECODE_WIDTH; i++) begin
            always_comb begin
                begin
                    if (id_i[i].use_imm) oprand2[i] = id_i[i].imm;
                    else if(ex_data_forward[1].reg_valid == `WriteEnable && ex_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][1] && id_i[i].reg_read_valid[1])
                        oprand2[i] = ex_data_forward[1].reg_data;
                    else if(ex_data_forward[0].reg_valid == `WriteEnable && ex_data_forward[0].reg_addr == regfile_reg_read_addr_o[i][1] && id_i[i].reg_read_valid[1])
                        oprand2[i] = ex_data_forward[0].reg_data;
                    else if(mem_data_forward[1].reg_valid == `WriteEnable && mem_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][1] && id_i[i].reg_read_valid[1])
                        oprand2[i] = mem_data_forward[1].reg_data;
                    else if(mem_data_forward[0].reg_valid == `WriteEnable && mem_data_forward[0].reg_addr == regfile_reg_read_addr_o[i][1] && id_i[i].reg_read_valid[1])
                        oprand2[i] = mem_data_forward[0].reg_data;
                    else oprand2[i] = regfile_reg_read_data_i[i][1];
                end
            end
        end
    endgenerate

    generate
        for (genvar i = 0; i < DECODE_WIDTH; i++) begin
            always_ff @(posedge clk or negedge rst_n) begin : dispatch_ff
                if (!rst_n) begin
                    exe_o[i] <= 0;
                end else if (flush) begin
                    exe_o[i] <= 0;
                end else if (stall) begin
                    // Do nothing, hold output
                end else if (do_we_issue[i] == 0) begin
                    exe_o[i] <= 0;  // Cannot be issued, so do not issue
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
                    exe_o[i].oprand1 <= oprand1[i];
                    exe_o[i].oprand2 <= oprand2[i];

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
