//to keep PC and inst_o corresponding
`include "defines.v"
module pc2_reg (
    input wire clk,
    input wire rst,
    input wire [`InstAddrBus]pc,

    input wire branch_flag_i,
    output reg[`InstAddrBus] pc2
);
 
always @(posedge clk) begin
    if(rst)
        pc2 <= 32'h0;
    else if(branch_flag_i == `Branch)
        pc2 <= 0;
    else
        pc2 <= pc;
end

endmodule