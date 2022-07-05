`include "core_types.sv"
`include "core_config.sv"

module mem2
    import core_types::*;
    import core_config::*;
(
    input logic rst,

    input mem1_mem2_struct mem1_i,

    output mem2_data_forward_t mem2_data_forward,

    output mem2_wb_struct mem2_o,

    input logic data_ok,
    input logic [`RegBus] cache_data

);

    logic [`AluOpBus] aluop_i;
    assign aluop_i = mem1_i.aluop;

    logic mem_load_op;
    assign mem_load_op = aluop_i == `EXE_LD_B_OP || aluop_i == `EXE_LD_BU_OP || aluop_i == `EXE_LD_H_OP || aluop_i == `EXE_LD_HU_OP ||
                       aluop_i == `EXE_LD_W_OP || aluop_i == `EXE_LL_OP || aluop_i == `EXE_SC_OP;

    always_comb begin
        assign mem2_o = mem1_i;
        if (mem_load_op && data_ok) mem2_o.wdata = cache_data;
    end

    assign mem2_data_forward = {
        mem_load_op, data_ok, mem1_i.wreg, mem1_i.waddr, mem1_i.wdata, cache_data
    };



endmodule
