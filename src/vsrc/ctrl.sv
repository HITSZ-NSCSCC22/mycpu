`include "pipeline_defines.sv"
module ctrl (
    input logic rst,

    input wb_ctrl wb_i_1,
    input wb_ctrl wb_i_2,
    input logic [1:0] ex_branch_flag_i,
    input logic [1:0] ex_stallreq_i,
    input logic stallreq_from_dispatch,
    input logic [1:0] mem_stallreq_i,
    input logic excp_flush,
    input logic ertn_flush,
    input logic fetch_flush,

    // Stall request to each stage
    output logic [4:0] stall,  // from 4->0 {ex_mem, dispatch_ex, id_dispatch, _}

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

    //regfile-write
    output wb_reg reg_o_0,
    output wb_reg reg_o_1,

    //csr-write
    output csr_write_signal csr_w_o_0,
    output csr_write_signal csr_w_o_1,

    //difftest-commit
    output diff_commit commit_0,
    output diff_commit commit_1
);

    logic valid;
    assign valid = wb_i_1.valid | wb_i_2.valid;

    assign ex_mem_flush_o[1] = ex_branch_flag_i[0];
    assign ex_mem_flush_o[0] = 0;
    assign flush = fetch_flush | excp_flush | ertn_flush;

    //暂停处理
    always_comb begin
        if (rst) stall = 5'b00000;
        else if (ex_stallreq_i[0] | ex_stallreq_i[1]) stall = 5'b11110;
        else if (mem_stallreq_i[0] | mem_stallreq_i[1]) stall = 5'b11110;
        else if (stallreq_from_dispatch) stall = 5'b11100;
        else stall = 5'b00000;
    end

    //提交difftest
    assign commit_0  = wb_i_1.diff_commit_o;
    assign commit_1  = (wb_i_1.aluop == `EXE_ERTN_OP) ? 0 : wb_i_2.diff_commit_o;

    //写入寄存器堆
    assign reg_o_0   = wb_i_1.wb_reg_o;
    assign reg_o_1   = (wb_i_1.aluop == `EXE_ERTN_OP) ? 0 : wb_i_2.wb_reg_o;

    assign csr_w_o_0 = wb_i_1.csr_signal_o;
    assign csr_w_o_1 = (wb_i_1.aluop == `EXE_ERTN_OP) ? 0 : wb_i_2.csr_signal_o;

    logic excp;
    logic [15:0] excp_num;
    logic [`RegBus] pc, error_va;
    assign excp = wb_i_1.excp | wb_i_2.excp;
    assign csr_era = pc;
    //异常处理，优先处理第一条流水线的异常
    assign {excp_num, pc, error_va} = 
            wb_i_1.excp ? {wb_i_1.excp_num, wb_i_1.wb_reg_o.pc, wb_i_1.wb_reg_o.wdata} :
            wb_i_2.excp ? {wb_i_2.excp_num, wb_i_2.wb_reg_o.pc, wb_i_2.wb_reg_o.wdata} : 0;

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
