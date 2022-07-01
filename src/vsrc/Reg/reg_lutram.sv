`include "defines.sv"

module reg_lutram(
    input logic clk,

    input wen,
    input [`RegAddrBus] waddr,
    input [`RegBus] wdata,

    input [`RegAddrBus] raddr,
    output [`RegBus] rdata
);

reg [`RegBus] ram[0:`RegNum-1];

always_ff @( posedge clk ) begin 
    if(wen)
        ram[waddr] <= wdata;
end

assign rdata = ram[raddr];

endmodule
