`include "pipeline_defines.sv"

module ex_mem (
    input logic clk,
    input logic rst,
    input logic excp_flush,
    input logic ertn_flush,

    input  ex_mem_struct ex_o,
    output ex_mem_struct mem_i,

    // Stall & flush
    input logic stall,
    input logic flush,

    input logic [`RegBus] ex_current_inst_address,
    input logic excp_i,
    input logic [9:0] excp_num_i,

    output reg [`RegBus] mem_current_inst_address,
    output reg excp_o,
    output reg [9:0] excp_num_o
);

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            mem_i <= 0;
            mem_current_inst_address <= `ZeroWord;
            excp_o <= 1'b0;
            excp_num_o <= 10'b0;
        end else if (flush == 1'b1 || excp_flush == 1'b1 || ertn_flush == 1'b1) begin
            mem_i <= 0;
            mem_current_inst_address <= `ZeroWord;
            excp_o <= 1'b0;
            excp_num_o <= 10'b0;
        end else
        if (stall == `Stop) begin
        end else begin
            mem_i <= ex_o;
            mem_current_inst_address <= ex_current_inst_address;
            excp_o <= excp_i;
            excp_num_o <= excp_num_i;
        end
    end

endmodule
