`include "axi/axi_interface.sv"
`include "axi/set_clr_reg_with_rst.sv"
`include "core_config.sv"

module axi_read_channel
    import core_config::*;
#(
    parameter ID = 0
) (
    input logic clk,
    input logic rst,

    input logic new_request,
    input logic uncached,
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [2:0] size,
    output logic [AXI_DATA_WIDTH-1:0] data_out,
    output logic ready_out,
    output logic rvalid_out,

    // AXI
    // ar 
    input logic arready,
    output logic arvalid,
    output logic [7:0] arid,
    output logic [7:0] arlen,
    output logic [1:0] arburst,
    output logic [2:0] arsize,
    output logic [ADDR_WIDTH-1:0] araddr,
    output logic [3:0] arcache,

    // r
    output logic rready,
    input logic rvalid,
    input logic rlast,
    input logic [7:0] rid,
    input logic [AXI_DATA_WIDTH-1:0] rdata,
    input logic [1:0] rresp


);

    // Signals
    logic ready;

    // ID
    assign arid = ID;


    always_ff @(posedge clk) begin
        if (new_request) begin
            arsize  <= size;
            araddr  <= addr;
            arcache <= uncached ? 4'b0000 : 4'b1111;
        end
    end

    // Read Constants
    assign arlen   = 0;
    assign arburst = 1;
    assign rready  = 1;

    set_clr_reg_with_rst #(
        .SET_OVER_CLR(0),
        .WIDTH(1),
        .RST_VALUE(1)
    ) ready_m (
        .clk,
        .rst,
        .set((rvalid & rid == ID)),
        .clr(new_request),
        .result(ready)
    );
    assign ready_out = ready;

    // read channel
    set_clr_reg_with_rst #(
        .SET_OVER_CLR(1),
        .WIDTH(1),
        .RST_VALUE(0)
    ) arvalid_m (
        .clk,
        .rst,
        .set(new_request),
        .clr(arready),
        .result(arvalid)
    );
    always_ff @(posedge clk) begin
        if (rvalid && rid == ID) data_out <= rdata;
    end
    always_ff @(posedge clk) begin
        rvalid_out <= rvalid && rid == ID;
    end


endmodule
