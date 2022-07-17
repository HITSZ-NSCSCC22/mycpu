`timescale 1ns / 1ps
`include "Cache/cache_frontend.sv"
`include "Cache/cache_memory.sv"
`include "Cache/backend.sv"
module dcache #(
    //memory cache's parameters
    parameter FE_ADDR_W = 32,
    parameter FE_DATA_W = 32,
    parameter N_WAYS = 2,
    parameter LINE_OFF_W = 7,
    parameter WORD_OFF_W = 3,
    parameter WTBUF_DEPTH_W = 5,
    //Replacement policy (N_WAYS > 1)
    parameter REP_POLICY = 2,
    //Do NOT change - memory cache's parameters - dependency
    parameter NWAY_W = $clog2(N_WAYS),
    parameter FE_NBYTES = FE_DATA_W / 8,
    parameter FE_BYTE_W = $clog2(FE_NBYTES),
    /*---------------------------------------------------*/
    //Higher hierarchy memory (slave) interface parameters 
    parameter BE_ADDR_W = FE_ADDR_W,
    parameter BE_DATA_W = FE_DATA_W * 4,
    parameter BE_NBYTES = BE_DATA_W / 8,
    parameter BE_BYTE_W = $clog2(BE_NBYTES),
    //Cache-Memory base Offset
    parameter LINE2MEM_W = WORD_OFF_W - $clog2(BE_DATA_W / FE_DATA_W),
    /*---------------------------------------------------*/
    //Write Policy 
    parameter WRITE_POL = 1,
    /*---------------------------------------------------*/
    //Controller's options
    parameter CTRL_ADDR_W = 4,
    parameter CTRL_CACHE = 0,
    parameter CTRL_CNT = 0
) (
    input logic clk,
    input logic rst,
    input logic valid,

    input logic [FE_ADDR_W-1:0] addr,

    input logic [FE_DATA_W-1:0] wdata,
    input logic [FE_NBYTES-1:0] wstrb,
    output logic [FE_DATA_W-1:0] rdata,
    output logic ready,

    input  logic force_inv_i,
    output logic force_inv_o,
    input  logic wtb_empty_i,
    output logic wtb_empty_o,

    output logic                 axi_arvalid,
    output logic [BE_ADDR_W-1:0] axi_araddr,
    output logic [          7:0] axi_arlen,
    output logic [          2:0] axi_arsize,
    output logic [          1:0] axi_arburst,
    output logic [          0:0] axi_arlock,
    output logic [          3:0] axi_arcache,
    output logic [          2:0] axi_arprot,
    output logic [          3:0] axi_arqos,
    output logic [          7:0] axi_arid,
    input  logic                 axi_arready,
    //Read
    input  logic                 axi_rvalid,
    input  logic [BE_DATA_W-1:0] axi_rdata,
    input  logic [          1:0] axi_rresp,
    input  logic                 axi_rlast,
    output logic                 axi_rready,
    // Address Write
    output logic                 axi_awvalid,
    output logic [BE_ADDR_W-1:0] axi_awaddr,
    output logic [          7:0] axi_awlen,
    output logic [          2:0] axi_awsize,
    output logic [          1:0] axi_awburst,
    output logic [          0:0] axi_awlock,
    output logic [          3:0] axi_awcache,
    output logic [          2:0] axi_awprot,
    output logic [          3:0] axi_awqos,
    output logic [          7:0] axi_awid,
    input  logic                 axi_awready,
    //Write
    output logic                 axi_wvalid,
    output logic [BE_DATA_W-1:0] axi_wdata,
    output logic [BE_NBYTES-1:0] axi_wstrb,
    output logic                 axi_wlast,
    input  logic                 axi_wready,
    input  logic                 axi_bvalid,
    input  logic [          1:0] axi_bresp,
    output logic                 axi_bready

);

    logic data_valid, data_ready;
    logic [FE_ADDR_W -1:FE_BYTE_W] data_addr;
    logic [FE_DATA_W-1 : 0] data_wdata, data_rdata;
    logic [         FE_NBYTES-1:0] data_wstrb;

    //stored signals
    logic [FE_ADDR_W -1:FE_BYTE_W] data_addr_reg;
    logic [       FE_DATA_W-1 : 0] data_wdata_reg;
    logic [         FE_NBYTES-1:0] data_wstrb_reg;
    logic                          data_valid_reg;

    //back-end write-channel
    logic write_valid, write_ready;
    logic [FE_ADDR_W-1:FE_BYTE_W + WRITE_POL*WORD_OFF_W] write_addr;
    logic [FE_DATA_W + WRITE_POL*(FE_DATA_W*(2**WORD_OFF_W)-FE_DATA_W)-1 : 0] write_wdata;
    logic [FE_NBYTES-1:0] write_wstrb;

    //back-end read-channel
    logic replace_valid, replace;
    logic [FE_ADDR_W -1:BE_BYTE_W+LINE2MEM_W] replace_addr;
    logic read_valid;
    logic [LINE2MEM_W-1:0] read_addr;
    logic [BE_DATA_W-1:0] read_rdata;

    //cache-control
    logic ctrl_valid, ctrl_ready;
    logic [CTRL_ADDR_W-1:0] ctrl_addr;
    logic wtbuf_full, wtbuf_empty;
    logic write_hit, write_miss, read_hit, read_miss;
    logic [CTRL_CACHE*(FE_DATA_W-1):0] ctrl_rdata;
    logic invalidate;



    assign force_inv_o = invalidate;

    generate
        if (CTRL_CACHE) assign wtb_empty_o = wtbuf_empty;
        else
            assign wtb_empty_out = wtbuf_empty & wtb_empty_i;//to remove unconnected port warning. If unused wtb_empty_in = 1'b1
    endgenerate

    cache_frontend #(
        .FE_ADDR_W (FE_ADDR_W),
        .FE_DATA_W (FE_DATA_W),
        .CTRL_CACHE(CTRL_CACHE)
    ) front_end (
        .clk   (clk),
        .reset (reset),
        //front-end port
        .valid (valid),
        .addr  (addr),
        .wdata (wdata),
        .wstrb (wstrb),
        .rdata (rdata),
        .ready (ready),
        //cache-memory input signals
        .data_valid (data_valid),
        .data_addr  (data_addr),
        //cache-memory output
        .data_rdata (data_rdata),
        .data_ready (data_ready),
        //stored input signals
        .data_valid_reg (data_valid_reg),
        .data_addr_reg  (data_addr_reg),
        .data_wdata_reg (data_wdata_reg),
        .data_wstrb_reg (data_wstrb_reg),
        //cache-control
        .ctrl_valid (ctrl_valid),
        .ctrl_addr  (ctrl_addr),
        .ctrl_rdata (ctrl_rdata),
        .ctrl_ready (ctrl_ready)
    );


    //BLOCK Cache memory & Cache memory block.
    cache_memory #(
        .FE_ADDR_W    (FE_ADDR_W),
        .FE_DATA_W    (FE_DATA_W),
        .BE_DATA_W    (BE_DATA_W),
        .N_WAYS       (N_WAYS),
        .LINE_OFF_W   (LINE_OFF_W),
        .WORD_OFF_W   (WORD_OFF_W),
        .REP_POLICY   (REP_POLICY),
        .WTBUF_DEPTH_W(WTBUF_DEPTH_W),
        .CTRL_CACHE   (CTRL_CACHE),
        .CTRL_CNT     (CTRL_CNT),
        .WRITE_POL    (WRITE_POL)
    ) cache_memory (
        .clk          (clk),
        .reset        (reset),
        //front-end
        //internal data signals
        .valid        (data_valid),
        .addr         (data_addr[FE_ADDR_W-1:BE_BYTE_W+LINE2MEM_W]),
        //.wdata (data_wdata),
        // .wstrb (data_wstrb),
        .rdata        (data_rdata),
        .ready        (data_ready),
        //stored data signals
        .valid_reg    (data_valid_reg),
        .addr_reg     (data_addr_reg),
        .wdata_reg    (data_wdata_reg),
        .wstrb_reg    (data_wstrb_reg),
        //back-end
        //write-through-buffer (write-channel)
        .write_valid  (write_valid),
        .write_addr   (write_addr),
        .write_wdata  (write_wdata),
        .write_wstrb  (write_wstrb),
        .write_ready  (write_ready),
        //cache-line replacement (read-channel)
        .replace_valid(replace_valid),
        .replace_addr (replace_addr),
        .replace      (replace),
        .read_valid   (read_valid),
        .read_addr    (read_addr),
        .read_rdata   (read_rdata),
        //control's signals 
        .wtbuf_empty  (wtbuf_empty),
        .wtbuf_full   (wtbuf_full),
        .write_hit    (write_hit),
        .write_miss   (write_miss),
        .read_hit     (read_hit),
        .read_miss    (read_miss),


        .invalidate(invalidate)

    );

    //BLOCK Back-end & Back-end block.
    backend #(
        .FE_ADDR_W (FE_ADDR_W),
        .FE_DATA_W (FE_DATA_W),
        .BE_ADDR_W (BE_ADDR_W),
        .BE_DATA_W (BE_DATA_W),
        .WORD_OFF_W(WORD_OFF_W),
        .WRITE_POL (WRITE_POL),
    ) back_end (
        .clk(clk),
        .reset(reset),
        //write-through-buffer (write-channel)
        .write_valid(write_valid),
        .write_addr(write_addr),
        .write_wdata(write_wdata),
        .write_wstrb(write_wstrb),
        .write_ready(write_ready),
        //cache-line replacement (read-channel)
        .replace_valid(replace_valid),
        .replace_addr(replace_addr),
        .replace(replace),
        .read_valid(read_valid),
        .read_addr(read_addr),
        .read_rdata(read_rdata),
        //back-end read-channel
        //read address
        .axi_arvalid(axi_arvalid),
        .axi_araddr(axi_araddr),
        .axi_arlen(axi_arlen),
        .axi_arsize(axi_arsize),
        .axi_arburst(axi_arburst),
        .axi_arlock(axi_arlock),
        .axi_arcache(axi_arcache),
        .axi_arprot(axi_arprot),
        .axi_arqos(axi_arqos),
        .axi_arid(axi_arid),
        .axi_arready(axi_arready),
        //read data
        .axi_rvalid(axi_rvalid),
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rlast(axi_rlast),
        .axi_rready(axi_rready),
        //back-end write-channel
        //write address
        .axi_awvalid(axi_awvalid),
        .axi_awaddr(axi_awaddr),
        .axi_awlen(axi_awlen),
        .axi_awsize(axi_awsize),
        .axi_awburst(axi_awburst),
        .axi_awlock(axi_awlock),
        .axi_awcache(axi_awcache),
        .axi_awprot(axi_awprot),
        .axi_awqos(axi_awqos),
        .axi_awid(axi_awid),
        .axi_awready(axi_awready),
        //write data
        .axi_wvalid(axi_wvalid),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wready(axi_wready),
        .axi_wlast(axi_wlast),
        //write response
        .axi_bvalid(axi_bvalid),
        .axi_bresp(axi_bresp),
        .axi_bready(axi_bready)
    );


    //BLOCK Cache control & Cache control block.
    generate
        if (CTRL_CACHE)

            cache_control #(
                .FE_DATA_W(FE_DATA_W),
                .CTRL_CNT (CTRL_CNT)
            ) cache_control (
                .clk   (clk),
                .reset (reset),
                //control's signals
                .valid (ctrl_valid),
                .addr  (ctrl_addr),
                //write data
                .wtbuf_full (wtbuf_full),
`ifdef CTRL_IO
                .wtbuf_empty (wtbuf_empty & wtb_empty_in),
`else
                .wtbuf_empty (wtbuf_empty),
`endif
                .write_hit  (write_hit),
                .write_miss (write_miss),
                .read_hit   (read_hit),
                .read_miss  (read_miss),
                ////////////
                .rdata (ctrl_rdata),
                .ready (ctrl_ready),
                .invalidate (invalidate)
            );
        else begin
            assign ctrl_rdata = 1'bx;
            assign ctrl_ready = 1'bx;
            assign invalidate = 1'b0;
        end  // else: !if(CTRL_CACHE)

    endgenerate


endmodule


