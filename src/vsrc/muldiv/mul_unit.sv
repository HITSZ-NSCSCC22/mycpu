`include "core_types.sv"
`include "core_config.sv"
`include "defines.sv"

module mul_unit
    import core_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,

    input logic start,
    input logic [`RegBus] rs1,
    input logic [`RegBus] rs2,
    input logic [1:0] op,

    output logic ready,
    output logic done,
    output logic [`RegBus] mul_result

);

    logic signed [63:0] result;
    logic mulh;
    logic valid;


    logic rs1_is_signed, rs2_is_signed;
    logic signed [32:0] rs1_ext, rs2_ext;

    logic stage1_advance;

    assign rs1_is_signed = op[1:0] inside {2'b01, 2'b10};  //MUL doesn't matter
    assign rs2_is_signed = op[1:0] inside {2'b01, 2'b10};  //MUL doesn't matter

    assign rs1_ext = signed'({rs1[31] & rs1_is_signed, rs1});
    assign rs2_ext = signed'({rs2[31] & rs2_is_signed, rs2});

    assign ready = stage1_advance;
    assign stage1_advance = start;

    always_ff @(posedge clk) begin
        if (stage1_advance) begin
            result <= 64'(rs1_ext * rs2_ext);
        end
    end

    assign mulh = (op[1:0] != 2'b01);

    always_ff @(posedge clk) begin
        if (rst) valid <= 0;
        else begin
            valid <= stage1_advance ? 1 : 0;
        end
    end

    assign mul_result = mulh ? result[63:32] : result[31:0];
    assign done = valid;


endmodule
