`include "defines.sv"
`include "instr_info.sv"
`include "csr_defines.sv"
`include "pipeline_defines.sv"

// id_dispatch is a sequential logic 
// merge all ID stage output to dispatch stage
//  ID ->                         -> EXE
//  ID -> id_dispatch -> dispatch -> EXE
// 

module id_dispatch #(
    parameter DECODE_WIDTH = 2
) (
    input logic clk,
    input logic rst,

    // Stall & flush
    // <-> Ctrl
    input logic stall,
    input logic flush,

    // <- ID stage
    input id_dispatch_struct [DECODE_WIDTH-1:0] id_i,

    // -> Dispatch stage
    output id_dispatch_struct [DECODE_WIDTH-1:0] dispatch_o
);

    logic rst_n;
    assign rst_n = ~rst;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dispatch_o <= 0;
        end else if (flush) begin
            dispatch_o <= 0;
        end else if (stall) begin
            // Do nothing, hold output
        end else begin
            dispatch_o <= id_i;
        end
    end

endmodule
