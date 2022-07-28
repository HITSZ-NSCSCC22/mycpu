`include "core_config.sv"
`include "core_types.sv"

module dispatch
    import core_types::*;
    import core_config::*;
(
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
    input data_forward_t [ISSUE_WIDTH-1:0] ex_data_forward_i,
    input data_forward_t [ISSUE_WIDTH-1:0] mem1_data_forward_i,
    input data_forward_t [ISSUE_WIDTH-1:0] mem2_data_forward_i,
    input data_forward_t [ISSUE_WIDTH-1:0] wb_data_forward_i,

    //<-> CSR
    //get wdata from csr
    output [13:0] csr_read_addr,
    input [`RegBus] csr_data,

    // -> Instruction Buffer, wire
    output logic [DECODE_WIDTH-1:0] ib_accept_o,

    // Dispatch Port, -> EXE
    output dispatch_ex_struct [DECODE_WIDTH-1:0] exe_o,

    // PMU
    output logic [1:0] pmu_dispatch_backend_nop,
    output logic [1:0] pmu_dispatch_frontend_nop,
    output logic pmu_dispatch_single_issue,
    output logic [1:0] pmu_dispatch_datadep_nop,
    output logic [1:0] pmu_dispatch_instr_cnt
);

    // Reset signal
    logic rst_n;

    logic [`AluOpBus] aluop_i[2];

    logic single_issue;
    logic is_both_mem_instr;
    logic [ISSUE_WIDTH-1:0] do_we_issue;
    // issue condition check
    logic [ISSUE_WIDTH-1:0] data_dep_check;
    logic [ISSUE_WIDTH-1:0] single_issue_check;
    logic [ISSUE_WIDTH-1:0] rreg_avail_check;
    logic [DECODE_WIDTH-1:0] instr_exists_check;
    // Final decision
    logic [ISSUE_WIDTH-1:0] issue_valid;

    logic pri_op[2];

    logic csr_op[2];
    // Read oprands
    logic [ISSUE_WIDTH-1:0][1:0][DATA_WIDTH-1:0] oprands;
    // Reg data available
    logic [GPR_NUM-1:0] regs_available;
    logic [ISSUE_WIDTH-1:0] issue_wreg;
    logic [ISSUE_WIDTH-1:0][`RegAddrBus] issue_wreg_addr;

    assign rst_n = ~rst;

    assign aluop_i[0] = id_i[0].aluop;
    assign aluop_i[1] = id_i[1].aluop;

    assign pri_op[0] = id_i[0].instr_info.special_info.is_pri;
    assign pri_op[1] = id_i[1].instr_info.special_info.is_pri;

    assign csr_op[0] = id_i[0].instr_info.special_info.is_csr;
    assign csr_op[1] = id_i[1].instr_info.special_info.is_csr;

    // csr related instrution is single issued
    assign csr_read_addr = csr_op[0] ? id_i[0].imm[13:0] : csr_op[1] ? id_i[1].imm[13:0] : 14'b0;

    // Force most branch, mem, privilege instr to issue only 1 instr per cycle
    assign is_both_mem_instr = id_i[0].instr_info.special_info.mem_load | id_i[0].instr_info.special_info.mem_store | id_i[1].instr_info.special_info.mem_load | id_i[1].instr_info.special_info.mem_store;



    always_comb begin
        for (integer i = 0; i < ISSUE_WIDTH; i++) begin
            issue_wreg[i] = id_i[i].reg_write_valid;
            issue_wreg_addr[i] = id_i[i].reg_write_addr;
        end
    end
    // Detect reg availability using a [GPR_NUM-1:0] register
    // this always block is written in "override" flavor to mitigate following conditions:
    // 1. instr in MEM2 has regX data_valid, so instr in EX depend on regX is issued a cycle before, but also uses regX and without data_valid
    //    so should not issue instructions now, since regX is considered not ready
    always_ff @(posedge clk) begin
        if (!rst_n) regs_available <= {GPR_NUM{1'b1}};
        else if (flush) regs_available <= {GPR_NUM{1'b1}};
        else begin
            // WB data available
            for (integer i = 0; i < ISSUE_WIDTH; i++) begin
                if (wb_data_forward_i[i].wreg & wb_data_forward_i[i].data_valid)
                    regs_available[wb_data_forward_i[i].wreg_addr] <= 1;
                else if (wb_data_forward_i[i].wreg & ~wb_data_forward_i[i].data_valid)
                    regs_available[wb_data_forward_i[i].wreg_addr] <= 0;
            end
            // MEM2 data available
            for (integer i = 0; i < ISSUE_WIDTH; i++) begin
                if (mem2_data_forward_i[i].wreg & mem2_data_forward_i[i].data_valid)
                    regs_available[mem2_data_forward_i[i].wreg_addr] <= 1;
                else if (mem2_data_forward_i[i].wreg & ~mem2_data_forward_i[i].data_valid)
                    regs_available[mem2_data_forward_i[i].wreg_addr] <= 0;
            end
            // MEM1 data available
            for (integer i = 0; i < ISSUE_WIDTH; i++) begin
                if (mem1_data_forward_i[i].wreg & mem1_data_forward_i[i].data_valid)
                    regs_available[mem1_data_forward_i[i].wreg_addr] <= 1;
                else if (mem1_data_forward_i[i].wreg & ~mem1_data_forward_i[i].data_valid)
                    regs_available[mem1_data_forward_i[i].wreg_addr] <= 0;
            end
            // EX data available
            for (integer i = 0; i < ISSUE_WIDTH; i++) begin
                if (ex_data_forward_i[i].wreg & ex_data_forward_i[i].data_valid)
                    regs_available[ex_data_forward_i[i].wreg_addr] <= 1;
                else if (ex_data_forward_i[i].wreg & ~ex_data_forward_i[i].data_valid)
                    regs_available[ex_data_forward_i[i].wreg_addr] <= 0;
            end
            // Set unavailable when issued
            for (integer issue_idx = 0; issue_idx < ISSUE_WIDTH; issue_idx++) begin
                if (issue_wreg[issue_idx] & issue_valid[issue_idx] & ~stall & id_i[issue_idx].instr_info.special_info.mem_load)
                    regs_available[issue_wreg_addr[issue_idx]] <= 0;
            end
            // $r0 is always available
            regs_available[0] <= 1;
        end
    end
    assign ib_accept_o = stall ? 0 : 
                        do_we_issue == 2'b01 ? do_we_issue | ~instr_exists_check : do_we_issue;

    // Instruction exists check
    always_comb begin
        for (integer i = 0; i < DECODE_WIDTH; i++) begin
            instr_exists_check[i] = id_i[i].instr_info.valid;
        end
    end
    // Reg read available check
    assign rreg_avail_check[0] = regs_available[id_i[0].reg_read_addr[0]] & regs_available[id_i[0].reg_read_addr[1]] ;
    assign rreg_avail_check[1] = regs_available[id_i[1].reg_read_addr[0]] & regs_available[id_i[1].reg_read_addr[1]] & rreg_avail_check[0];
    // Data dependency check 
    always_comb begin
        if (id_i[1].reg_read_addr[0] == id_i[0].reg_write_addr && id_i[1].reg_read_valid[0] && id_i[0].reg_write_valid) begin
            data_dep_check = 2'b01;
        end else if (id_i[1].reg_read_addr[1] == id_i[0].reg_write_addr && id_i[1].reg_read_valid[1] && id_i[0].reg_write_valid) begin
            data_dep_check = 2'b01;
        end else data_dep_check = 2'b11;
    end
    // Single issue check
    assign single_issue = pri_op[0]| pri_op[1] | csr_op[0] | csr_op[1] | is_both_mem_instr | id_i[0].instr_info.excp | id_i[1].instr_info.excp;
    assign single_issue_check = single_issue ? 2'b01 : 2'b11;
    // Do we issue ?
    assign do_we_issue = single_issue_check & data_dep_check & rreg_avail_check;
    // Final decision
    assign issue_valid = do_we_issue & instr_exists_check;


    // Reg read, -> Regfile
    generate
        for (genvar i = 0; i < DECODE_WIDTH; i++) begin : reg_read_comb
            always_comb begin
                regfile_reg_read_valid_o[i] = id_i[i].reg_read_valid;
                regfile_reg_read_addr_o[i]  = id_i[i].reg_read_addr;
            end
        end
    endgenerate



    generate
        for (genvar issue_idx = 0; issue_idx < ISSUE_WIDTH; issue_idx++) begin : issue_gen
            for (genvar op_idx = 0; op_idx < 2; op_idx++) begin : op_gen
                always_comb begin
                    begin
                        // Noraml read regfile
                        oprands[issue_idx][op_idx] = regfile_reg_read_data_i[issue_idx][op_idx];
                        // WB data forward overide
                        for (integer i = 0; i < ISSUE_WIDTH; i++) begin
                            if (wb_data_forward_i[i].wreg && wb_data_forward_i[i].wreg_addr == regfile_reg_read_addr_o[issue_idx][op_idx])
                                oprands[issue_idx][op_idx] = wb_data_forward_i[i].wreg_data;
                        end
                        // MEM2 data forward overide
                        for (integer i = 0; i < ISSUE_WIDTH; i++) begin
                            if (mem2_data_forward_i[i].wreg && mem2_data_forward_i[i].wreg_addr == regfile_reg_read_addr_o[issue_idx][op_idx])
                                oprands[issue_idx][op_idx] = mem2_data_forward_i[i].wreg_data;
                        end
                        // MEM1 data forward overide
                        for (integer i = 0; i < ISSUE_WIDTH; i++) begin
                            if (mem1_data_forward_i[i].wreg && mem1_data_forward_i[i].wreg_addr == regfile_reg_read_addr_o[issue_idx][op_idx])
                                oprands[issue_idx][op_idx] = mem1_data_forward_i[i].wreg_data;
                        end
                        // EX data forward overide
                        for (integer i = 0; i < ISSUE_WIDTH; i++) begin
                            if (ex_data_forward_i[i].wreg && ex_data_forward_i[i].wreg_addr == regfile_reg_read_addr_o[issue_idx][op_idx])
                                oprands[issue_idx][op_idx] = ex_data_forward_i[i].wreg_data;
                        end
                        // $r0 is always 0
                        if (regfile_reg_read_addr_o[issue_idx][op_idx] == 0)
                            oprands[issue_idx][op_idx] = 0;
                    end
                end
            end
        end
    endgenerate

    generate
        for (genvar i = 0; i < ISSUE_WIDTH; i++) begin
            always_ff @(posedge clk) begin : dispatch_ff
                if (!rst_n) begin
                    exe_o[i] <= 0;
                end else if (flush) begin
                    exe_o[i] <= 0;
                end else if (stall) begin
                    // Do nothing, hold output
                end else if (issue_valid[i]) begin

                    // Pass through to EXE 
                    exe_o[i].instr_info <= id_i[i].instr_info;
                    exe_o[i].use_imm <= id_i[i].use_imm;
                    exe_o[i].read_reg_addr <= {
                        id_i[i].reg_read_valid[1] ? regfile_reg_read_addr_o[i][1] : 5'b0,
                        id_i[i].reg_read_valid[0] ? regfile_reg_read_addr_o[i][0] : 5'b0
                    };
                    exe_o[i].aluop <= id_i[i].aluop;
                    exe_o[i].alusel <= id_i[i].alusel;
                    exe_o[i].reg_write_addr <= id_i[i].reg_write_addr;
                    exe_o[i].reg_write_valid <= id_i[i].reg_write_valid;

                    exe_o[i].oprand1 <= oprands[i][0];
                    exe_o[i].oprand2 <= id_i[i].use_imm ? id_i[i].imm : oprands[i][1];
                    exe_o[i].imm <= id_i[i].imm;

                    exe_o[i].csr_signal.we <= csr_op[i] && aluop_i[i] != `EXE_CSRRD_OP;
                    exe_o[i].csr_signal.addr <= id_i[i].imm[13:0];
                    exe_o[i].csr_signal.data <= oprands[i][0];
                    exe_o[i].csr_reg_data <= csr_data;
                end else begin
                    // Cannot be issued, so do not issue,just issue the excp
                    exe_o[i] <= 0;  //.excp <= id_i[i].excp;
                    //exe_o[i].excp_num <= id_i[i].excp_num; 
                end
            end
        end
    endgenerate

    // PMU
    assign pmu_dispatch_single_issue = single_issue & ~stall & ~flush & instr_exists_check[1] & data_dep_check[1] & rreg_avail_check[1];
    always_comb begin
        pmu_dispatch_instr_cnt = 0;
        pmu_dispatch_backend_nop = 0;
        pmu_dispatch_frontend_nop = 0;
        pmu_dispatch_datadep_nop = 0;
        for (integer i = 0; i < ISSUE_WIDTH; i++) begin
            if (~stall & ~flush) pmu_dispatch_instr_cnt = pmu_dispatch_instr_cnt + issue_valid[i];
            if (stall) pmu_dispatch_backend_nop = pmu_dispatch_backend_nop + instr_exists_check[i];
            pmu_dispatch_frontend_nop = pmu_dispatch_frontend_nop + ((1 - instr_exists_check[i]) || flush);
            if (~stall & ~flush)
                pmu_dispatch_datadep_nop = pmu_dispatch_datadep_nop + (instr_exists_check[i] && ~(data_dep_check[i] && rreg_avail_check[i]));
        end
    end


`ifdef SIMU
    // DEBUG signal
    logic [4:0] debug_reg0, debug_reg1, debug_reg2, debug_reg3;
    logic [`InstAddrBus] debug_pc[DECODE_WIDTH];
    always_comb begin
        for (integer i = 0; i < DECODE_WIDTH; i++) begin
            debug_pc[i] = id_i[i].instr_info.pc;
        end
    end
    assign debug_reg0 = id_i[0].reg_read_addr[0];
    assign debug_reg1 = id_i[0].reg_read_addr[1];
    assign debug_reg2 = id_i[1].reg_read_addr[0];
    assign debug_reg3 = id_i[1].reg_read_addr[1];
`endif
endmodule
