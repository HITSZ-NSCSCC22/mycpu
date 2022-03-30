`include "defines.v"
module ctrl (
    input wire clk,
    input wire rst,
    input wire id_is_branch_instr_i,
    input wire stallreq_from_id,

    input wire[1:0] excepttype_i,
    
    output reg[`RegBus] new_pc,
    output reg flush,

    output wire pc_instr_invalid_o,
    output wire if_id_instr_invalid_o

  );

  wire rst_n = ~rst;
  reg [1:0] branch_flush_cnt;

  always @(posedge clk or negedge rst_n)
    begin
      if (!rst_n)
        begin
          branch_flush_cnt <= 2'b0;
          flush <= 1'b0;
          new_pc <= `ZeroWord;
        end
      else
        if (!(branch_flush_cnt==0))
          begin
            branch_flush_cnt <= branch_flush_cnt -1;
            flush <= 1'b0;
            new_pc <= `ZeroWord;
          end
        else if(id_is_branch_instr_i)
          begin
            branch_flush_cnt <= 1;
            flush <= 1'b0;
            new_pc <= `ZeroWord;
          end
        else if(excepttype_i != 0)
          begin
            flush <= 1'b1;
            case (excepttype_i)
              2'b01:
                  new_pc <= 32'h00000020;
              2'b10:
                  new_pc <= 32'h00000040;
              default:begin
              end
            endcase
          end
        else
          branch_flush_cnt <= branch_flush_cnt;

    end

  assign  pc_instr_invalid_o = id_is_branch_instr_i;
  assign  if_id_instr_invalid_o = id_is_branch_instr_i || (branch_flush_cnt == 1);

endmodule //ctrl
