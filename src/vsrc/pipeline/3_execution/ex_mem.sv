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
    input logic flush

);

    csr_write_signal csr_test;
    assign csr_test = mem_i.csr_signal;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            mem_i <= 0;
        end else if (flush == 1'b1 || excp_flush == 1'b1 || ertn_flush == 1'b1) begin
            mem_i <= 0;
        end else if (stall == `Stop) begin
            // Do nothing
        end else begin
            mem_i <= ex_o;
        end
    end

endmodule
