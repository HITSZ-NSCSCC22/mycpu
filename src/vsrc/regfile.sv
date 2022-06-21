`include "defines.sv"

// Regfile is the architectural register file
// No hardware reset to generate LUTRAM, is allowed in manual
module regfile #(
    parameter READ_PORTS = 4
) (
    input wire clk,

    input wire [`InstAddrBus] pc_i_1,
    input wire we_1,
    input wire [`RegAddrBus] waddr_1,
    input wire [`RegBus] wdata_1,
    input wire [`InstAddrBus] pc_i_2,
    input wire we_2,
    input wire [`RegAddrBus] waddr_2,
    input wire [`RegBus] wdata_2,

    // Read signals, all packed
    input logic [READ_PORTS-1:0] read_valid_i,
    input logic [READ_PORTS-1:0][`RegAddrBus] read_addr_i,
    output logic [READ_PORTS-1:0][`RegBus] read_data_o
);

    // Used in difftest, should named regs, IMPORTANT!!
    reg [`RegBus] regs[0:`RegNum-1];

    // Write Logic
    always @(posedge clk) begin
        begin  //同时写入一个位置，将后面的写入
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

    // Read Logic
    always_comb begin : read_comb
        for (integer i = 0; i < READ_PORTS; i++) begin
            if (read_addr_i[i] == 0) read_data_o[i] = `ZeroWord;  // r0 is always zero
            else if (waddr_2 == read_addr_i[i] && we_2)
                read_data_o[i] = wdata_2;  // port 2 has higher priority
            else if (waddr_1 == read_addr_i[i] && we_1) read_data_o[i] = wdata_1;
            else if (read_valid_i[i]) read_data_o[i] = regs[read_addr_i[i]];  // Read reg when valid
            else read_data_o[i] = `ZeroWord;  // Else zero
        end
    end

endmodule

