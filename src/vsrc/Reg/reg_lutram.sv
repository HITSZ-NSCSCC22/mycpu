`include "defines.sv"
`include "core_config.sv"

module reg_lutram
    import core_config::*;
(
    input logic clk,

    input wen,
    input [$clog2(REGNUM)-1:0] waddr,
    input [DATA_WIDTH-1:0] wdata,

    input [$clog2(REGNUM)-1:0] raddr,
    output [DATA_WIDTH-1:0] rdata
);

    (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] ram[0:REGNUM-1];

    always_ff @(posedge clk) begin
        if (wen) ram[waddr] <= wdata;
    end

    assign rdata = ram[raddr];

endmodule
