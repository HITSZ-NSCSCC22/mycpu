`include "vsrc/defines.v"

module ram (
    input clock,
    input reset,
    input wire branch_flag_i,
    input wire ce,
    input wire[`InstAddrBus] raddr,
    output reg[`InstBus] rdata,
    input wire[`RegBus] waddr,
    input wire[`RegBus] wdata,
    input wire wen
  );

  reg[`InstBus]  mem[0:`InstMemNum-1];

  wire [`InstAddrBus] tmp_addr;
  assign tmp_addr = raddr - 32'h1c000000;
  
  initial
    $readmemh ("D:/cpu-test/latest/mycpu/la_code/inst_rom.data", mem);

  always @ (posedge clock)
    begin
      if (ce == `ChipDisable)
        rdata <= `ZeroWord;
      else if(branch_flag_i)    rdata<=`ZeroWord;
      else
        rdata <= mem[tmp_addr[`InstMemNumLog2+1:2]];
    end

endmodule
