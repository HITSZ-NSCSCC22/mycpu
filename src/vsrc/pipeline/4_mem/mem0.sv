`include "core_config.sv"
`include "core_types.sv"
`include "csr_defines.sv"
`include "TLB/tlb_types.sv"

module mem0
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
    input ex_mem_struct ex_i,

    // <- TLB
    input tlb_data_t tlb_result_i,


    // Data forward
    // -> Dispatch
    output data_forward_t data_forward_o,

    // Next stage
    output ex_mem_struct mem1_o_buffer,
    output tlb_data_t tlb_result_o

);


    // Instr info
    instr_info_t   instr_info;
    special_info_t special_info;
    assign instr_info   = ex_i.instr_info;
    assign special_info = instr_info.special_info;

    // Signals
    logic mem_load_op;

    assign mem_load_op = special_info.mem_load;


    ex_mem_struct mem1_o;
    assign mem1_o = ex_i;


    // Data forward
    assign data_forward_o = {ex_i.wreg, !mem_load_op, ex_i.waddr, ex_i.wdata};


    always_ff @(posedge clk) begin
        if (rst) begin
            mem1_o_buffer <= 0;
            tlb_result_o  <= 0;
        end else if (flush | clear) begin
            mem1_o_buffer <= 0;
            tlb_result_o  <= 0;
        end else if (advance) begin
            mem1_o_buffer <= mem1_o;
            tlb_result_o  <= tlb_result_i;
        end
    end

endmodule
