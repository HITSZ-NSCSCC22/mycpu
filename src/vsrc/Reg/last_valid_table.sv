`include "defines.sv"

module last_valid_table #(
    parameter WRITE_PORTS = 2,
    parameter READ_PORTS = 4
)(
    input logic clk,

    input logic [WRITE_PORTS-1:0]we,
    input logic [WRITE_PORTS-1:0][`RegAddrBus] waddr,

    input logic [READ_PORTS-1:0][`RegAddrBus] raddr,
    output logic [READ_PORTS-1:0]rdata
);

logic [`RegBus] ram;


//写入数据时，把对应的位置标记，第一个写入标记为0，第二个写入标记为1
generate
    for(genvar i=0;i<WRITE_PORTS;i=i+1)begin
        always_ff @( posedge clk ) begin 
            if(we[i])
                ram[waddr[i]] <= i ;
        end
    end
endgenerate

generate
    for(genvar i=0;i<READ_PORTS;i=i+1)begin
        assign rdata[i] = ram[raddr[i]];
    end
endgenerate

endmodule
