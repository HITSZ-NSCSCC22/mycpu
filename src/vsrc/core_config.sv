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

    // BPU Parameters
    // BPU
    parameter BPU_GHR_LENGTH = 200;
    parameter BPU_TAG_COMPONENT_NUM = 4;
    parameter integer BPU_COMPONENT_TABLE_DEPTH[BPU_TAG_COMPONENT_NUM+1] = '{
        8192,
        2048,
        2048,
        2048,
        2048
    };
    parameter integer BPU_COMPONENT_CTR_WIDTH[BPU_TAG_COMPONENT_NUM+1] = '{3, 2, 2, 2, 2};
    parameter integer BPU_COMPONENT_USEFUL_WIDTH[BPU_TAG_COMPONENT_NUM+1] = '{0, 3, 3, 3, 3};
    // FTB
    parameter integer FTB_DEPTH = 512;

    parameter DECODE_WIDTH = 2;
    parameter ISSUE_WIDTH = 2;

    // ICache parameters
    parameter ICACHE_NWAY = 2;
    parameter ICACHE_NSET = 256;

    //DCache parameters
    parameter DCACHE_NWAY = 2;
    parameter DCACHE_NSET = 256;
    parameter DCACHELINE_WIDTH = 128;

    // Commit Parameters
    parameter COMMIT_WIDTH = 2;

    // TLB related parameters
    parameter TLB_NSET = 8;
    parameter TLB_NWAY = 4;
    parameter TLB_NUM = TLB_NWAY * TLB_NSET;

    // AXI parameters
    parameter AXI_DATA_WIDTH = 128;

endpackage

`endif
