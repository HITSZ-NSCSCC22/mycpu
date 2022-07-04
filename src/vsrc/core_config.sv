`ifndef CORE_CONFIG_SV
`define CORE_CONFIG_SV


package core_config;

    // Global parameters
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter INSTR_WIDTH = 32;
    parameter GPR_NUM = 32;

    // Frontend Parameters
    parameter FETCH_WIDTH = 4;
    parameter ICACHELINE_WIDTH = 128;
    parameter FRONTEND_FTQ_SIZE = 8;


    parameter DECODE_WIDTH = 2;

    // ICache parameters
    parameter ICACHE_NWAY = 2;
    parameter ICACHE_NSET = 256;

    // Commit Parameters
    parameter COMMIT_WIDTH = 2;

    // TLB related parameters
    parameter TLB_NSET = 8;
    parameter TLB_NWAY = 4;
    parameter TLB_NUM = TLB_NWAY * TLB_NSET;

endpackage

`endif
