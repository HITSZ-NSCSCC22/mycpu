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
    input wire wen,
    input wire [6:0]stall,
    input wire flush
  );

  reg[`InstBus]  mem[0:`InstMemNum-1];

  wire [`InstAddrBus] tmp_addr;
  assign tmp_addr = raddr - 32'h1c000000;
  
  initial
    $readmemh ("D:/Linnux_LongXin/Share/LoongArch/inst_rom.data", mem);

  always @ (posedge clock)
    begin
      if (ce == `ChipDisable)
        rdata <= `ZeroWord;
      else if(branch_flag_i)    rdata<=`ZeroWord;
      else if(flush) rdata<=`ZeroWord;
      else if(stall[0]) rdata<=rdata;
      else
        rdata <= mem[tmp_addr[`InstMemNumLog2+1:2]];
    end

endmodule