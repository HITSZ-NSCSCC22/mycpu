`include "pipeline_defines.sv"

module mem_wb (
    input logic clk,
    input logic rst,
    input logic stall,

    input mem_wb_struct mem_signal_o,

    input logic mem_LLbit_we,
    input logic mem_LLbit_value,

    input logic flush,

    // load store relate difftest
    output wb_ctrl wb_ctrl_signal,

    // <-> Frontend
    output logic is_last_in_block
);

    // For observability
    logic [`RegBus] debug_mem_wdata;
    assign debug_mem_wdata = mem_signal_o.wdata;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            wb_ctrl_signal   <= 0;
            is_last_in_block <= 0;
        end else if (stall == `Stop) begin
            wb_ctrl_signal.diff_commit_o.instr <= `ZeroWord;
            wb_ctrl_signal.diff_commit_o.pc <= `ZeroWord;
            wb_ctrl_signal.diff_commit_o.valid <= `InstInvalid;
            is_last_in_block <= 0;
        end else begin
            is_last_in_block <= mem_signal_o.instr_info.is_last_in_block;
            wb_ctrl_signal.valid <= 1'b1;
            wb_ctrl_signal.aluop <= mem_signal_o.aluop;
            wb_ctrl_signal.wb_reg_o.waddr    <= mem_signal_o.waddr;
            wb_ctrl_signal.wb_reg_o.we  <= mem_signal_o.wreg;
            wb_ctrl_signal.wb_reg_o.wdata <= mem_signal_o.wdata;
            wb_ctrl_signal.wb_reg_o.pc <= mem_signal_o.instr_info.pc;
            wb_ctrl_signal.llbit_o.we <= mem_LLbit_we;
            wb_ctrl_signal.llbit_o.value <= mem_LLbit_value;
            wb_ctrl_signal.excp <= mem_signal_o.excp;
            wb_ctrl_signal.excp_num <= mem_signal_o.excp_num;
            wb_ctrl_signal.fetch_flush <= mem_signal_o.refetch;
            wb_ctrl_signal.csr_signal_o <= mem_signal_o.csr_signal;
            wb_ctrl_signal.diff_commit_o.pc <= mem_signal_o.instr_info.pc;
            wb_ctrl_signal.diff_commit_o.valid <= mem_signal_o.instr_info.valid;
            wb_ctrl_signal.diff_commit_o.instr <= mem_signal_o.instr_info.instr;
            wb_ctrl_signal.diff_commit_o.inst_ld_en <= mem_signal_o.inst_ld_en;
            wb_ctrl_signal.diff_commit_o.inst_st_en <= mem_signal_o.inst_st_en;
            wb_ctrl_signal.diff_commit_o.ld_paddr <= mem_signal_o.load_addr;
            wb_ctrl_signal.diff_commit_o.ld_vaddr <= mem_signal_o.load_addr;
            wb_ctrl_signal.diff_commit_o.st_paddr <= mem_signal_o.store_addr;
            wb_ctrl_signal.diff_commit_o.st_vaddr <= mem_signal_o.store_addr;
            wb_ctrl_signal.diff_commit_o.st_data <= mem_signal_o.store_data;
        end
    end


endmodule
