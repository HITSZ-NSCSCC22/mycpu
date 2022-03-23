module ctrl (
    input wire clk,
    input wire rst,
    input wire id_is_branch_instr_i,
    output wire pc_instr_invalid_o,
    output wire if_id_instr_invalid_o
  );

  wire rst_n = ~rst;
  reg [1:0] branch_flush_cnt;

  always @(posedge clk or negedge rst_n)
    begin
      if (!rst_n)
        branch_flush_cnt <= 0;
      else
        if (!(branch_flush_cnt==0))
          branch_flush_cnt <= branch_flush_cnt -1;
        else if(id_is_branch_instr_i)
          branch_flush_cnt <= 1;
        else
          branch_flush_cnt <= branch_flush_cnt;

    end

  assign  pc_instr_invalid_o = id_is_branch_instr_i;
  assign  if_id_instr_invalid_o = id_is_branch_instr_i || (branch_flush_cnt == 1);

endmodule //ctrl
