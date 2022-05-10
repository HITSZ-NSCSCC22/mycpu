
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

    // <-> Regfile
    output logic [DECODE_WIDTH-1:0][1:0] regfile_reg_read_valid_o,  // Read valid for 2 regs
    output logic [DECODE_WIDTH-1:0][`RegNumLog2*2-1:0] regfile_reg_read_addr_o,  // Read addr, {reg2, reg1}
    input logic [DECODE_WIDTH-1:0][1:0][`RegBus] regfile_reg_read_data_i,  // Read result

    // <- EXE
    // Data forwarding
    input ex_dispatch_struct ex_data_forward[EXE_STAGE_WIDTH],

    // <- Mem
    // Data forwarding
    input mem_dispatch_struct mem_data_forward[MEM_STAGE_WIDTH],

    //<- Ctrl
    //request for stall
    output logic stallreg_from_dispatch,

    // Dispatch Port
    output dispatch_ex_struct [DECODE_WIDTH-1:0] exe_o
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    //Load relate
    logic pre_load;
    assign pre_load = ((ex_data_forward[1].aluop_i == `EXE_LD_B_OP) ||(ex_data_forward[1].aluop_i == `EXE_LD_H_OP)||
                       (ex_data_forward[1].aluop_i == `EXE_LD_W_OP) ||(ex_data_forward[1].aluop_i == `EXE_ST_B_OP)||
                       (ex_data_forward[1].aluop_i == `EXE_ST_H_OP) ||(ex_data_forward[1].aluop_i == `EXE_ST_W_OP)||
                       (ex_data_forward[1].aluop_i == `EXE_LD_BU_OP)||(ex_data_forward[1].aluop_i == `EXE_LD_HU_OP) ||
                       (ex_data_forward[1].aluop_i == `EXE_LL_OP)   ||(ex_data_forward[1].aluop_i == `EXE_SC_OP)) ||
                      ((ex_data_forward[0].aluop_i == `EXE_LD_B_OP) ||(ex_data_forward[0].aluop_i == `EXE_LD_H_OP)||
                       (ex_data_forward[0].aluop_i == `EXE_LD_W_OP) ||(ex_data_forward[0].aluop_i == `EXE_ST_B_OP)||
                       (ex_data_forward[0].aluop_i == `EXE_ST_H_OP) ||(ex_data_forward[0].aluop_i == `EXE_ST_W_OP)||
                       (ex_data_forward[0].aluop_i == `EXE_LD_BU_OP)||(ex_data_forward[0].aluop_i == `EXE_LD_HU_OP) ||
                       (ex_data_forward[0].aluop_i == `EXE_LL_OP)   ||(ex_data_forward[0].aluop_i == `EXE_SC_OP))? 1'b1 : 1'b0;


    always_comb begin
        if(rst)
            stallreg_from_dispatch = `NoStop;
        else if(pre_load)
            stallreg_from_dispatch = `Stop;
    end


    generate
        for (genvar i = 0; i < DECODE_WIDTH; i++) begin : reg_read_comb
            always_comb begin
                // Reg read
                regfile_reg_read_valid_o[i] = id_i[i].reg_read_valid;
                regfile_reg_read_addr_o[i]  = id_i[i].reg_read_addr;
            end
        end
    endgenerate

    //data relate
    logic [`RegBus] oprand1,oprand2;

      generate
        for (genvar i = 0; i < DECODE_WIDTH; i++)
            always_comb begin 
                if (!rst_n) begin
                    oprand1 = 0; //
                end else begin
                    if(ex_data_forward[1].reg_valid == `WriteEnable && ex_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][4:0])
                        oprand1 = ex_data_forward[1].reg_data;
                    else if(ex_data_forward[0].reg_valid == `WriteEnable && ex_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][4:0])
                        oprand1 = ex_data_forward[0].reg_data;
                    else if(mem_data_forward[1].reg_valid == `WriteEnable && mem_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][4:0])
                        oprand1 = mem_data_forward[1].reg_data;
                    else if(mem_data_forward[0].reg_valid == `WriteEnable && mem_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][4:0])
                        oprand1 = mem_data_forward[0].reg_data;
                    else 
                        oprand1 = regfile_reg_read_data_i[i][0];
                end
            end
    endgenerate

    generate
        for (genvar i = 0; i < DECODE_WIDTH; i++) begin
            always_comb begin 
                if (!rst_n) begin
                    oprand2 = 0; //
                end else begin
                    if(ex_data_forward[1].reg_valid == `WriteEnable && ex_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][4:0])
                        oprand2 = ex_data_forward[1].reg_data;
                    else if(ex_data_forward[0].reg_valid == `WriteEnable && ex_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][4:0])
                        oprand2 = ex_data_forward[0].reg_data;
                    else if(mem_data_forward[1].reg_valid == `WriteEnable && mem_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][4:0])
                        oprand2 = mem_data_forward[1].reg_data;
                    else if(mem_data_forward[0].reg_valid == `WriteEnable && mem_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][4:0])
                        oprand2 = mem_data_forward[0].reg_data;
                    else 
                        oprand2 = id_i[i].use_imm ? id_i[i].imm : regfile_reg_read_data_i[i][1];
                end
            end
        end
    endgenerate            

    generate
        for (genvar i = 0; i < DECODE_WIDTH; i++) begin
            always_ff @(posedge clk or negedge rst_n) begin : dispatch_ff
                if (!rst_n) begin
                    exe_o[i] <= 0; //
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
                    exe_o[i].oprand1 <= oprand1;
                    exe_o[i].oprand2 <= oprand2;

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
