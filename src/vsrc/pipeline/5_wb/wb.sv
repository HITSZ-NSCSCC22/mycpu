`include "core_types.sv"
`include "core_config.sv"
`include "TLB/tlb_types.sv"

module wb
    import core_types::*;
    import core_config::*;
    import csr_defines::*;
    import tlb_types::*;
(
    input logic clk,
    input logic rst,

    // Pipeline control signals
    input logic flush,
    input logic advance,
    // input logic advance_ready,

    input mem2_wb_struct mem_i,

    // load store relate difftest
    output wb_ctrl_struct wb_ctrl_signal,

    // <- Dispatch
    output data_forward_t data_forward_o,

    // DCache
    output logic dcache_flush_o,
    output logic dcache_store_commit_o
);

    // Assign input ///////////////////////////////////////////
    instr_info_t instr_info;
    special_info_t special_info;

    csr_write_signal csr_test;

    logic excp;
    logic [15:0] excp_num;
    logic access_mem, mem_store_op, mem_load_op;

    logic [7:0] aluop;

    logic is_CNTinst;

    assign instr_info = mem_i.instr_info;
    assign special_info = mem_i.instr_info.special_info;


    assign csr_test = mem_i.csr_signal;


    assign aluop = mem_i.aluop;

    assign is_CNTinst = aluop == `EXE_RDCNTVL_OP | aluop == `EXE_RDCNTID_OP | aluop == `EXE_RDCNTVH_OP;


    assign access_mem = mem_load_op | mem_store_op;
    assign mem_load_op = special_info.mem_load;
    assign mem_store_op = special_info.mem_store;

    assign excp = instr_info.excp;
    assign excp_num = instr_info.excp_num;

    assign dcache_flush_o = excp | special_info.redirect | (special_info.need_refetch && aluop != `EXE_CACOP_OP);
    assign dcache_store_commit_o = mem_store_op & ~excp;

    assign data_forward_o = {mem_i.wreg, 1'b1, mem_i.waddr, mem_i.wdata, mem_i.csr_signal};


    always @(posedge clk) begin
        if (rst) begin
            wb_ctrl_signal <= 0;
        end else if (flush) begin
            wb_ctrl_signal <= 0;
        end else if (advance) begin
            wb_ctrl_signal.valid <= mem_i.instr_info.valid;
            wb_ctrl_signal.is_last_in_block <= mem_i.instr_info.is_last_in_block;
            wb_ctrl_signal.aluop <= mem_i.aluop;
            wb_ctrl_signal.instr_info <= mem_i.instr_info;
            wb_ctrl_signal.mem_addr <= mem_i.mem_addr;
            wb_ctrl_signal.wb_reg.wdata <= mem_i.wdata;
            wb_ctrl_signal.wb_reg.waddr <= mem_i.waddr;
            wb_ctrl_signal.wb_reg.we <= mem_i.wreg;
            wb_ctrl_signal.llbit.we <= mem_i.LLbit_we;
            wb_ctrl_signal.llbit.value <= mem_i.LLbit_value;
            // wb_ctrl_signal.data_tlb_index <= tlb_signal.tlb_index;
            wb_ctrl_signal.csr_signal_o <= mem_i.csr_signal;
            wb_ctrl_signal.inv_i <= mem_i.inv_i;

            wb_ctrl_signal.diff_commit_o.pc <= mem_i.instr_info.pc;
            wb_ctrl_signal.diff_commit_o.valid <= mem_i.instr_info.valid;
            wb_ctrl_signal.diff_commit_o.instr <= mem_i.instr_info.instr;
            wb_ctrl_signal.diff_commit_o.inst_ld_en <= mem_i.difftest_mem_info.inst_ld_en;
            wb_ctrl_signal.diff_commit_o.inst_st_en <= mem_i.difftest_mem_info.inst_st_en;
            wb_ctrl_signal.diff_commit_o.is_CNTinst <= is_CNTinst;
            wb_ctrl_signal.diff_commit_o.timer_64 <= mem_i.difftest_mem_info.timer_64;
            wb_ctrl_signal.diff_commit_o.ld_paddr <= mem_i.difftest_mem_info.load_addr;
            wb_ctrl_signal.diff_commit_o.ld_vaddr <= mem_i.difftest_mem_info.load_addr;
            wb_ctrl_signal.diff_commit_o.st_paddr <= mem_i.difftest_mem_info.store_addr;
            wb_ctrl_signal.diff_commit_o.st_vaddr <= mem_i.difftest_mem_info.store_addr;
            wb_ctrl_signal.diff_commit_o.st_data <= mem_i.difftest_mem_info.store_data;
            wb_ctrl_signal.diff_commit_o.csr_rstat <= special_info.csr_rstat;
        end
    end

    logic debug_redirect = special_info.redirect;
    logic debug_refetch = special_info.need_refetch;

endmodule
