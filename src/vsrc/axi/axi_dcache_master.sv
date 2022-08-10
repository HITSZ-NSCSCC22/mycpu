`include "axi/axi_interface.sv"
`include "axi/set_clr_reg_with_rst.sv"
`include "core_config.sv"
module axi_dcache_master
    import core_config::*;
#(
    parameter ID = 0
) (
    input logic clk,
    input logic rst,

    axi_interface.master m_axi,
    input logic new_request,
    input logic we,
    input logic uncached,
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [2:0] size,
    input logic [AXI_DATA_WIDTH-1:0] data_in,
    input logic [(AXI_DATA_WIDTH/8)-1:0] wstrb,
    output logic ready_out,
    output logic rvalid_out,
    output logic wvalid_out,
    output logic [AXI_DATA_WIDTH-1:0] data_out

);
    logic ready;

    // AXI ID
    assign m_axi.arid = ID;
    assign m_axi.awid = ID;

    //read constants
    assign m_axi.arlen = 0;  // 1 request
    assign m_axi.arburst = 0;  // burst type does not matter
    assign m_axi.rready = 1;  //always ready to receive data

    always_ff @(posedge clk) begin
        if (new_request) begin
            m_axi.araddr  <= addr;
            m_axi.arsize  <= size;
            m_axi.awsize  <= size;
            m_axi.awaddr  <= addr;
            m_axi.wdata   <= data_in;
            m_axi.wstrb   <= wstrb;
            m_axi.arcache <= uncached ? 4'b0000 : 4'b1110;
            m_axi.awcache <= uncached ? 4'b0000 : 4'b1110;
        end
    end

    //write constants
    assign m_axi.awlen   = 0;
    assign m_axi.awburst = 0;
    assign m_axi.bready  = 1;

    set_clr_reg_with_rst #(
        .SET_OVER_CLR(0),
        .WIDTH(1),
        .RST_VALUE(1)
    ) ready_m (
        .clk,
        .rst,
        .set((m_axi.rvalid & m_axi.rid == ID) | (m_axi.bvalid & m_axi.bid == ID)),
        .clr(new_request),
        .result(ready)
    );
    assign ready_out = ready;

    always_ff @(posedge clk) begin
        if (rst) rvalid_out <= 0;
        else rvalid_out <= m_axi.rvalid;
    end

    always_ff @(posedge clk) begin
        if (rst) wvalid_out <= 0;
        else wvalid_out <= m_axi.bvalid;
    end

    //read channel
    set_clr_reg_with_rst #(
        .SET_OVER_CLR(1),
        .WIDTH(1),
        .RST_VALUE(0)
    ) arvalid_m (
        .clk,
        .rst,
        .set(new_request & ~we),
        .clr(m_axi.arready),
        .result(m_axi.arvalid)
    );

    always_ff @(posedge clk) begin
        if (m_axi.rvalid) data_out <= m_axi.rdata;
    end

    //write channel
    set_clr_reg_with_rst #(
        .SET_OVER_CLR(1),
        .WIDTH(1),
        .RST_VALUE(0)
    ) awvalid_m (
        .clk,
        .rst,
        .set(new_request & we),
        .clr(m_axi.awready),
        .result(m_axi.awvalid)
    );

    set_clr_reg_with_rst #(
        .SET_OVER_CLR(1),
        .WIDTH(1),
        .RST_VALUE(0)
    ) wvalid_m (
        .clk,
        .rst,
        .set(new_request & we),
        .clr(m_axi.wready),
        .result(m_axi.wvalid)
    );
    assign m_axi.wlast = m_axi.wvalid;

endmodule

