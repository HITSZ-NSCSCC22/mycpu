`ifndef FRONTEND_DEFINES_SV
`define FRONTEND_DEFINES_SV
`include "defines.sv"

`define FETCH_WIDTH 4

typedef struct packed {
    logic valid;
    logic is_cross_cacheline;
    logic [`InstAddrBus] start_pc;
    logic [$clog2(`FETCH_WIDTH)-1:0] length;

    // TODO: add BPU meta
} bpu_ftq_t;

typedef struct packed {
    logic valid;
    logic is_cross_cacheline;
    logic [`InstAddrBus] start_pc;
    logic [$clog2(`FETCH_WIDTH)-1:0] length;
} ftq_block_t;

// FTQ <-> IFU
typedef struct packed {
    logic valid;
    logic is_cross_cacheline;
    logic [`InstAddrBus] start_pc;
    logic [$clog2(`FETCH_WIDTH)-1:0] length;
} ftq_ifu_t;

`endif
