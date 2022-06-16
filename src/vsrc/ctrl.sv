`include "core_types.sv"
`include "tlb_types.sv"
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

    input wb_ctrl wb_i[2],  //流水线传来的信号
    input logic [1:0][$clog2(FRONTEND_FTQ_SIZE)-1:0] wb_ftq_id_i,
    input logic [1:0] ex_branch_flag_i,  //执行阶段跳转信号
    input logic [1:0] ex_stallreq_i,  //执行阶段暂停请求信号
    input logic [1:0] tlb_stallreq,  //tlb暂停请求信号(未用到)
    input logic stallreq_from_dispatch,  //发射阶段暂停请求信号
    input logic [1:0] mem_stallreq_i,  //访存阶段暂停请求信号
    output logic idle_flush,  //idle指令冲刷信号
    output logic excp_flush,  //异常指令冲刷信号
    output logic ertn_flush,  //ertn指令冲刷信号
    output logic fetch_flush,  //未用到，暂时不管
    output logic [`InstAddrBus] idle_pc,  //idle指令pc

    // Stall request to each stage
    output logic [4:0] stall,  // from 4->0 {mem_wb, ex_mem, dispatch_ex, id_dispatch, _}

    input logic is_pri_instr,  //是否为特权指令
    output logic pri_stall,   //当特权指令发射时把此信号拉高,提交后拉低,确保特权指令后没有其它指令

    output logic [1:0] ex_mem_flush_o,
    output logic flush,

    //to csr
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
    output wb_llbit llbit_signal,

    input tlb_to_mem_struct tlbsrch_result_i,

    //invtlb signal to tlb
    output tlb_inv_t inv_o,

    //regfile-write
    output wb_reg reg_o_0,
    output wb_reg reg_o_1,

    //csr-write
    output csr_write_signal csr_w_o_0,
    output csr_write_signal csr_w_o_1,

    //difftest-commit
    output [`InstBus] excp_instr,
    output diff_commit commit_0,
    output diff_commit commit_1
);

    logic valid;
    assign valid = wb_i[0].valid | wb_i[1].valid;

    logic [COMMIT_WIDTH-1:0] backend_commit_valid;
    assign backend_commit_valid[0] = wb_i[0].valid;
    assign backend_commit_valid[1] = (aluop == `EXE_ERTN_OP | aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP | aluop == `EXE_IDLE_OP | wb_i[0].excp)? 0 : wb_i[1].valid;

    // Backend commit basic block
    assign backend_commit_block_o = backend_commit_valid & (wb_i[0].excp ? 2'b01:
                                    wb_i[1].excp ? {1'b1 , wb_i[0].is_last_in_block | ertn_flush | idle_flush} : 
                                    {wb_i[1].is_last_in_block, wb_i[0].is_last_in_block | ertn_flush | idle_flush});
    // Backend flush FTQ ID
    assign backend_flush_ftq_id_o = (wb_i[0].excp | ertn_flush | idle_flush ) ? wb_ftq_id_i[0] :
                                    (wb_i[1].excp) ? wb_ftq_id_i[1] : 0;

    logic [`AluOpBus] aluop, aluop_1;
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

    //flush sign 

    //第二条流水线冲刷:当第一条流水线的指令发生跳转时,或是发生异常和ertn指令时进行冲刷
    assign ex_mem_flush_o[1] = ex_branch_flag_i[0] | ertn_flush | excp_flush;
    //第一条流水线冲刷:发生异常和ertn指令时进行冲刷
    assign ex_mem_flush_o[0] = ertn_flush | excp_flush;
    assign excp_flush = excp;
    assign idle_flush = aluop == `EXE_IDLE_OP;
    assign ertn_flush = aluop == `EXE_ERTN_OP | wb_i[1].aluop == `EXE_ERTN_OP;
    assign fetch_flush = 0;
    assign idle_pc = wb_i[0].wb_reg_o.pc;
    assign flush = fetch_flush | excp_flush | ertn_flush;

    //暂停处理
    always_comb begin
        if (rst) stall = 5'b00000;
        //访存阶段的暂停请求:进行访存操作时请求暂停,此时将译码和发射阶段阻塞
        else if (mem_stallreq_i[0] | mem_stallreq_i[1]) stall = 5'b11110;
        //执行阶段的暂停请求:进行乘除法时请求暂停,此时将译码和发射阶段阻塞
        else if (ex_stallreq_i[0] | ex_stallreq_i[1]) stall = 5'b11110;
        //发射阶段的暂停请求:原本用于tlbrd指令的请求暂停,但是会出现bug,目前已经弃用
        else if (stallreq_from_dispatch) stall = 5'b11100;
        //else if (tlb_stallreq[0] | tlb_stallreq[1]) stall = 5'b11000;
        else
            stall = 5'b00000;
    end

    //判断提交的是否为特权指令,因为特权后不发射其它指令,故必然出现在第一条流水线
    logic pri_commit;
    assign pri_commit = aluop == `EXE_CSRWR_OP | aluop == `EXE_CSRRD_OP | aluop == `EXE_CSRXCHG_OP |
                       aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP | aluop == `EXE_ERTN_OP |
                       aluop == `EXE_TLBRD_OP | aluop == `EXE_TLBWR_OP | aluop == `EXE_TLBSRCH_OP |
                       aluop == `EXE_TLBFILL_OP | aluop == `EXE_IDLE_OP | aluop == `EXE_INVTLB_OP |
                       aluop == `EXE_RDCNTID_OP | aluop == `EXE_RDCNTVL_OP | aluop == `EXE_RDCNTVH_OP |
                       aluop == `EXE_CACOP_OP ;

    //特权阻塞信号
    always_ff @(posedge clk) begin
        if (rst) pri_stall <= 0;
        //发射阶段发射特权信号,拉高阻塞信号,阻塞前端,不再传指令
        else if (is_pri_instr) pri_stall <= 1;
        //提交阶段,若提交的是特权指令,把阻塞信号拉低,开始发射
        else if (pri_commit | excp_flush) pri_stall <= 0;
        //其余时刻保持当前状态
    end

    //提交difftest
    always_comb begin
        commit_0 = wb_i[0].diff_commit_o;
        if (wb_i[0].excp) commit_0.valid = 0;
        commit_1 = (aluop == `EXE_ERTN_OP | aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP | aluop == `EXE_IDLE_OP) ? 0 : wb_i[1].diff_commit_o;
        if (wb_i[1].excp) commit_1.valid = 0;
    end

    //写入寄存器堆
    assign reg_o_0 = wb_i[0].excp ? 0 : wb_i[0].wb_reg_o;
    assign reg_o_1 = (aluop == `EXE_ERTN_OP | aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP | aluop == `EXE_IDLE_OP | excp) ? 0 : wb_i[1].wb_reg_o;

    assign csr_w_o_0 = wb_i[0].excp ? 0 : wb_i[0].csr_signal_o;
    assign csr_w_o_1 = (aluop == `EXE_ERTN_OP | aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP | aluop == `EXE_IDLE_OP | excp) ? 0 : wb_i[1].csr_signal_o;

    logic excp;
    logic [15:0] excp_num;
    logic [`RegBus] pc, error_va;
    assign excp = wb_i[0].excp | wb_i[1].excp;
    assign csr_era = aluop == `EXE_IDLE_OP ? pc + 32'h4 : pc;
    //异常处理，优先处理第一条流水线的异常
    assign {excp_num, pc, excp_instr, error_va} = 
            wb_i[0].excp ? {wb_i[0].excp_num, wb_i[0].wb_reg_o.pc,wb_i[0].diff_commit_o.instr, wb_i[0].mem_addr} :
            wb_i[1].excp ? {wb_i[1].excp_num, wb_i[1].wb_reg_o.pc,wb_i[1].diff_commit_o.instr, wb_i[1].mem_addr} : 0;

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
