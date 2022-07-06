`include "core_types.sv"
`include "core_config.sv"
`include "tlb_types.sv"

module wb
    import core_types::*;
    import core_config::*;
    import csr_defines::*;
    import tlb_types::*;
(
    input logic clk,
    input logic rst,
    input logic stall,
    input logic flush,

    input mem2_wb_struct mem_signal_o,

    input logic mem_LLbit_we,
    input logic mem_LLbit_value,

    //<-> csr 
    input csr_to_mem_struct csr_mem_signal,
    input logic disable_cache,
    input logic LLbit_i,
    input logic LLbit_we_i,
    input logic LLbit_value_i,

    // load store relate difftest
    output wb_ctrl_struct wb_ctrl_signal,

    //<- dispatch
    output wb_data_forward_t wb_forward,

    // <-> DCache
    input data_ok,
    input [`RegBus] cache_data,
    output logic dcache_flush_o,

    //<- ctrl
    output logic stallreq,

    // <-> Frontend
    output logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] ftq_id_o
);

    csr_write_signal csr_test;
    assign csr_test = mem_signal_o.csr_signal;

    tlb_data_t tlb_signal;
    assign tlb_signal = mem_signal_o.tlb_signal;

    //sc只有llbit为1才执行，如果llbit为0，sc就不算访存指令
    logic LLbit;
    always @(*) begin
        if (rst == `RstEnable) LLbit = 1'b0;
        else begin
            if (LLbit_we_i == 1'b1) LLbit = LLbit_value_i;
            else LLbit = LLbit_i;
        end
    end

    logic excp, pg_mode, da_mode;
    logic [15:0] excp_num;
    logic access_mem, mem_store_op, mem_load_op;
    logic excp_tlbr, excp_pil, excp_pis, excp_pme, excp_ppi, excp_adem;
    logic cacop_en, icache_op_en;
    logic [4:0] cacop_op;
    assign cacop_en = mem_signal_o.cacop_en;
    assign icache_op_en = mem_signal_o.icache_op_en;
    assign cacop_op = mem_signal_o.cacop_op;

    logic [7:0] aluop;
    assign aluop = mem_signal_o.aluop;
    logic is_CNTinst;
    assign is_CNTinst = aluop == `EXE_RDCNTVL_OP | aluop == `EXE_RDCNTID_OP | aluop == `EXE_RDCNTVH_OP;

    //debug用的,无实际作用
    logic [2:0] mem_addr;
    assign mem_addr = mem_signal_o.mem_addr[31:29];

    logic data_addr_trans_en;
    assign data_addr_trans_en = mem_signal_o.data_addr_trans_en;

    assign access_mem = mem_load_op || mem_store_op;

    assign mem_load_op = mem_signal_o.aluop == `EXE_LD_B_OP ||  mem_signal_o.aluop == `EXE_LD_BU_OP ||  mem_signal_o.aluop == `EXE_LD_H_OP ||  mem_signal_o.aluop == `EXE_LD_HU_OP ||
                        mem_signal_o.aluop == `EXE_LD_W_OP ||  mem_signal_o.aluop == `EXE_LL_OP;

    assign mem_store_op =  mem_signal_o.aluop == `EXE_ST_B_OP ||  mem_signal_o.aluop == `EXE_ST_H_OP ||  mem_signal_o.aluop == `EXE_ST_W_OP ||  (mem_signal_o.aluop == `EXE_SC_OP && LLbit == 1'b1);

    // Addr translate mode for DCache, pull down if instr is invalid

    assign excp_adem = (access_mem || cacop_en) && data_addr_trans_en && (csr_mem_signal.csr_plv == 2'd3) && mem_signal_o.mem_addr[31];
    assign excp_tlbr = (access_mem || cacop_en) && !tlb_signal.found && data_addr_trans_en;
    assign excp_pil  = mem_load_op  && !tlb_signal.tlb_v && data_addr_trans_en;  //cache will generate pil exception??
    assign excp_pis = mem_store_op && !tlb_signal.tlb_v && data_addr_trans_en;
    assign excp_ppi = access_mem && tlb_signal.tlb_v && (csr_mem_signal.csr_plv > tlb_signal.tlb_plv) && data_addr_trans_en;
    assign excp_pme  = mem_store_op && tlb_signal.tlb_v && (csr_mem_signal.csr_plv <= tlb_signal.tlb_plv) && !tlb_signal.tlb_d && data_addr_trans_en;

    assign excp = excp_tlbr || excp_pil || excp_pis || excp_ppi || excp_pme || excp_adem || mem_signal_o.excp;
    assign excp_num = {
        excp_pil, excp_pis, excp_ppi, excp_pme, excp_tlbr, excp_adem, mem_signal_o.excp_num
    };

    assign dcache_flush_o = excp;

    assign wb_forward = {
        mem_load_op, data_ok, mem_signal_o.wreg, mem_signal_o.waddr, mem_signal_o.wdata, cache_data
    };

    assign stallreq = mem_load_op & !data_ok;


    always_ff @(posedge clk) begin
        if (rst == `RstEnable) wb_ctrl_signal.wb_reg_o.wdata <= 0;
        else if (flush | stall) wb_ctrl_signal.wb_reg_o.wdata <= 0;
        else if (mem_load_op && data_ok) wb_ctrl_signal.wb_reg_o.wdata <= cache_data;
        else wb_ctrl_signal.wb_reg_o.wdata <= mem_signal_o.wdata;
    end

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            wb_ctrl_signal <= 0;
        end else if (flush | stall) begin
            wb_ctrl_signal <= 0;
        end else begin
            // -> Frontend
            // If marked as exception, the basic block is ended
            ftq_id_o <= mem_signal_o.instr_info.ftq_id;

            wb_ctrl_signal.valid <= 1'b1;
            wb_ctrl_signal.is_last_in_block <= mem_signal_o.instr_info.is_last_in_block;
            wb_ctrl_signal.aluop <= mem_signal_o.aluop;
            wb_ctrl_signal.wb_reg_o.waddr <= mem_signal_o.waddr;
            wb_ctrl_signal.wb_reg_o.we <= mem_signal_o.wreg;
            wb_ctrl_signal.wb_reg_o.pc <= mem_signal_o.instr_info.pc;
            wb_ctrl_signal.llbit_o.we <= mem_LLbit_we;
            wb_ctrl_signal.llbit_o.value <= mem_LLbit_value;
            wb_ctrl_signal.excp <= excp;
            wb_ctrl_signal.excp_num <= excp_num;
            wb_ctrl_signal.mem_addr <= mem_signal_o.mem_addr;
            wb_ctrl_signal.fetch_flush <= mem_signal_o.refetch;
            wb_ctrl_signal.data_tlb_found <= tlb_signal.found;
            wb_ctrl_signal.data_tlb_index <= tlb_signal.tlb_index;
            wb_ctrl_signal.csr_signal_o <= mem_signal_o.csr_signal;
            wb_ctrl_signal.inv_i <= mem_signal_o.inv_i;
            wb_ctrl_signal.diff_commit_o.pc <= mem_signal_o.instr_info.pc;
            wb_ctrl_signal.diff_commit_o.valid <= mem_signal_o.instr_info.valid;
            wb_ctrl_signal.diff_commit_o.instr <= mem_signal_o.instr_info.instr;
            wb_ctrl_signal.diff_commit_o.inst_ld_en <= mem_signal_o.inst_ld_en;
            wb_ctrl_signal.diff_commit_o.inst_st_en <= mem_signal_o.inst_st_en;
            wb_ctrl_signal.diff_commit_o.is_CNTinst <= is_CNTinst;
            wb_ctrl_signal.diff_commit_o.timer_64 <= mem_signal_o.timer_64;
            wb_ctrl_signal.diff_commit_o.ld_paddr <= {tlb_signal.tag, mem_signal_o.load_addr[11:0]};
            wb_ctrl_signal.diff_commit_o.ld_vaddr <= mem_signal_o.load_addr;
            wb_ctrl_signal.diff_commit_o.st_paddr <= {
                tlb_signal.tag, mem_signal_o.store_addr[11:0]
            };
            wb_ctrl_signal.diff_commit_o.st_vaddr <= mem_signal_o.store_addr;
            wb_ctrl_signal.diff_commit_o.st_data <= mem_signal_o.store_data;
            wb_ctrl_signal.cacop_en <= cacop_en;
            wb_ctrl_signal.icache_op_en <= icache_op_en;
            wb_ctrl_signal.cacop_op <= cacop_op;
        end
    end


endmodule
