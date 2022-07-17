`ifndef DCACHE_CONFIG_SV
`define DCACHE_CONFIG_SV

package dcache_config;

    //memory cache's parameters
    parameter FE_ADDR_W = 32;
    parameter FE_DATA_W = 32;
    parameter N_WAYS = 2;
    parameter LINE_OFF_W = 7;
    parameter WORD_OFF_W = 3;
    parameter WTBUF_DEPTH_W = 5;
    //Replacement policy (N_WAYS > 1)
    parameter REP_POLICY = 2;
    //Do NOT change - memory cache's parameters - dependency
    parameter NWAY_W = $clog2(N_WAYS);
    parameter FE_NBYTES = FE_DATA_W / 8;
    parameter FE_BYTE_W = $clog2(FE_NBYTES);
    /*---------------------------------------------------*/
    //Higher hierarchy memory (slave) interface parameters 
    parameter BE_ADDR_W = FE_ADDR_W;
    parameter BE_DATA_W = FE_DATA_W * 4;
    parameter BE_NBYTES = BE_DATA_W / 8;
    parameter BE_BYTE_W = $clog2(BE_NBYTES);
    //Cache-Memory base Offset
    parameter LINE2MEM_W = WORD_OFF_W - $clog2(BE_DATA_W / FE_DATA_W);
    /*---------------------------------------------------*/
    //Write Policy 
    parameter WRITE_POL = 1;
    /*---------------------------------------------------*/
    //Controller's options
    parameter CTRL_ADDR_W = 4;
    parameter CTRL_CACHE = 0;
    parameter CTRL_CNT = 0;
    //AXI specific parameters
    parameter AXI_ID_W = 1;  //AXI ID (identification) width
    parameter [AXI_ID_W-1:0] AXI_ID = 0;  //AXI ID value
    //Replacement policy (N_WAYS > 1)

    parameter HEXFILE = "none";
    parameter DATA_W = 0;
    parameter ADDR_W = 0;


endpackage

`endif
