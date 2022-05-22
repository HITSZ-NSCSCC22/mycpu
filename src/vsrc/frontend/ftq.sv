`include "defines.sv"
`include "frontend/frontend_defines.sv"

module ftq #(
    parameter FETCH_WIDTH = 4,
    parameter QUEUE_SIZE  = 4
) (
    input logic clk,
    input logic rst,

    // <-> BPU
    input bpu_ftq_t bpu_i,
    output logic bpu_queue_full_o,

    // <-> Backend 
    input logic backend_commit_i,

    // <-> IFU
    output ftq_ifu_t ifu_o,
    input logic ifu_accept_i
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    // QUEUE data structure
    ftq_block_t [QUEUE_SIZE-1:0] FTQ, next_FTQ;
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            FTQ <= 0;
        end else begin
            FTQ <= next_FTQ;
        end
    end

    // DEBUG signal
    logic [`InstAddrBus] debug_queue_pc[QUEUE_SIZE];
    always_comb begin
        for (integer i = 0; i < QUEUE_SIZE; i++) begin
            debug_queue_pc[i] = FTQ[i].start_pc;
        end
    end

    // PTR
    logic [$clog2(QUEUE_SIZE)-1:0] bpu_ptr, ifu_ptr, comm_ptr;
    always_ff @(posedge clk or negedge rst_n) begin : ptr_ff
        if (~rst_n) begin
            bpu_ptr  <= 0;
            ifu_ptr  <= 0;
            comm_ptr <= 0;
        end else begin
            if (backend_commit_i) comm_ptr <= comm_ptr + 1;
            if (ifu_accept_i) ifu_ptr <= ifu_ptr + 1;
            if (bpu_i.valid) bpu_ptr <= bpu_ptr + 1;
        end
    end

    // next_FTQ
    always_comb begin : next_FTQ_comb
        // Default, no change
        next_FTQ = FTQ;
        if (backend_commit_i) next_FTQ[comm_ptr] = 0;
        if (bpu_i.valid) next_FTQ[bpu_ptr] = bpu_i;
    end

    // Output
    // -> IFU
    assign ifu_o.valid = FTQ[ifu_ptr].valid;
    assign ifu_o.is_cross_cacheline = FTQ[ifu_ptr].is_cross_cacheline;
    assign ifu_o.start_pc = FTQ[ifu_ptr].start_pc;
    assign ifu_o.length = FTQ[ifu_ptr].length;

    // -> BPU
    logic [$clog2(QUEUE_SIZE)-1:0] bpu_ptr_plus1;  // Limit the bit width
    assign bpu_ptr_plus1 = bpu_ptr + 1;
    assign bpu_queue_full_o = (bpu_ptr_plus1 == comm_ptr);


endmodule
