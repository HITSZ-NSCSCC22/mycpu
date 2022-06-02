`include "pipeline_defines.sv"
module ctrl (
    input logic clk,
    input logic rst,

    input wb_ctrl wb_i_1,
    input wb_ctrl wb_i_2,
    input logic [1:0] ex_branch_flag_i,
    input logic [1:0] ex_stallreq_i,
    input logic [1:0] tlb_stallreq,
    input logic stallreq_from_dispatch,
    input logic [1:0] mem_stallreq_i,
    output logic excp_flush,
    output logic ertn_flush,
    output logic fetch_flush,

    // Stall request to each stage
    output logic [4:0] stall,  // from 4->0 {ex_mem, dispatch_ex, id_dispatch, _}

    input logic is_pri_instr,
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

    //invtlb signal to tlb
    output tlb_inv_in_struct inv_o,

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
    assign valid = wb_i_1.valid | wb_i_2.valid;

    logic [`AluOpBus] aluop, aluop_1;
    assign aluop = wb_i_1.aluop;
    assign aluop_1 = wb_i_2.aluop;

    // csr and tlb instr 
    assign tlbrd_en = wb_i_1.aluop == `EXE_TLBRD_OP | wb_i_2.aluop == `EXE_TLBRD_OP;
    assign tlbwr_en = wb_i_1.aluop == `EXE_TLBWR_OP | wb_i_2.aluop == `EXE_TLBWR_OP;
    assign tlbsrch_en = wb_i_1.aluop == `EXE_TLBSRCH_OP | wb_i_2.aluop == `EXE_TLBSRCH_OP;
    assign tlbfill_en = wb_i_1.aluop == `EXE_TLBFILL_OP | wb_i_2.aluop == `EXE_TLBFILL_OP;
    assign tlbsrch_found = wb_i_1.data_tlb_found | wb_i_2.data_tlb_found;
    assign tlbsrch_index = wb_i_1.data_tlb_index | wb_i_2.data_tlb_index;
    assign inv_o = wb_i_1.inv_i | wb_i_2.inv_i;

    //flush sign 

    //第二条流水线冲刷:当第一条流水线的指令发生跳转时,或是发生异常和ertn指令时进行冲刷
    assign ex_mem_flush_o[1] = ex_branch_flag_i[0] | ertn_flush | excp_flush;
    //第一条流水线冲刷:发生异常和ertn指令时进行冲刷
    assign ex_mem_flush_o[0] = ertn_flush | excp_flush;
    assign excp_flush = excp;
    assign ertn_flush = wb_i_1.aluop == `EXE_ERTN_OP | wb_i_2.aluop == `EXE_ERTN_OP;
    assign fetch_flush = 0;
    assign flush = fetch_flush | excp_flush | ertn_flush;

    //暂停处理
    always_comb begin
        if (rst) stall = 5'b00000;
        //执行阶段的暂停请求:进行乘除法时请求暂停,此时将译码和发射阶段阻塞
        else if (ex_stallreq_i[0] | ex_stallreq_i[1]) stall = 5'b11110;
        //访存阶段的暂停请求:进行访存操作时请求暂停,此时将译码和发射阶段阻塞
        else if (mem_stallreq_i[0] | mem_stallreq_i[1]) stall = 5'b11110;
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
                       aluop == `EXE_CACOP_OP ;

    //特权阻塞信号
    always_ff @(posedge clk) begin
        if (rst) pri_stall <= 0;
        //发射阶段发射特权信号,拉高阻塞信号,阻塞前端,不再传指令
        else if (is_pri_instr) pri_stall <= 1;
        //提交阶段,若提交的是特权指令,把阻塞信号拉低,开始发射
        else if (pri_commit) pri_stall <= 0;
        //其余时刻保持当前状态
    end

    //提交difftest
    always_comb begin
        commit_0 = wb_i_1.diff_commit_o;
        if (wb_i_1.excp) commit_0.valid = 0;
        commit_1 = (aluop == `EXE_ERTN_OP | aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP) ? 0 : wb_i_2.diff_commit_o;
        if (wb_i_2.excp) commit_1.valid = 0;
    end

    //写入寄存器堆
    assign reg_o_0 = wb_i_1.wb_reg_o;
    assign reg_o_1 = (aluop == `EXE_ERTN_OP | aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP ) ? 0 : wb_i_2.wb_reg_o;

    assign csr_w_o_0 = wb_i_1.csr_signal_o;
    assign csr_w_o_1 = (aluop == `EXE_ERTN_OP | aluop == `EXE_SYSCALL_OP | aluop == `EXE_BREAK_OP ) ? 0 : wb_i_2.csr_signal_o;

    logic excp;
    logic [15:0] excp_num;
    logic [`RegBus] pc, error_va;
    assign excp = wb_i_1.excp | wb_i_2.excp;
    assign csr_era = pc;
    //异常处理，优先处理第一条流水线的异常
    assign {excp_num, pc, excp_instr, error_va} = 
            wb_i_1.excp ? {wb_i_1.excp_num, wb_i_1.wb_reg_o.pc,wb_i_1.diff_commit_o.instr, wb_i_1.wb_reg_o.wdata} :
            wb_i_2.excp ? {wb_i_2.excp_num, wb_i_2.wb_reg_o.pc,wb_i_2.diff_commit_o.instr, wb_i_2.wb_reg_o.wdata} : 0;

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
    excp_num[13] ? {`ECODE_PPI , valid, error_va, 9'b0, 1'b0, valid, error_va[31:13]} :
    excp_num[14] ? {`ECODE_PIS , valid, error_va, 9'b0, 1'b0, valid, error_va[31:13]} :
    excp_num[15] ? {`ECODE_PIL , valid, error_va, 9'b0, 1'b0, valid, error_va[31:13]} :
    69'b0;

endmodule  //ctrl
