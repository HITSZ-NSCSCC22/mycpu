module conctrol #(
    parameter FE_ADDR_W   = 32,       //Address width - width of the Master's entire access address (including the LSBs that are discarded, but discarding the Controller's)
    parameter FE_DATA_W = 32,
    parameter FE_NBYTES = FE_DATA_W / 8
) (
    input logic clk,
    input logic rst,

    input logic cpu_valid,
    input logic [FE_ADDR_W-1:0] cpu_addr,
    input logic [FE_DATA_W-1:0] cpu_wdata,
    input logic [FE_NBYTES-1:0] cpu_wstrb,
    output logic [FE_DATA_W-1:0] cpu_rdata,
    output logic cpu_ready,

    output logic dcache_valid,
    output logic [FE_ADDR_W-1:0] dcache_addr,
    output logic [FE_DATA_W-1:0] dcache_wdata,
    output logic [FE_NBYTES-1:0] dcache_wstrb,
    input logic [FE_DATA_W-1:0] dcache_rdata,
    input logic dcache_ready

);

    always_ff @(posedge clk) begin
        if (rst) begin
            dcache_valid <= 0;
            dcache_addr  <= 0;
            dcache_wdata <= 0;
            dcache_wstrb <= 0;
        end else if (cpu_valid) begin
            dcache_valid <= 1;
            dcache_addr  <= cpu_addr;
            dcache_wdata <= cpu_wdata;
            dcache_wstrb <= cpu_wstrb;
        end else if (dcache_ready) begin
            dcache_valid <= 0;
            dcache_addr  <= 0;
            dcache_wdata <= 0;
            dcache_wstrb <= 0;
        end else begin
            dcache_valid <= dcache_valid;
            dcache_addr  <= dcache_addr;
            dcache_wdata <= dcache_wdata;
            dcache_wstrb <= dcache_wstrb;
        end
    end


    assign cpu_rdata = dcache_rdata;
    assign cpu_ready = dcache_ready;

endmodule
