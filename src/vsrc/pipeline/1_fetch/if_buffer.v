//to keep PC and inst_o corresponding
`include "defines.v"
module if_buffer (
    input wire clk,
    input wire rst,
    input wire [`InstAddrBus] pc_i,
    input wire flush,
    input wire stall,
    input wire excp_flush,
    input wire ertn_flush,

    input wire branch_flag_i,
    output reg [`InstAddrBus] pc_o,
    output reg pc_valid,

    input wire excp_i,
    input wire [3:0] excp_num_i,
    output reg excp_o,
    output reg [3:0] excp_num_o
);

    always @(posedge clk) begin
        if (rst) begin
            pc_o <= `ZeroWord;
            pc_valid <= `InstInvalid;
            excp_o <= 1'b0;
            excp_num_o <= 4'b0;
        end else if (branch_flag_i == `Branch) begin
            pc_o <= `ZeroWord;
            pc_valid <= `InstInvalid;
            excp_o <= 1'b0;
            excp_num_o <= 4'b0;
        end else if (flush == 1'b1 || excp_flush == 1'b1 || ertn_flush == 1'b1) begin
            pc_o <= `ZeroWord;
            pc_valid <= `InstInvalid;
            excp_o <= 1'b0;
            excp_num_o <= 4'b0;
        end
      else if(stall == `Stop) // Stall, hold output
        begin
            pc_o <= pc_o;
            pc_valid <= pc_valid;
            excp_o <= excp_i;
            excp_num_o <= excp_num_i;
        end else begin
            pc_o <= pc_i;
            pc_valid <= `InstValid;
            excp_o <= excp_i;
            excp_num_o <= excp_num_i;
        end
    end

endmodule
