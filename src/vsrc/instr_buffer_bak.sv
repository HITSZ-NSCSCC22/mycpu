`include "core_types.sv"

module instr_buffer
    import core_types::*;
#(
    parameter IF_WIDTH = 2,
    parameter ID_WIDTH = 2,
    parameter BUFFER_SIZE = 16
) (
    input logic clk,
    input logic rst,

    // <-> Frontend
    input instr_info_t frontend_instr_i[IF_WIDTH],
    output logic frontend_stallreq_o,  // Require frontend to stop

    // <-> Backend
    input logic [ID_WIDTH-1:0] backend_accept_i,  // Backend can accept 0 or more instructions, must return in the next cycle!
    input logic backend_flush_i,  // Backend require flush, maybe branch miss
    output instr_info_t backend_instr_o[ID_WIDTH]

);

    localparam PTR_WIDTH = $clog2(BUFFER_SIZE);

    // Reset signal
    logic rst_n;

    instr_info_t buffer_queue[BUFFER_SIZE], next_buffer_queue[BUFFER_SIZE];

    logic [$clog2(BUFFER_SIZE)-1:0] read_ptr, write_ptr;

    // Workaround, verilator seems to extend {write_ptr + 2} to more bits
    // we want a loopback counter, so declare a fixed width to get around
    logic [$clog2(BUFFER_SIZE)-1:0] buffer_clearance;

    // Popcnt of backend_accept_i
    logic [$clog2(ID_WIDTH):0] backend_accept_num;

    // Popcnt of frontend_instr_i.[i].valid
    logic [$clog2(IF_WIDTH):0] frontend_accept_num;

    assign rst_n = ~rst;

    assign buffer_clearance = read_ptr - write_ptr;
    assign frontend_stallreq_o = (buffer_clearance <= 4 && buffer_clearance != 0);

    // State transition
    always_ff @(posedge clk or negedge rst_n) begin : buffer_queue_ff
        if ((!rst_n) || backend_flush_i) begin
            for (integer i = 0; i < BUFFER_SIZE; i++) begin
                buffer_queue[i] <= 0;
            end
        end else begin
            for (integer i = 0; i < BUFFER_SIZE; i++) begin
                buffer_queue[i] <= next_buffer_queue[i];
            end
        end
    end

    always_comb begin
        backend_accept_num = 0;
        for (integer i = 0; i < ID_WIDTH; i++) begin
            backend_accept_num += backend_accept_i[i];
        end
    end

    always_comb begin
        frontend_accept_num = 0;
        for (integer i = 0; i < IF_WIDTH; i++) begin
            frontend_accept_num += frontend_instr_i[i].valid;
        end
    end

    // Update ptrs
    always_ff @(posedge clk or negedge rst_n) begin : ptr_ff
        if (!rst_n || backend_flush_i) begin
            read_ptr  <= 0;
            write_ptr <= 0;
        end else begin
            read_ptr  <= read_ptr + {2'b0, backend_accept_num};
            write_ptr <= write_ptr + {2'b0, frontend_accept_num};
        end
    end

    always_comb begin : next_buffer_queue_comb  // Main shift logic
        // Default keep all entry
        for (integer i = 0; i < BUFFER_SIZE; i++) begin
            next_buffer_queue[i] = buffer_queue[i];
        end

        // Backend overide
        for (integer i = 0; i < ID_WIDTH; i++) begin
            // Reset entry
            if (i < backend_accept_num) begin
                next_buffer_queue[PTR_WIDTH'(read_ptr+i[3:0])] = 0;
            end
        end

        // Frontend overide
        for (integer i = 0; i < IF_WIDTH; i++) begin
            // Accept entry from frontend
            if (i < frontend_accept_num) begin
                next_buffer_queue[PTR_WIDTH'(write_ptr+i[3:0])] = frontend_instr_i[i];
            end
        end
    end

    // Connect backend_instr_o directly to buffer_queue
    always_comb begin : backend_instr_o_comb
        for (integer i = 0; i < ID_WIDTH; i++) begin
            backend_instr_o[i] = buffer_queue[PTR_WIDTH'(read_ptr+i[3:0])];
        end
    end


endmodule
