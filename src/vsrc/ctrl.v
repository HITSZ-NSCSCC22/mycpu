`include "defines.v"
module ctrl (
    input wire clk,
    input wire rst,
    input wire stallreq_from_id,
    input wire stallreq_from_ex,

    input wire[1:0] excepttype_i,

    output reg[6:0]stall,
    output reg[`RegBus] new_pc,
    output reg flush
  );

  wire rst_n = ~rst;

  always @(posedge clk or negedge rst_n)
    begin
      if (!rst_n)
        begin
          flush <= 1'b0;
          new_pc <= `ZeroWord;
          stall <= 7'b0000000;
        end
      else
        if(excepttype_i != 0)
          begin
            flush <= 1'b1;
            stall <= 7'b0000000;
            case (excepttype_i)
              2'b01:
                new_pc <= 32'h0000000c;
              2'b10:
                new_pc <= 32'h0000000c;
              default:
                begin
                end
            endcase
          end
        else if(stallreq_from_id == `Stop)
          begin
            flush <= 1'b0;
            new_pc <= `ZeroWord;
            stall <= 7'b0011111;
          end
        else if(stallreq_from_ex == `Stop)
          begin
            flush <= 1'b0;
            new_pc <= `ZeroWord;
            stall <= 7'b0011111;
          end
        else
          begin
            flush <= 1'b0;
            new_pc <= `ZeroWord;
            stall <= 7'b0000000;
          end

    end


endmodule //ctrl
