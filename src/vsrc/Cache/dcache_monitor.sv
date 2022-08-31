`include "core_config.sv"


module dcache_monitor
    import core_config::*;
(
    input logic clk,
    input logic rst,

    input logic store_valid,
    input logic [ADDR_WIDTH-1:0] store_paddr,
    input logic [DATA_WIDTH-1:0] store_data,

    input logic load_valid,
    input logic [ADDR_WIDTH-1:0] load_paddr,

    input logic axi_rvalid,
    input logic [AXI_DATA_WIDTH-1:0] axi_rdata,

    input logic axi_wvalid,
    input logic [AXI_DATA_WIDTH-1:0] axi_wdata
);

    logic error_r, error_pulse;

    // AXI
    // Read transaction
    logic read_ongoing;
    logic [AXI_DATA_WIDTH-1:0] read_data;

    // Replaced
    logic [AXI_DATA_WIDTH-1:0] replaced_data;


    // RAM
    logic [DCACHE_NSET-1:0][DCACHELINE_WIDTH-1:0] ram;



    // Read trigger a replace
    always_ff @(posedge clk) begin
        if (rst) read_ongoing <= 0;
        else if (axi_rvalid) read_ongoing <= 1;
        else if (store_valid | load_valid) read_ongoing <= 0;
    end
    always_ff @(posedge clk) begin
        if (rst) read_data <= 0;
        else if (axi_rvalid) read_data <= axi_rdata;
    end

    // Replace
    always_ff @(posedge clk) begin
        if (read_ongoing) begin
            if (store_valid) begin
                ram[store_paddr[$clog2(DCACHE_NSET)+3:4]] <= read_data;
                replaced_data <= ram[store_paddr[$clog2(DCACHE_NSET)+3:4]];
            end else if (load_valid) begin
                ram[load_paddr[$clog2(DCACHE_NSET)+3:4]] <= read_data;
                replaced_data <= ram[load_paddr[$clog2(DCACHE_NSET)+3:4]];
            end
        end else if (store_valid) ram[store_paddr[$clog2(DCACHE_NSET)+3:4]] <= store_data;
    end




    // Compare write data
    always_comb begin
        error_pulse = 0;
        if (axi_wvalid) error_pulse = (axi_wdata != replaced_data);
    end


endmodule
