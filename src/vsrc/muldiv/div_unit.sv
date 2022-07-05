`include "core_types.sv"
`include "core_config.sv"
`include "defines.sv"

module div_unit (
    input logic clk,
    input logic rst,

    input logic [`RegBus] rs1,
    input logic [`RegBus] rs2,
    input logic [1:0] op,

    input logic div_ack,

    output logic ready,
    output logic done,
    output logic [`RegBus] div_result
);
    
endmodule
