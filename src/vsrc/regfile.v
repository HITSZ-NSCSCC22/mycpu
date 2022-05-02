`include "defines.v"
module regfile (
    input wire clk,
    input wire rst,

    input wire [`InstAddrBus] pc_i_1,
    input wire we_1,
    input wire [`RegAddrBus] waddr_1,
    input wire [`RegBus] wdata_1,
    input wire [`InstAddrBus] pc_i_2,
    input wire we_2,
    input wire [`RegAddrBus] waddr_2,
    input wire [`RegBus] wdata_2,

    input wire re1_1,
    input wire [`RegAddrBus] raddr1_1,
    output reg [`RegBus] rdata1_1,
    input wire re1_2,
    input wire [`RegAddrBus] raddr1_2,
    output reg [`RegBus] rdata1_2,

    input wire re2_1,
    input wire [`RegAddrBus] raddr2_1,
    output reg [`RegBus] rdata2_1,
    input wire re2_2,
    input wire [`RegAddrBus] raddr2_2,
    output reg [`RegBus] rdata2_2
);

    reg [`RegBus] regs[0:`RegNum-1];

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            for (integer i = 0; i < 32; i = i + 1) begin
                regs[i] <= 0;
            end
        end else begin  //同时写入一个位置，将后面的写入
            if ((we_1 == `WriteEnable) && (we_2 == `WriteEnable) && waddr_1 == waddr_2) begin
                if (pc_i_1 > pc_i_2) regs[waddr_1] <= wdata_1;
                else regs[waddr_1] <= wdata_2;
            end else begin
                if ((we_1 == `WriteEnable) && !(waddr_1 == `RegNumLog2'h0))
                    regs[waddr_1] <= wdata_1;
                if ((we_2 == `WriteEnable) && !(waddr_2 == `RegNumLog2'h0))
                    regs[waddr_2] <= wdata_2;
            end
        end
    end

    always @(*) begin
        if (rst == `RstEnable) rdata1_1 = `ZeroWord;
        else if (raddr1_1 == `RegNumLog2'h0) rdata1_1 = `ZeroWord;
        else if ((raddr1_1 == waddr_1) && (we_1 == `WriteEnable) && (re1_1 == `ReadEnable))
            rdata1_1 = wdata_1;
        else if ((raddr1_1 == waddr_2) && (we_2 == `WriteEnable) && (re1_1 == `ReadEnable))
            rdata1_1 = wdata_2;
        else if (re1_1 == `ReadEnable) rdata1_1 = regs[raddr1_1];
        else rdata1_1 = `ZeroWord;
    end

    always @(*) begin
        if (rst == `RstEnable) rdata1_2 = `ZeroWord;
        else if (raddr1_2 == `RegNumLog2'h0) rdata1_2 = `ZeroWord;
        else if ((raddr1_2 == waddr_1) && (we_1 == `WriteEnable) && (re1_2 == `ReadEnable))
            rdata1_2 = wdata_1;
        else if ((raddr1_2 == waddr_2) && (we_2 == `WriteEnable) && (re1_2 == `ReadEnable))
            rdata1_2 = wdata_2;
        else if (re1_2 == `ReadEnable) rdata1_2 = regs[raddr1_2];
        else rdata1_2 = `ZeroWord;
    end

    always @(*) begin
        if (rst == `RstEnable) rdata2_1 = `ZeroWord;
        else if (raddr2_1 == `RegNumLog2'h0) rdata2_1 = `ZeroWord;
        else if ((raddr2_1 == waddr_1) && (we_1 == `WriteEnable) && (re2_1 == `ReadEnable))
            rdata2_1 = wdata_1;
        else if ((raddr2_1 == waddr_2) && (we_2 == `WriteEnable) && (re2_1 == `ReadEnable))
            rdata2_1 = wdata_2;
        else if (re2_1 == `ReadEnable) rdata2_1 = regs[raddr2_1];
        else rdata2_1 = `ZeroWord;
    end

    always @(*) begin
        if (rst == `RstEnable) rdata2_2 = `ZeroWord;
        else if (raddr2_2 == `RegNumLog2'h0) rdata2_2 = `ZeroWord;
        else if ((raddr2_2 == waddr_1) && (we_1 == `WriteEnable) && (re2_2 == `ReadEnable))
            rdata2_2 = wdata_1;
        else if ((raddr2_2 == waddr_2) && (we_2 == `WriteEnable) && (re2_2 == `ReadEnable))
            rdata2_2 = wdata_2;
        else if (re2_1 == `ReadEnable) rdata2_2 = regs[raddr2_2];
        else rdata2_2 = `ZeroWord;
    end

endmodule

