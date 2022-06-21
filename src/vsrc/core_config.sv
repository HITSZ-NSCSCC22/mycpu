`ifndef CORE_CONFIG_SV
`define CORE_CONFIG_SV


package core_config;

    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;


    // Frontend Parameters
    parameter FETCH_WIDTH = 4;
    parameter ICACHELINE_WIDTH = 128;
    parameter FRONTEND_FTQ_SIZE = 8;

    // Commit Parameters
    parameter COMMIT_WIDTH = 2;

endpackage

`endif