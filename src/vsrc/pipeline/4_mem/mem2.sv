`include "core_types.sv"
`include "core_config.sv"

module mem2
    import core_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,

    // Pipeline control signals
    input logic flush,
    input logic clear,
    input logic advance,

    // Previous stage
    input mem1_mem2_struct mem1_i,

    // Dispatch
    output data_forward_t   data_forward_o,
    // Next stage
    output mem2_mem3_struct mem2_o_buffer
);
    mem2_mem3_struct mem2_o;

    // Assign input
    instr_info_t instr_info;
    special_info_t special_info;

    logic mem_load_op;


    assign instr_info = mem1_i.instr_info;
    assign special_info = mem1_i.instr_info.special_info;


    assign mem_load_op = special_info.mem_load;

    assign data_forward_o = {
        mem2_o.wreg, !mem_load_op, mem2_o.waddr, mem2_o.wdata, mem2_o.csr_signal
    };


    always_comb begin
        mem2_o.instr_info = instr_info;
        mem2_o.wreg = mem1_i.wreg;
        mem2_o.waddr = mem1_i.waddr;
        mem2_o.wdata = mem1_i.wdata;
        mem2_o.LLbit_we = mem1_i.LLbit_we;
        mem2_o.LLbit_value = mem1_i.LLbit_value;
        mem2_o.mem_addr = mem1_i.mem_addr;
        mem2_o.aluop = mem1_i.aluop;
        mem2_o.mem_access_valid = mem1_i.mem_access_valid;
        // Pass down TLBSRCH result
        mem2_o.tlbsrch_found = mem1_i.tlbsrch_found;
        mem2_o.tlbsrch_index = mem1_i.tlbsrch_index;
        mem2_o.csr_signal = mem1_i.csr_signal;
        mem2_o.inv_i = mem1_i.inv_i;
        mem2_o.difftest_mem_info = mem1_i.difftest_mem_info;
    end

    always_ff @(posedge clk) begin
        if (rst) mem2_o_buffer <= 0;
        else if (flush | clear) mem2_o_buffer <= 0;
        else if (advance) mem2_o_buffer <= mem2_o;
    end

`ifdef SIMU
    logic [ADDR_WIDTH-1:0] debug_pc = instr_info.pc;
    logic [`RegBus] debug_wdata = mem2_o.wdata;
`endif


endmodule
