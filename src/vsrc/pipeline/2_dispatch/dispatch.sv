
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
    output logic stallreq,
    input  logic stall,
    input  logic flush,

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

    //<-> CSR
    //get wdata from csr
    output [13:0] csr_read_addr,
    input [`RegBus] csr_data,

    // -> Instruction Buffer, wire
    output logic [DECODE_WIDTH-1:0] ib_accept_o,

    // Dispatch Port
    output dispatch_ex_struct [DECODE_WIDTH-1:0] exe_o
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    logic [`AluSelBus] alusel_i[2];
    assign alusel_i[0]   = id_i[0].alusel;
    assign alusel_i[1]   = id_i[1].alusel;

    logic [`AluOpBus] aluop_i[2];
    assign aluop_i[0] = id_i[0].aluop;
    assign aluop_i[1] = id_i[1].aluop;

    logic csr_op[2];
    assign csr_op[0] = aluop_i[0] == `EXE_CSRWR_OP | aluop_i[0] == `EXE_CSRRD_OP | aluop_i[0] == `EXE_CSRXCHG_OP;
    assign csr_op[1] = aluop_i[1] == `EXE_CSRWR_OP | id_i[1].aluop == `EXE_CSRRD_OP | id_i[1].aluop == `EXE_CSRXCHG_OP;

    //assume two csr write instr not come together
    //assign csr_read_addr = id_i[0].imm[13:0] | id_i[1].imm[13:0];
    assign csr_read_addr = csr_op[0] ? id_i[0].imm[13:0] : csr_op[1] ? id_i[1].imm[13:0] : 14'b0;

    logic is_both_mem_instr;
    assign is_both_mem_instr = alusel_i[0] == `EXE_RES_LOAD_STORE && alusel_i[1] == `EXE_RES_LOAD_STORE;

    // Dispatch flag
    logic [EXE_STAGE_WIDTH-1:0] do_we_issue;
    logic [EXE_STAGE_WIDTH-1:0] issue_valid;
    assign issue_valid = do_we_issue & {id_i[1].instr_info.valid, id_i[0].instr_info.valid};
    // If stall, tell IB no more instructions can be accepted
    logic [DECODE_WIDTH-1:0] instr_valid;  // For observability
    always_comb begin
        for (integer i = 0; i < DECODE_WIDTH; i++) begin
            instr_valid[i] = id_i[i].instr_info.valid;
        end
    end
    assign ib_accept_o = stall ? 0 :do_we_issue & {id_i[1].instr_info.valid, id_i[0].instr_info.valid};

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
        end else if (is_both_mem_instr) begin
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
                    if(ex_data_forward[1].reg_valid == `WriteEnable && ex_data_forward[1].reg_addr == regfile_reg_read_addr_o[i][1] && id_i[i].reg_read_valid[1])
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
                end else if (issue_valid[i]) begin

                    // Pass through to EXE 
                    // TODO: add dispatch logic
                    exe_o[i].instr_info <= id_i[i].instr_info;
                    exe_o[i].aluop <= id_i[i].aluop;
                    exe_o[i].alusel <= id_i[i].alusel;
                    exe_o[i].reg_write_addr <= id_i[i].reg_write_addr;
                    exe_o[i].reg_write_valid <= id_i[i].reg_write_valid;

                    exe_o[i].oprand1 <= oprand1[i];
                    exe_o[i].oprand2 <= id_i[i].use_imm ? id_i[i].imm : oprand2[i];

                    exe_o[i].imm <= id_i[i].imm;
                    exe_o[i].branch_com_result[0] <= oprand1[i] == oprand2[i];
                    exe_o[i].branch_com_result[1] <= oprand1[i] != oprand2[i];
                    exe_o[i].branch_com_result[2] <= ({~oprand1[i][31],oprand1[i][30:0]} < {~oprand2[i][31],oprand2[i][30:0]});
                    exe_o[i].branch_com_result[3] <= ({~oprand1[i][31],oprand1[i][30:0]} >= {~oprand2[i][31],oprand2[i][30:0]});
                    exe_o[i].branch_com_result[4] <= oprand1[i] < oprand2[i];
                    exe_o[i].branch_com_result[5] <= oprand1[i] >= oprand2[i];

                    exe_o[i].excp <= id_i[i].excp;
                    exe_o[i].excp_num <= id_i[i].excp_num;
                    exe_o[i].refetch <= id_i[i].refetch;
                    
                    exe_o[i].csr_signal.we <= csr_op[i];
                    exe_o[i].csr_signal.addr <= id_i[i].imm[13:0];
                    exe_o[i].csr_signal.data <= oprand1[0];
                    exe_o[i].csr_reg_data <= csr_data;
                end else begin
                    exe_o[i] <= 0;  // Cannot be issued, so do not issue
                end
            end
        end
    endgenerate

endmodule
