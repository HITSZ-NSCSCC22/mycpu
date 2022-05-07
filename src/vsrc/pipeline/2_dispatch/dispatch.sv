
`include "pipeline_defines.sv"

module dispatch #(
    parameter DECODE_WIDTH = 2
) (
    input logic clk,
    input logic rst,

    // <- ID
    input id_dispatch_struct [DECODE_WIDTH-1:0] id_i,

    // Dispatch Port
    output logic ex_aluop_o
);

endmodule
