`include "defines.sv"
`include "core_config.sv"

module last_valid_table
    import core_config::*;
#(
    parameter WRITE_PORTS = 2,
    parameter READ_PORTS  = 4
) (
    input logic clk,

    input logic [WRITE_PORTS-1:0] we,
    input logic [WRITE_PORTS-1:0][$clog2(GPR_NUM)-1:0] waddr,

    input logic [READ_PORTS-1:0][$clog2(GPR_NUM)-1:0] raddr,
    output logic [READ_PORTS-1:0] rdata
);

    logic [GPR_NUM-1:0][$clog2(WRITE_PORTS)-1:0] ram;


    // 写入数据时，把寄存器号对应的位置标记为写入的端口号
    // 多端口同时写入，编号越大的端口为最终结果
    always_ff @(posedge clk) begin
        for (integer i = 0; i < WRITE_PORTS; i = i + 1) begin
            if (we[i]) ram[waddr[i]] <= i[$clog2(WRITE_PORTS)-1:0];
        end
    end

    always_comb begin
        for (integer i = 0; i < READ_PORTS; i = i + 1) begin
            rdata[i] = ram[raddr[i]];
        end
    end

endmodule
