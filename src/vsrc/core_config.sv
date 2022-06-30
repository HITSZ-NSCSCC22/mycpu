`ifndef CORE_CONFIG_SV
`define CORE_CONFIG_SV


package core_config;

    // Global parameters
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    // Frontend Parameters
    parameter FETCH_WIDTH = 4;
    parameter ICACHELINE_WIDTH = 128;
    parameter FRONTEND_FTQ_SIZE = 8;

    // BPU Parameters
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

    // ICache parameters
    parameter ICACHE_NWAY = 2;
    parameter ICACHE_NSET = 256;

    // Commit Parameters
    parameter COMMIT_WIDTH = 2;

endpackage

`endif
