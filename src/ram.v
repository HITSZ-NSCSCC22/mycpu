`include "vsrc/defines.v"

module ram (
    input clock,
    input reset,
    input wire branch_flag_i,
    input wire ce,
    input wire[`InstAddrBus] raddr_1,
    input wire[`InstAddrBus] raddr_2,
    output reg[`InstBus] rdata_1,
    output reg[`InstBus] rdata_2,
    input wire[`RegBus] waddr,
    input wire[`RegBus] wdata,
    input wire wen
  );

  reg[`InstBus]  mem[0:`InstMemNum-1];

  wire [`InstAddrBus] tmp_addr_1;
  wire [`InstAddrBus] tmp_addr_2;
  assign tmp_addr_1 = raddr_1 - 32'h1c000000;
  assign tmp_addr_2 = raddr_2 - 32'h1c000000;
  
  initial
    $readmemh ("D:/cpu-test/latest/mycpu/la_code/inst_rom.data", mem);

  always @ (posedge clock)
    begin
      if (ce == `ChipDisable)
        rdata_1 <= `ZeroWord;
      else if(branch_flag_i)    rdata_1<=`ZeroWord;
      else
        rdata_1 <= mem[tmp_addr_1[`InstMemNumLog2+1:2]];
    end

  always @ (posedge clock)
    begin
      if (ce == `ChipDisable)
        rdata_2 <= `ZeroWord;
      else if(branch_flag_i)    rdata_2<=`ZeroWord;
      else
        rdata_2 <= mem[tmp_addr_2[`InstMemNumLog2+1:2]];
    end

endmodule
