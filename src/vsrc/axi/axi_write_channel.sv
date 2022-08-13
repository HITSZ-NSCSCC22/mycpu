`include "axi/axi_interface.sv"
`include "axi/set_clr_reg_with_rst.sv"
`include "core_config.sv"

module axi_write_channel
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
    input logic [AXI_DATA_WIDTH-1:0] data_in,
    input logic [(AXI_DATA_WIDTH/8)-1:0] wstrb_in,
    output logic ready_out,
    output logic bvalid_out,

    // AXI 
    // aw
    input logic awready,
    output logic awvalid,
    output logic [7:0] awid,
    output logic [7:0] awlen,
    output logic [1:0] awburst,
    output logic [2:0] awsize,
    output logic [ADDR_WIDTH-1:0] awaddr,
    output logic [3:0] awcache,
    // w
    input logic wready,
    output logic wvalid,
    output logic wlast,
    output logic [AXI_DATA_WIDTH-1:0] wdata,
    output logic [(AXI_DATA_WIDTH/8)-1:0] wstrb,
    output logic [7:0] wid,
    // b
    output logic bready,
    input logic bvalid,
    input logic [7:0] bid,
    input logic [1:0] bresp

);

    // Signals
    logic ready;

    // ID
    assign awid = ID;
    assign wid  = ID;

    always_ff @(posedge clk) begin
        if (new_request) begin
            awsize  <= size;
            awaddr  <= addr;
            wdata   <= data_in;
            wstrb   <= wstrb_in;
            awcache <= uncached ? 4'b0000 : 4'b1111;
        end
    end

    // Write Constants
    assign awlen   = 0;
    assign awburst = 1;
    assign bready  = 1;

    set_clr_reg_with_rst #(
        .SET_OVER_CLR(0),
        .WIDTH(1),
        .RST_VALUE(1)
    ) ready_m (
        .clk,
        .rst,
        .set((bvalid & bid == ID)),
        .clr(new_request),
        .result(ready)
    );

    assign ready_out = ready;
    always_ff @(posedge clk) begin
        if (rst) bvalid_out <= 0;
        else bvalid_out <= bvalid && bid == ID;
    end

    set_clr_reg_with_rst #(
        .SET_OVER_CLR(1),
        .WIDTH(1),
        .RST_VALUE(0)
    ) awvalid_m (
        .clk,
        .rst,
        .set(new_request),
        .clr(awready),
        .result(awvalid)
    );

    set_clr_reg_with_rst #(
        .SET_OVER_CLR(1),
        .WIDTH(1),
        .RST_VALUE(0)
    ) wvalid_m (
        .clk,
        .rst,
        .set(new_request),
        .clr(wready),
        .result(wvalid)
    );
    assign wlast = wvalid;

endmodule
