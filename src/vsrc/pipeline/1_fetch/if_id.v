`include "../../defines.v"
module if_id (
    input wire clk,
    input wire rst,

    input wire instr_invalid,
    input wire[`InstAddrBus] if_pc_i,
    input wire[`InstAddrBus] if_inst_i,
    output reg[`InstAddrBus] id_pc_o,
    output reg[`InstBus] id_inst_o
  );

  integer i;

  reg[`InstBus] fetch_queue[0:`CacheLatency];

  always @(posedge clk)
    begin
      if(rst == `RstEnable)
        begin
          id_pc_o <= `ZeroWord;
          id_inst_o <= `ZeroWord;
          for (i = 0; i<=`CacheLatency; i = i+ 1)
            begin
              fetch_queue[i] <= 32'h0;
            end
        end
      else if(instr_invalid)
        begin
          id_pc_o <= `ZeroWord;
          id_inst_o <= `ZeroWord;
          // Pump normally
          for(i = 1; i<= `CacheLatency; i = i + 1)
            begin
              fetch_queue[i] <= fetch_queue[i-1];
            end
        end
      else
        begin
          id_inst_o <= if_inst_i;
          id_pc_o <= fetch_queue[`CacheLatency];
          for(i = 1; i<= `CacheLatency; i = i + 1)
            begin
              fetch_queue[i] <= fetch_queue[i-1];
            end
          fetch_queue[0] = if_pc_i;
        end
    end

endmodule
