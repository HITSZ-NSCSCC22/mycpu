`include "utils/fifo.sv"
`include "core_config.sv"
`include "core_types.sv"

module instr_buffer
    import core_config::*;
    import core_types::*;
(
    input logic clk,
    input logic rst,


    // <-> Frontend
    input instr_info_t frontend_instr_i[FETCH_WIDTH],
    output logic frontend_stallreq_o,  // Require frontend to stop


    // <-> Backend
    input logic [DECODE_WIDTH-1:0] backend_accept_i,  // Backend can accept 0 or more instructions, must return in the next cycle!
    input logic backend_flush_i,  // Backend require flush, maybe branch miss
    output instr_info_t backend_instr_o[DECODE_WIDTH]
);

    typedef logic [$clog2(CHANNEL)-1:0] index_t;

    localparam CHANNEL = INSTR_BUFFER_CHANNEL;
    localparam BANK_DEPTH = INSTR_BUFFER_SIZE / CHANNEL;
    localparam PUSH_CHANNEL = FETCH_WIDTH;
    localparam POP_CHANNEL = DECODE_WIDTH;
    localparam FIFO_DATA_WIDTH = $bits(instr_info_t);

    parameter type dtype = logic [FIFO_DATA_WIDTH-1:0];

    // queues info
    logic [CHANNEL-1:0] queue_push, queue_pop;
    logic [CHANNEL-1:0] queue_full, queue_empty;
    dtype [CHANNEL-1:0] data_in, data_out;
    logic [$clog2(CHANNEL+1)-1:0] full_cnt;
    logic [$clog2(PUSH_CHANNEL+1)-1:0] push_num;
    logic [$clog2(POP_CHANNEL+1)-1:0] pop_num;
    logic empty;

    assign frontend_stallreq_o = full_cnt > CHANNEL - PUSH_CHANNEL;
    assign empty = &queue_empty;

    // index
    index_t [CHANNEL-1:0] shifted_read_idx, shifted_write_idx;
    index_t [CHANNEL-1:0] rshifted_read_idx, rshifted_write_idx;
    index_t read_ptr_now, write_ptr_now;

    always_comb begin
        full_cnt = '0;
        for (int i = 0; i < CHANNEL; ++i) full_cnt += queue_full[i];
    end

    for (genvar i = 0; i < CHANNEL; ++i) begin : gen_shifted_rw_index
        assign shifted_read_idx[i]   = read_ptr_now + i;
        assign shifted_write_idx[i]  = write_ptr_now + i;
        assign rshifted_read_idx[i]  = i - read_ptr_now;
        assign rshifted_write_idx[i] = i - write_ptr_now;
    end

    // queue logic
    always_comb begin
        for (integer i = 0; i < POP_CHANNEL; ++i) begin : gen_read_queue
            backend_instr_o[i] = data_out[shifted_read_idx[i]];
            backend_instr_o[i].valid = ~queue_empty[shifted_read_idx[i]];
        end
    end

    // write queue logic
    for (genvar i = 0; i < CHANNEL; ++i) begin : gen_rw_req
        assign data_in[i]    = frontend_instr_i[rshifted_write_idx[i]];
        assign queue_pop[i]  = (rshifted_read_idx[i] < pop_num);
        assign queue_push[i] = (rshifted_write_idx[i] < push_num);
    end

    // update index
    always_ff @(posedge clk) begin
        if (rst || backend_flush_i) begin
            read_ptr_now  <= '0;
            write_ptr_now <= '0;
        end else begin
            read_ptr_now  <= read_ptr_now + pop_num;
            write_ptr_now <= write_ptr_now + push_num;
        end
    end

    always_comb begin
        pop_num = 0;
        for (integer i = 0; i < DECODE_WIDTH; i++) begin
            pop_num += backend_accept_i[i];
        end
    end

    always_comb begin
        push_num = 0;
        for (integer i = 0; i < FETCH_WIDTH; i++) begin
            push_num += frontend_instr_i[i].valid;
        end
    end

    // FIFOs
    for (genvar i = 0; i < CHANNEL; ++i) begin : gen_instr_fifo_bank
        fifo #(
            .DEPTH     (BANK_DEPTH),
            .DATA_WIDTH(FIFO_DATA_WIDTH)
        ) instr_fifo_bank (
            .clk      (clk),
            .rst      (rst),
            // Push
            .push     (queue_push[i]),
            .push_data(data_in[i]),
            // Pop
            .pop      (queue_pop[i]),
            .pop_data (data_out[i]),
            // Control
            .reset    (backend_flush_i),
            .full     (queue_full[i]),
            .empty    (queue_empty[i])
        );
    end

endmodule
