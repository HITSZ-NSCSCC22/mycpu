`include "core_types.sv"
`include "TLB/tlb_types.sv"
`include "csr_defines.sv"
`include "core_config.sv"


module ctrl
    import tlb_types::*;
    import core_types::*;
    import csr_defines::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,

    // -> Frontend
    output logic [COMMIT_WIDTH-1:0] backend_commit_block_o,  // do backend commit a basic block
    output logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_flush_ftq_id_o,

    input wb_ctrl_struct [COMMIT_WIDTH-1:0] wb_i,  //流水线传来的信号

    // Pipeline control signals
    input logic [ISSUE_WIDTH-1:0] ex_redirect_i,  //执行阶段重定向信号
    input logic [ISSUE_WIDTH-1:0] ex_advance_ready_i,  //执行阶段完成信号
    input logic [ISSUE_WIDTH-1:0] mem1_advance_ready_i,
    input logic [ISSUE_WIDTH-1:0] mem2_advance_ready_i,  //访存阶段暂停请求信号
    output logic [6:0] flush_o,  // flush signal {frontend, id_dispatch, dispatch, ex, mem1, mem2, wb}
    output logic [6:0] advance_o,  // {frontend, id_dispatch, dispatch, ex, mem1, mem2, wb}

    // -> CSR
    output logic [31:0] csr_era,
    output logic [8:0] csr_esubcode,
    output logic [5:0] csr_ecode,
    output logic va_error,
    output logic [31:0] bad_va,
    output logic excp_tlbrefill,
    output logic excp_tlb,
    output logic [18:0] excp_tlb_vppn,
    output logic tlbsrch_found,
    output logic [4:0] tlbsrch_index,
    output logic tlbrd_en,

    output logic tlbwr_en,
    output logic tlbsrch_en,
    output logic tlbfill_en,
    output wb_llbit_t llbit_signal,

    input tlb_to_mem_struct tlbsrch_result_i,

    //invtlb signal to tlb
    output tlb_inv_t inv_o,
    input logic inv_stallreq,

    //regfile-write
    output wb_reg_t [COMMIT_WIDTH-1:0] regfile_o,

    //csr-write
    output csr_write_signal [COMMIT_WIDTH-1:0] csr_write_o,

    //difftest-commit
    output [`InstBus] excp_instr,
    output diff_commit [COMMIT_WIDTH-1:0] difftest_commit_o
);

    instr_info_t [COMMIT_WIDTH-1:0] instr_info;
    special_info_t [COMMIT_WIDTH-1:0] special_info;

    logic valid;
    logic [`AluOpBus] aluop, aluop_1;
    logic [COMMIT_WIDTH-1:0] backend_commit_valid;
    logic [`RegBus] pc, error_va;
    // Exception
    logic excp;
    logic [15:0] excp_num;
    logic excp_flush, ertn_flush, refetch_flush, idle_flush;
    logic [  ADDR_WIDTH-1:0] idle_pc;
    logic [COMMIT_WIDTH-1:0] commit_valid;


    assign valid = wb_i[0].valid | wb_i[1].valid;

    always_comb begin
        for (integer i = 0; i < COMMIT_WIDTH; i++) begin
            instr_info[i]   = wb_i[i].instr_info;
            special_info[i] = wb_i[i].instr_info.special_info;
        end
    end


    assign backend_commit_valid[0] = wb_i[0].valid;
    assign backend_commit_valid[1] = (aluop == `EXE_ERTN_OP | aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP | aluop == `EXE_IDLE_OP | instr_info[0].excp)? 0 : wb_i[1].valid;

    // Backend commit basic block
    assign backend_commit_block_o = backend_commit_valid & (instr_info[0].excp ? 2'b01:
                                    instr_info[1].excp ? {1'b1 , wb_i[0].is_last_in_block | ertn_flush | idle_flush | refetch_flush} : 
                                    {wb_i[1].is_last_in_block, wb_i[0].is_last_in_block | ertn_flush | idle_flush | refetch_flush});
    // Backend flush FTQ ID
    assign backend_flush_ftq_id_o = (instr_info[0].excp | ertn_flush | idle_flush | refetch_flush) ? instr_info[0].ftq_id :
                                    (instr_info[1].excp) ? instr_info[1].ftq_id : 0;


    assign aluop = wb_i[0].aluop;
    assign aluop_1 = wb_i[1].aluop;

    // csr and tlb instr 
    assign tlbrd_en = wb_i[0].aluop == `EXE_TLBRD_OP | wb_i[1].aluop == `EXE_TLBRD_OP;
    assign tlbwr_en = wb_i[0].aluop == `EXE_TLBWR_OP | wb_i[1].aluop == `EXE_TLBWR_OP;
    assign tlbsrch_en = wb_i[0].aluop == `EXE_TLBSRCH_OP | wb_i[1].aluop == `EXE_TLBSRCH_OP;
    assign tlbfill_en = wb_i[0].aluop == `EXE_TLBFILL_OP | wb_i[1].aluop == `EXE_TLBFILL_OP;
    assign tlbsrch_found = tlbsrch_result_i.data_tlb_found;
    assign tlbsrch_index = tlbsrch_result_i.data_tlb_index;
    assign inv_o = wb_i[0].inv_i | wb_i[1].inv_i;

    //assign llbit_signal.we = wb_i[0].aluop == `EXE_LL_OP | wb_i[0].aluop == `EXE_SC_OP ;
    //assign llbit_signal.value = (wb_i[0].aluop == `EXE_LL_OP & 1'b1) | (wb_i[0].aluop == `EXE_SC_OP & 1'b0);

    always_comb begin
        if (rst) llbit_signal = 0;
        else if (excp) llbit_signal = 0;
        else begin
            llbit_signal.we = wb_i[0].aluop == `EXE_LL_OP | wb_i[0].aluop == `EXE_SC_OP;
            llbit_signal.value = (wb_i[0].aluop == `EXE_LL_OP & 1'b1) | (wb_i[0].aluop == `EXE_SC_OP & 1'b0);
        end
    end

    // Pipeline control signals
    logic advance;  // Advance when all stages are ready
    logic advance_delay;
    always_comb begin
        advance = 1;
        for (integer i = 0; i < COMMIT_WIDTH; i++) begin
            advance = advance & ex_advance_ready_i[i] & mem1_advance_ready_i[i] & mem2_advance_ready_i[i];
        end
    end
    assign advance_o = {7{advance}};
    // Frontend
    assign flush_o[6] = excp_flush | ertn_flush | refetch_flush | idle_flush;
    // ID -> Dispatch
    assign flush_o[5] = excp_flush | ertn_flush | refetch_flush | idle_flush;
    // Dispatch
    assign flush_o[4] = excp_flush | ertn_flush | refetch_flush | idle_flush;
    // Ex
    assign flush_o[3] = excp_flush | ertn_flush | refetch_flush | idle_flush;
    // MEM1
    assign flush_o[2] = excp_flush | ertn_flush | refetch_flush | idle_flush;
    // MEM2
    assign flush_o[1] = excp_flush | ertn_flush | refetch_flush | idle_flush;
    // WB
    assign flush_o[0] = (advance_delay & ~advance) | excp_flush | ertn_flush | refetch_flush | idle_flush;

    assign excp_flush = excp;
    assign idle_flush = aluop == `EXE_IDLE_OP;
    assign ertn_flush = aluop == `EXE_ERTN_OP | wb_i[1].aluop == `EXE_ERTN_OP;
    assign refetch_flush = special_info[0].need_refetch | special_info[0].need_refetch;
    assign idle_pc = instr_info[0].pc;

    //提交difftest
    always_comb begin
        difftest_commit_o[0] = wb_i[0].valid ? wb_i[0].diff_commit_o : 0;
        if (~commit_valid[0]) difftest_commit_o[0].valid = 0;

        difftest_commit_o[1] = (!wb_i[1].valid |aluop == `EXE_ERTN_OP | aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP | aluop == `EXE_IDLE_OP) ? 0 : wb_i[1].diff_commit_o;
        if (~commit_valid[1]) difftest_commit_o[1].valid = 0;
    end

    //写入寄存器堆
    assign commit_valid[0] = ~instr_info[0].excp;
    assign commit_valid[1] = ~instr_info[0].excp & ~instr_info[1].excp & ~(special_info[0].is_taken & ~special_info[1].predicted_taken) & ~(aluop == `EXE_ERTN_OP | aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP | aluop == `EXE_IDLE_OP);

    assign regfile_o[0] = commit_valid[0] ? wb_i[0].wb_reg : 0;
    assign regfile_o[1] = commit_valid[1] ? wb_i[1].wb_reg : 0;

    assign csr_write_o[0] = commit_valid[0] ? wb_i[0].csr_signal_o : 0;
    assign csr_write_o[1] = commit_valid[1] ? wb_i[1].csr_signal_o : 0;


    assign excp = instr_info[0].excp | instr_info[1].excp;
    assign csr_era = aluop == `EXE_IDLE_OP ? pc + 32'h4 : pc;
    //异常处理，优先处理第一条流水线的异常
    assign {excp_num, pc, excp_instr, error_va} = 
            instr_info[0].excp ? {instr_info[0].excp_num, instr_info[0].pc,wb_i[0].diff_commit_o.instr, wb_i[0].mem_addr} :
            instr_info[1].excp ? {instr_info[1].excp_num, instr_info[1].pc ,wb_i[1].diff_commit_o.instr, wb_i[1].mem_addr} : 0;

    assign {csr_ecode,va_error, bad_va, csr_esubcode, excp_tlbrefill,excp_tlb, excp_tlb_vppn} = 
    excp_num[0] ? {`ECODE_INT ,1'b0, 32'b0 , 9'b0 , 1'b0, 1'b0, 19'b0} :
    excp_num[1] ? {`ECODE_ADEF, valid, pc, `ESUBCODE_ADEF, 1'b0, 1'b0, 19'b0} :
    excp_num[2] ? {`ECODE_TLBR, valid, pc, 9'b0, valid, valid, pc[31:13]} :
    excp_num[3] ? {`ECODE_PIF , valid, pc, 9'b0, 1'b0, valid, pc[31:13]} :
    excp_num[4] ? {`ECODE_PPI , valid, pc, 9'b0, 1'b0, valid, pc[31:13]} :
    excp_num[5] ? {`ECODE_SYS , 1'b0, 32'b0, 9'b0, 1'b0, 1'b0, 19'b0} :
    excp_num[6] ? {`ECODE_BRK , 1'b0, 32'b0, 9'b0, 1'b0, 1'b0, 19'b0} :
    excp_num[7] ? {`ECODE_INE , 1'b0, 32'b0, 9'b0, 1'b0, 1'b0, 19'b0} :
    excp_num[8] ? {`ECODE_IPE , 1'b0, 32'b0, 9'b0, 1'b0, 1'b0, 19'b0} :   //close ipe excp now
    excp_num[9] ? {`ECODE_ALE , valid, error_va, 9'b0 , 1'b0, 1'b0, 19'b0} :
    excp_num[10] ? {`ECODE_ADEM, valid, error_va, `ESUBCODE_ADEM, 1'b0, 1'b0 , 19'b0} :
    excp_num[11] ? {`ECODE_TLBR, valid, error_va, 9'b0, valid, valid, error_va[31:13]} :
    excp_num[12] ? {`ECODE_PME , valid, error_va, 9'b0, 1'b0, valid, error_va[31:13]} :
    excp_num[13] ? {`ECODE_PPI , valid, error_va, 9'b0, 1'b0, valid, error_va[31:13]} :
    excp_num[14] ? {`ECODE_PIS , valid, error_va, 9'b0, 1'b0, valid, error_va[31:13]} :
    excp_num[15] ? {`ECODE_PIL , valid, error_va, 9'b0, 1'b0, valid, error_va[31:13]} :
    69'b0;

endmodule  //ctrl
