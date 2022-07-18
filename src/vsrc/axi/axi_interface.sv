//`ifndef AXI_INTERFACE_SV
//`define AXI_INTERFACE_SV
`include "core_config.sv"

interface axi_interface;

    import core_config::*;

    logic arready;
    logic arvalid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0] arlen;
    logic [2:0] arsize;
    logic [1:0] arburst;
    logic [3:0] arcache;
<<<<<<< HEAD
    logic [5:0] arid;
    logic [2:0] arprot;
    logic [1:0] arlock;
=======
    logic [3:0] arid;
>>>>>>> AXI128

    //read data
    logic rready;
    logic rvalid;
    logic [AXI_DATA_WIDTH-1:0] rdata;
    logic [1:0] rresp;
    logic rlast;
    logic [3:0] rid;

    //Write channel
    //write address
    logic awready;
    logic awvalid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0] awlen;
    logic [2:0] awsize;
    logic [1:0] awburst;
    logic [3:0] awcache;
<<<<<<< HEAD
    logic [5:0] awid;
    logic [2:0] awprot;
    logic [1:0] awlock;
=======
    logic [3:0] awid;
>>>>>>> AXI128

    //write data
    logic wready;
    logic wvalid;
    logic [AXI_DATA_WIDTH-1:0] wdata;
    logic [(AXI_DATA_WIDTH/8)-1:0] wstrb;
    logic wlast;

    //write response
    logic bready;
    logic bvalid;
    logic [1:0] bresp;
    logic [3:0] bid;

    modport master(
        input arready, rvalid, rdata, rresp, rlast, rid, awready, wready, bvalid, bresp, bid,
        output arvalid, araddr, arlen, arsize, arburst, arcache, arid,arprot,arlock,
         rready,
          awvalid, awaddr, awlen, awsize, awburst, awcache, awid,awprot,awlock,
                      wvalid, wdata, wstrb, wlast, bready
    );

    modport slave(
        input arvalid, araddr, arlen, arsize, arburst, arcache,arprot,arlock,
            rready,
            awvalid, awaddr, awlen, awsize, awburst, awcache,arid,awlock,awprot,
            wvalid, wdata, wstrb, wlast, awid,
            bready,
        output arready, rvalid, rdata, rresp, rlast, rid, awready, wready, bvalid, bresp, bid
    );

endinterface
//`endif
