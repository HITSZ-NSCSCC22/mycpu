`include "defines.v"
module regfile (
    input wire clk,
    input wire rst,

    input wire we,
    input wire [`RegAddrBus] waddr,
    input wire [`RegBus] wdata,

    input wire re1,
    input wire [`RegAddrBus] raddr1,
    output reg [`RegBus] rdata1,

    input wire re2,
    input wire [`RegAddrBus] raddr2,
    output reg [`RegBus] rdata2,

    output wire[1023:0] debug_reg
);
    
reg[`RegBus]  regs[0:`RegNum-1];

assign debug_reg = {regs[31],regs[30],regs[29],regs[28],regs[27],regs[26],regs[25],regs[24],regs[23],regs[22],regs[21],regs[20],regs[19],regs[18],regs[17],regs[16],regs[15],regs[14],regs[13],regs[12],regs[11],regs[10],regs[9],regs[8],regs[7],regs[6],regs[5],regs[4],regs[3],regs[2],regs[1],regs[0]};

always @ (posedge clk)begin
    if (rst == `RstEnable)begin
        regs[31] <= `ZeroWord;
        regs[30] <= `ZeroWord;
        regs[29] <= `ZeroWord;
        regs[28] <= `ZeroWord;
        regs[27] <= `ZeroWord;
        regs[26] <= `ZeroWord;
        regs[25] <= `ZeroWord;
        regs[24] <= `ZeroWord;
        regs[23] <= `ZeroWord;
        regs[22] <= `ZeroWord;
        regs[21] <= `ZeroWord;
        regs[20] <= `ZeroWord;
        regs[19] <= `ZeroWord;
        regs[18] <= `ZeroWord;
        regs[17] <= `ZeroWord;
        regs[16] <= `ZeroWord;
        regs[15] <= `ZeroWord;
        regs[14] <= `ZeroWord;
        regs[13] <= `ZeroWord;
        regs[12] <= `ZeroWord;
        regs[11] <= `ZeroWord;
        regs[10] <= `ZeroWord;
        regs[9] <= `ZeroWord;
        regs[8] <= `ZeroWord;
        regs[7] <= `ZeroWord;
        regs[6] <= `ZeroWord;
        regs[5] <= `ZeroWord;
        regs[4] <= `ZeroWord;
        regs[3] <= `ZeroWord;
        regs[2] <= `ZeroWord;
        regs[1] <= `ZeroWord;
        regs[0] <= `ZeroWord;
    end else if ((we == `WriteEnable) && !(waddr == `RegNumLog2'h0))
          regs[waddr] <= wdata;
    
end

  always @ (*)
    begin
      if (rst == `RstEnable)
        rdata1 = `ZeroWord;
      else if (raddr1 == `RegNumLog2'h0)
        rdata1 = `ZeroWord;
      else if ((raddr1 == waddr) && (we == `WriteEnable) && (re1 == `ReadEnable))
        rdata1 = wdata;
      else if (re1 == `ReadEnable)
        rdata1 = regs[raddr1];
      else
        rdata1 = `ZeroWord;
    end

  always @ (*)
    begin
      if (rst == `RstEnable)
        rdata2 = `ZeroWord;
      else if (raddr2 == `RegNumLog2'h0)
        rdata2 = `ZeroWord;
      else if ((raddr2 == waddr) && (we == `WriteEnable) && (re2 == `ReadEnable))
        rdata2 = wdata;
      else if (re2 == `ReadEnable)
        rdata2 = regs[raddr2];
      else
        rdata2 = `ZeroWord;
    end

endmodule

