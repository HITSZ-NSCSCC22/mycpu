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
    parameter BPU_GHR_LENGTH = 150;
    parameter BPU_TAG_COMPONENT_NUM = 4;
    parameter integer BPU_COMPONENT_TABLE_DEPTH[BPU_TAG_COMPONENT_NUM+1] = '{
        16384,
        2048,
        2048,
        2048,
        2048
    };
    parameter integer BPU_COMPONENT_CTR_WIDTH[BPU_TAG_COMPONENT_NUM+1] = '{2, 3, 3, 3, 3};
    parameter integer BPU_COMPONENT_USEFUL_WIDTH[BPU_TAG_COMPONENT_NUM+1] = '{0, 2, 2, 2, 2};
    parameter integer BPU_COMPONENT_HISTORY_LENGTH[BPU_TAG_COMPONENT_NUM+1] = '{
        0,
        5,
        15,
        44,
        130
    };
    // FTB
    parameter integer FTB_NSET = 1024;
    parameter integer FTB_NWAY = 4;
    // RAS
    parameter integer RAS_ENTRY_NUM = 32;

    parameter DECODE_WIDTH = 2;
    parameter ISSUE_WIDTH = 2;

    // ICache parameters
    parameter ICACHE_NWAY = 2;
    parameter ICACHE_NSET = 1024;

    // DCache parameters
    parameter DCACHE_NWAY = 2;
    parameter DCACHE_NSET = 256;
    parameter DCACHELINE_WIDTH = 128;

    // LSU parameters
    parameter LSU_STORE_QUEU_SIZE = 4;

    // Commit Parameters
    parameter COMMIT_WIDTH = 2;

    // TLB related parameters
    // parameter TLB_NSET = 8;
    // parameter TLB_NWAY = 4;
    parameter TLB_NUM = 32;

    // AXI parameters
    parameter AXI_DATA_WIDTH = 128;

endpackage

`endif
