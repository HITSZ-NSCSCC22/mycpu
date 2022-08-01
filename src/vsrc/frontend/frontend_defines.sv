`ifndef FRONTEND_DEFINES_SV
`define FRONTEND_DEFINES_SV
`include "defines.sv"

`define FETCH_WIDTH 4

typedef struct packed {
    logic valid;
    logic is_cross_cacheline;
    logic [$clog2(`FETCH_WIDTH+1)-1:0] length;
    // BPU info
    logic predicted_taken;
    logic predict_valid;
    logic [`InstAddrBus] start_pc;
} ftq_block_t;



typedef struct packed {
    logic is_branch;
    logic [1:0] branch_type;
    logic is_taken;
    logic predicted_taken;  // Comes from BPU
} backend_commit_meta_t;

`endif
