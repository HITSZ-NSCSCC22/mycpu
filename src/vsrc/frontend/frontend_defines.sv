`ifndef FRONTEND_DEFINES_SV
`define FRONTEND_DEFINES_SV
`include "defines.sv"

`define FETCH_WIDTH 4

typedef struct packed {
    logic valid;
    logic [`InstAddrBus] start_pc;
    logic is_cross_cacheline;
    logic [$clog2(`FETCH_WIDTH+1)-1:0] length;
    logic predicted_taken;
} bpu_ftq_t;

typedef struct packed {
    logic valid;
    logic [`InstAddrBus] start_pc;
    logic is_cross_cacheline;
    logic [$clog2(`FETCH_WIDTH+1)-1:0] length;
    logic predicted_taken;
} ftq_block_t;

// FTQ <-> IFU
typedef struct packed {
    logic valid;
    logic [`InstAddrBus] start_pc;
    logic is_cross_cacheline;
    logic [$clog2(`FETCH_WIDTH+1)-1:0] length;
    logic predicted_taken;
} ftq_ifu_t;

typedef struct packed {
    logic is_branch;
    logic is_conditional;
    logic is_taken;
    logic predicted_taken;  // Comes from BPU
} backend_commit_meta_t;

`endif
