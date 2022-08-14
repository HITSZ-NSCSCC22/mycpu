`include "core_config.sv"
`include "core_types.sv"
`include "csr_defines.sv"
`include "TLB/tlb_types.sv"

module mem2
    import core_config::*;
    import core_types::*;
    import csr_defines::*;
    import tlb_types::*;
(
    input logic clk,
    input logic rst,

    // Pipeline control signals
    input logic flush,
    input logic clear,
    input logic advance,

    // Previous stage
    input mem1_mem2_struct mem1_i,

    // Data forward
    // -> Dispatch
    output data_forward_t data_forward_o,

    // Next stage
    output mem1_mem2_struct mem3_o_buffer
);


    // Instr info
    instr_info_t   instr_info;
    special_info_t special_info;
    assign instr_info   = mem1_i.instr_info;
    assign special_info = instr_info.special_info;

    // Signals
    logic mem_load_op;

    assign mem_load_op = special_info.mem_load;


    mem1_mem2_struct mem3_o;
    assign mem3_o = mem1_i;


    // Data forward
    assign data_forward_o = {mem1_i.wreg, !mem_load_op, mem1_i.waddr, mem1_i.wdata};


    always_ff @(posedge clk) begin
        if (rst) begin
            mem3_o_buffer <= 0;
        end else if (flush | clear) begin
            mem3_o_buffer <= 0;
        end else if (advance) begin
            mem3_o_buffer <= mem3_o;
        end
    end

endmodule
