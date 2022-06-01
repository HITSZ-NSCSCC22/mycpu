`include "defines.sv"
`include "frontend/frontend_defines.sv"

module ftq #(
    parameter FETCH_WIDTH = 4,
    parameter QUEUE_SIZE  = 4
) (
    input logic clk,
    input logic rst,

    // <-> Frontend
    input logic backend_flush_i,
    input logic instr_buffer_stallreq_i,

    // <-> BPU
    input bpu_ftq_t bpu_i,
    output logic bpu_queue_full_o,

    // <-> Backend 
    input logic backend_commit_i,

    // <-> IFU
    output ftq_ifu_t ifu_o,
    input logic ifu_accept_i  // Must return in the same cycle
);

    // QUEUE data structure
    ftq_block_t [QUEUE_SIZE-1:0] FTQ, next_FTQ;
    always_ff @(posedge clk) begin
        if (rst) begin
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
    always_ff @(posedge clk) begin : ptr_ff
        if (rst) begin
            bpu_ptr  <= 0;
            ifu_ptr  <= 0;
            comm_ptr <= 0;
        end else begin
            // Backend committed, means that current comm_ptr block is done
            if (backend_commit_i) comm_ptr <= comm_ptr + 1;

            // If block is accepted by IFU, ifu_ptr++
            // IB full should result in IFU not accepting FTQ input
            if (ifu_accept_i) ifu_ptr <= ifu_ptr + 1;

            // BPU ptr
            if (bpu_i.valid) bpu_ptr <= bpu_ptr + 1;

            // If backend redirect triggered, back to comm_ptr + 1
            // Since FTQ is cleared out, so not pending block
            if (backend_flush_i) begin
                ifu_ptr <= comm_ptr + 1;
                bpu_ptr <= comm_ptr + 1;
            end
        end
    end

    // next_FTQ
    always_comb begin : next_FTQ_comb
        // Default no change
        next_FTQ = FTQ;
        // clear out if committed
        if (backend_commit_i) next_FTQ[comm_ptr] = 0;
        // Accept BPU input
        if (bpu_i.valid) next_FTQ[bpu_ptr] = bpu_i;
        // If backend redirect triggered, clear FTQ
        if (backend_flush_i) next_FTQ = 0;
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
