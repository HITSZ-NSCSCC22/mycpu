`include "defines.sv"
`include "frontend/frontend_defines.sv"
`include "core_config.sv"

module ftq
    import core_config::*;
(
    input logic clk,
    input logic rst,

    // <-> Frontend
    input logic backend_flush_i,
    input logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_flush_ftq_id_i,

    // <-> BPU
    input bpu_ftq_t bpu_i,
    output ftq_block_t bpu_o,
    output logic bpu_queue_full_o,

    // <-> Backend 
    input logic [COMMIT_WIDTH-1:0] backend_commit_i,

    // <-> IFU
    output ftq_ifu_t ifu_o,
    output [$clog2(FRONTEND_FTQ_SIZE)-1:0] ifu_ftq_id_o,
    input logic ifu_accept_i  // Must return in the same cycle
);

    logic [$clog2(COMMIT_WIDTH):0] backend_commit_num;
    always_comb begin
        backend_commit_num = 0;
        for (integer i = 0; i < COMMIT_WIDTH; i++) begin
            backend_commit_num += backend_commit_i[i];
        end
    end

    localparam QUEUE_SIZE = FRONTEND_FTQ_SIZE;

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
    assign ifu_ftq_id_o = ifu_ptr;
    always_ff @(posedge clk) begin : ptr_ff
        if (rst) begin
            bpu_ptr  <= 0;
            ifu_ptr  <= 0;
            comm_ptr <= 0;
        end else begin
            // Backend committed, means that current comm_ptr block is done
            comm_ptr <= comm_ptr + backend_commit_num;

            // If block is accepted by IFU, ifu_ptr++
            // IB full should result in IFU not accepting FTQ input
            if (ifu_accept_i) ifu_ptr <= ifu_ptr + 1;

            // BPU ptr
            if (bpu_i.valid) bpu_ptr <= bpu_ptr + 1;

            // If backend redirect triggered, back to the next block of the redirect block
            // backend may continue to commit older block
            if (backend_flush_i) begin
                ifu_ptr <= backend_flush_ftq_id_i + 1;
                bpu_ptr <= backend_flush_ftq_id_i + 1;
            end
        end
    end

    // next_FTQ
    always_comb begin : next_FTQ_comb
        // Default no change
        next_FTQ = FTQ;
        // clear out if committed
        for (integer i = 0; i < COMMIT_WIDTH; i++) begin
            if (i < backend_commit_num) next_FTQ[$clog2(QUEUE_SIZE)'(comm_ptr+i)] = 0;
        end
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
    assign bpu_o = FTQ[bpu_ptr-1];


endmodule
