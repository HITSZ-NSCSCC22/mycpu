`include "defines.sv"
`include "frontend/frontend_defines.sv"
`include "core_config.sv"
`include "BPU/include/bpu_types.sv"

module ftq
    import core_config::*;
    import bpu_types::*;
(
    input logic clk,
    input logic rst,

    // <-> Frontend
    input logic backend_flush_i,
    input logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_flush_ftq_id_i,

    // <-> BPU
    input bpu_ftq_t bpu_p0_i,
    input bpu_ftq_t bpu_p1_i,
    input bpu_ftq_meta_t bpu_meta_i,
    input logic main_bpu_redirect_i,
    output logic bpu_queue_full_o,
    output ftq_bpu_meta_t bpu_meta_o,

    // <-> Backend
    input logic backend_ftq_meta_update_valid_i,
    input logic [ADDR_WIDTH-1:0] backend_ftq_meta_update_jump_target_i,
    input logic [ADDR_WIDTH-1:0] backend_ftq_meta_update_fall_through_i,
    input logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_ftq_update_meta_id_i,
    input logic [COMMIT_WIDTH-1:0] backend_commit_bitmask_i,
    input logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_commit_ftq_id_i,
    input backend_commit_meta_t backend_commit_meta_i,

    // <-> IFU
    output ftq_ifu_t ifu_o,
    output logic ifu_frontend_redirect_o,
    output [$clog2(FRONTEND_FTQ_SIZE)-1:0] ifu_ftq_id_o,
    input logic ifu_accept_i  // Must return in the same cycle
);

    // Parameters
    localparam QUEUE_SIZE = FRONTEND_FTQ_SIZE;

    // Signals
    logic queue_full;
    logic queue_full_delay;


    logic [$clog2(COMMIT_WIDTH):0] backend_commit_num;
    always_comb begin
        backend_commit_num = 0;
        for (integer i = 0; i < COMMIT_WIDTH; i++) begin
            backend_commit_num += backend_commit_bitmask_i[i];
        end
    end

    // Queue full
    assign queue_full = (bpu_ptr_plus1 == comm_ptr);
    always_ff @(posedge clk) begin
        queue_full_delay <= queue_full;
    end
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
            if (bpu_p0_i.valid) bpu_ptr <= bpu_ptr + 1;
            // P1 redirect, maintain bpu_ptr;
            if (main_bpu_redirect_i & ~queue_full_delay) bpu_ptr <= bpu_ptr;

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
            if (i < backend_commit_num) next_FTQ[comm_ptr+i[$clog2(QUEUE_SIZE)-1:0]] = 0;
        end

        // Accept BPU input
        // P0
        if (bpu_p0_i.valid) next_FTQ[bpu_ptr] = bpu_p0_i;
        // P1
        if (bpu_p1_i.valid & ~queue_full_delay)  // If last cycle accepted P0 input
            next_FTQ[bpu_ptr-1] = bpu_p1_i;
        else if (bpu_p1_i.valid)  // Else no override
            next_FTQ[bpu_ptr] = bpu_p1_i;

        // If backend redirect triggered, clear the committed and predicted entry
        if (backend_flush_i) begin
            for (integer i = 0; i < QUEUE_SIZE; i++) begin
                if (~(i >= comm_ptr & i <= backend_flush_ftq_id_i)) next_FTQ[i] = 0;
            end
        end
    end

    // Output
    // -> IFU
    assign ifu_o.valid = FTQ[ifu_ptr].valid;
    assign ifu_o.is_cross_cacheline = FTQ[ifu_ptr].is_cross_cacheline;
    assign ifu_o.start_pc = FTQ[ifu_ptr].start_pc;
    assign ifu_o.length = FTQ[ifu_ptr].length;
    assign ifu_o.predicted_taken = FTQ[ifu_ptr].predicted_taken;
    assign ifu_frontend_redirect_o = bpu_ptr == ifu_ptr & FTQ[ifu_ptr].valid & main_bpu_redirect_i & ~queue_full_delay;
    // DEBUG
    logic [2:0] debug_length = ifu_o.length;


    // -> BPU
    logic [$clog2(QUEUE_SIZE)-1:0] bpu_ptr_plus1;  // Limit the bit width
    assign bpu_ptr_plus1 = bpu_ptr + 1;
    assign bpu_queue_full_o = queue_full;

    // Training meta to BPU
    always_ff @(posedge clk) begin
        if (rst) bpu_meta_o <= 0;
        else begin
            bpu_meta_o <= 0;
            if (backend_commit_bitmask_i[0] & backend_commit_meta_i.is_branch) begin
                bpu_meta_o.valid <= 1;
                bpu_meta_o.is_branch <= backend_commit_meta_i.is_branch;
                bpu_meta_o.is_conditional <= backend_commit_meta_i.is_conditional;
                bpu_meta_o.is_taken <= backend_commit_meta_i.is_taken;
                bpu_meta_o.predicted_taken <= backend_commit_meta_i.predicted_taken;
                bpu_meta_o.start_pc <= FTQ[backend_commit_ftq_id_i].start_pc;
                bpu_meta_o.is_cross_cacheline <= FTQ[backend_commit_ftq_id_i].is_cross_cacheline;
                bpu_meta_o.provider_ctr_bits <= FTQ_meta[backend_commit_ftq_id_i].provider_ctr_bits;
                bpu_meta_o.jump_target_address <= FTQ_meta[backend_commit_ftq_id_i].jump_target_address;
                bpu_meta_o.fall_through_address <= FTQ_meta[backend_commit_ftq_id_i].fall_through_address;
            end
        end
    end


    // BPU meta ram
    ftq_bpu_meta_entry_t [QUEUE_SIZE-1:0] FTQ_meta;
    always_ff @(posedge clk) begin
        FTQ_meta[bpu_ptr] <= {bpu_meta_i, 64'b0};
        if (backend_ftq_meta_update_valid_i) begin
            FTQ_meta[backend_ftq_update_meta_id_i][63:0] <= {
                backend_ftq_meta_update_jump_target_i, backend_ftq_meta_update_fall_through_i
            };
        end
    end



endmodule
