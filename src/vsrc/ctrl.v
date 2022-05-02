`include "defines.v"
module ctrl (
    input wire clk,
    input wire rst,
    input wire stallreq_from_id_1,
    input wire stallreq_from_ex_1,
    input wire stallreq_from_id_2,
    input wire stallreq_from_ex_2,

    input wire idle_stallreq,
    input wire has_int_stallreq,
    input wire [1:0] excepttype_i_1,
    input wire [1:0] excepttype_i_2,


    output reg [6:0] stall1,
    output reg [6:0] stall2,
    output reg [`RegBus] new_pc,
    output reg flush
);

    wire rst_n = ~rst;

    always @(*) begin
        if (!rst_n) begin
            flush  = 1'b0;
            new_pc = `ZeroWord;
        end else if (excepttype_i_1 != 0) begin
            flush = 1'b1;
            case (excepttype_i_1)
                2'b01: new_pc = 32'h0000000c;
                2'b10: new_pc = 32'h0000000c;
                default: begin
                end
            endcase
        end else if (excepttype_i_2 != 0) begin
            flush = 1'b1;
            case (excepttype_i_2)
                2'b01: new_pc = 32'h0000000c;
                2'b10: new_pc = 32'h0000000c;
                default: begin
                end
            endcase
        end else begin
            flush  = 1'b0;
            new_pc = `ZeroWord;
        end
    end

    always @(*) begin
        if (!rst_n) stall1 = 7'b0000000;
        else if (idle_stallreq) stall1 = 7'b1111111;
        else if (stallreq_from_ex_1 == `Stop || has_int_stallreq == `Stop) stall1 = 7'b0011111;
        else if (stallreq_from_id_1 == `Stop) stall1 = 7'b0011111;
        else stall1 = 7'b0000000;
    end

    always @(*) begin
        if (!rst_n) stall2 = 7'b0000000;
        else if (idle_stallreq) stall2 = 7'b1111111;
        else if (stallreq_from_ex_2 == `Stop || has_int_stallreq == `Stop) stall2 = 7'b0011111;
        else if (stallreq_from_id_2 == `Stop) stall2 = 7'b0011111;
        else stall2 = 7'b0000000;
    end


endmodule  //ctrl
