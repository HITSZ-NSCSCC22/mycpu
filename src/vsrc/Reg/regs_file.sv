`include "defines.sv"
`include "Reg/last_valid_table.sv"
`include "Reg/reg_lutram.sv"

// Regfile is the architectural register file
// No hardware reset to generate LUTRAM, is allowed in manual
module regs_file #(
    parameter WRITE_PORTS = 2,
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

    logic [READ_PORTS-1:0] read_valid_bit;        
    logic [WRITE_PORTS-1:0][READ_PORTS-1:0][`RegBus] rdata_buffer;

    last_valid_table u_lvt(
        .clk(clk),
        .we({we_2,we_1}),
        .waddr({waddr_2,waddr_1}),
        .raddr(read_addr_i),
        .rdata(read_valid_bit)
    );


    for (genvar i = 0; i < READ_PORTS; i = i + 1) begin
        reg_lutram u_reg_lutram_1 (
            .clk(clk),

            //write-port
            .wen(we_1),
            .waddr(waddr_1),
            .wdata(wdata_1),

            .raddr(read_addr_i[i]),
            .rdata(rdata_buffer[0][i])
        );
    end

    for (genvar i = 0; i < READ_PORTS; i = i + 1) begin
        reg_lutram u_reg_lutram_2 (
            .clk(clk),

            //write-port
            .wen(we_2),
            .waddr(waddr_2),
            .wdata(wdata_2),

            .raddr(read_addr_i[i]),
            .rdata(rdata_buffer[1][i])
        );
    end

    // Read Logic
    always_comb begin : read_comb
        for (integer i = 0; i < READ_PORTS; i++) begin
            if (read_addr_i[i] == 0) read_data_o[i] = `ZeroWord;  // r0 is always zero
            else if (waddr_2 == read_addr_i[i] && we_2)read_data_o[i] = wdata_2;  // port 2 has higher priority
            else if (waddr_1 == read_addr_i[i] && we_1) read_data_o[i] = wdata_1;
            else if (read_valid_i[i]) read_data_o[i] = read_valid_bit[i] ? rdata_buffer[1][i] : rdata_buffer[0][i];  // Read reg when valid
            else read_data_o[i] = `ZeroWord;  // Else zero
        end
    end

endmodule
