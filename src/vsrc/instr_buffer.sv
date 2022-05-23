`include "instr_info.sv"

module instr_buffer #(
    parameter IF_WIDTH = 2,
    parameter ID_WIDTH = 2,
    parameter BUFFER_SIZE = 16
) (
    input logic clk,
    input logic rst,

    // <-> Frontend
    input instr_buffer_info_t frontend_instr_i[IF_WIDTH],
    output logic frontend_stallreq_o,  // Require frontend to stop

    // <-> Backend
    input logic [ID_WIDTH-1:0] backend_accept_i,  // Backend can accept 0 or more instructions, must return in the next cycle!
    input logic backend_flush_i,  // Backend require flush, maybe branch miss
    output instr_buffer_info_t backend_instr_o[ID_WIDTH]

);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    instr_buffer_info_t buffer_queue[BUFFER_SIZE], next_buffer_queue[BUFFER_SIZE];

    logic [$clog2(BUFFER_SIZE)-1:0] read_ptr, write_ptr, write_ptr_plus_2;

    // Workaround, verilator seems to extend {write_ptr + 2} to more bits
    // we want a loopback counter, so declare a fixed width to get around
    assign write_ptr_plus_2 = write_ptr + 2;
    assign frontend_stallreq_o = (write_ptr_plus_2 == read_ptr);

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

    // Popcnt of backend_accept_i
    logic [$clog2(ID_WIDTH):0] backend_accept_num;
    always_comb begin
        backend_accept_num = 0;
        foreach (backend_accept_i[idx]) begin
            backend_accept_num += backend_accept_i[idx];
        end
    end
    // Popcnt of frontend_instr_i.[i].valid
    logic [$clog2(IF_WIDTH):0] frontend_accept_num;
    always_comb begin
        frontend_accept_num = 0;
        foreach (frontend_instr_i[idx]) begin
            frontend_accept_num += frontend_instr_i[idx].valid;
        end
    end

    // Update ptrs
    always_ff @(posedge clk or negedge rst_n) begin : ptr_ff
        if (!rst_n || backend_flush_i) begin
            read_ptr  <= 0;
            write_ptr <= 0;
        end else begin
            read_ptr  <= read_ptr + backend_accept_num;
            write_ptr <= write_ptr + frontend_accept_num;
        end
    end

    always_comb begin : next_buffer_queue_comb  // Main shift logic
        // Default keep all entry
        foreach (buffer_queue[idx]) begin
            next_buffer_queue[idx] = buffer_queue[idx];
        end

        // Backend overide
        for (integer i = 0; i < ID_WIDTH; i++) begin
            // Reset entry
            if (i < backend_accept_num) begin
                // verilator lint_off WIDTH
                next_buffer_queue[read_ptr+i] = 0;
                // verilator lint_on WIDTH
            end
        end

        // Frontend overide
        for (integer i = 0; i < IF_WIDTH; i++) begin
            // Accept entry from frontend
            if (i < frontend_accept_num) begin
                // verilator lint_off WIDTH
                next_buffer_queue[write_ptr+i] = frontend_instr_i[i];
                // verilator lint_on WIDTH
            end
        end
    end

    // Connect backend_instr_o directly to buffer_queue
    // FIXME: may introduce large latency
    // OPTIM: may have better ways
    always_comb begin : backend_instr_o_comb
        for (integer i = 0; i < ID_WIDTH; i++) begin
            // verilator lint_off WIDTH
            backend_instr_o[i] = buffer_queue[read_ptr+i+backend_accept_num];
            // verilator lint_on WIDTH
        end
    end


endmodule
