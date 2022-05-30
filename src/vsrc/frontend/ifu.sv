`include "frontend/frontend_defines.sv"
`include "instr_info.sv"


module ifu #(
    parameter FETCH_WIDTH = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter CACHELINE_WIDTH = 128  // FETCH_WIDTH and CACHELINE_WIDTH must match
) (
    input logic clk,
    input logic rst,

    // Flush
    input flush_i,

    // <-> Fetch Target Queue
    input ftq_ifu_t ftq_i,
    output logic ftq_accept_o,  // In current cycle


    // <-> Frontend <-> ICache
    output logic [1:0] icache_rreq_o,
    output logic [1:0][ADDR_WIDTH-1:0] icache_raddr_o,
    input logic [1:0] icache_rvalid_i,
    input logic [1:0][CACHELINE_WIDTH-1:0] icache_rdata_i,


    // <-> Frontend <-> Instruction Buffer
    input logic stallreq_i,
    output instr_buffer_info_t instr_buffer_o[FETCH_WIDTH]
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    logic accept_ftq_input;
    assign ftq_accept_o = accept_ftq_input;

    // P0
    logic ftq_input_valid = ftq_i.valid;
    // Send addr to ICache
    always_comb begin
        if (ftq_input_valid) begin
            icache_rreq_o[0] = 1;
            icache_rreq_o[1] = ftq_i.is_cross_cacheline ? 1 : 0;
            icache_raddr_o[0] = {ftq_i.start_pc[ADDR_WIDTH-1:4], 4'b0};
            icache_raddr_o[1] = ftq_i.is_cross_cacheline ? {ftq_i.start_pc[ADDR_WIDTH-1:4], 4'b0} + 16 : 0; // TODO: remove magic number
        end else begin
            icache_rreq_o  = 0;
            icache_raddr_o = 0;
        end
    end

    // Flush state
    logic is_flushing;
    logic [1:0] flushing_rvalid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            flushing_rvalid <= 0;
        end else if (flush_i) begin
            flushing_rvalid <= 0;
        end else begin
            if (icache_rvalid_i[0]) flushing_rvalid[0] <= 1;
            if (icache_rvalid_i[1]) flushing_rvalid[1] <= 1;
        end
    end
    logic last_rreq_cross_cacheline;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_flushing <= 0;
            last_rreq_cross_cacheline <= 0;
        end else if (flush_i) begin
            is_flushing <= 1;
            last_rreq_cross_cacheline <= current_fetch_block.is_cross_cacheline;
        end else if (last_rreq_cross_cacheline) begin
            if ((icache_rvalid_i | flushing_rvalid) == 2'b11) begin
                is_flushing <= 0;
                last_rreq_cross_cacheline <= 0;
            end
        end else if (icache_rvalid_i[0] == 1) begin
            is_flushing <= 0;
            last_rreq_cross_cacheline <= 0;
        end
    end

    // P1 
    // FTQ input pass to P1
    ftq_ifu_t current_fetch_block;
    logic [ADDR_WIDTH-1:0] debug_p1_pc = current_fetch_block.start_pc;  // DEBUG
    logic [ADDR_WIDTH-1:0] debug_p0_pc = ftq_i.start_pc;  // DEBUG
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_fetch_block <= 0;
        end else if (flush_i) begin
            current_fetch_block <= 0;
        end else begin
            current_fetch_block <= ftq_i;
        end
    end
    // Cacheline returned
    logic [FETCH_WIDTH-1:0][DATA_WIDTH-1:0] cacheline_0, cacheline_1;
    assign cacheline_0 = icache_rdata_i[0];
    assign cacheline_1 = icache_rdata_i[1];
    logic icache_result_valid;
    always_comb begin
        if (current_fetch_block.is_cross_cacheline)
            icache_result_valid = icache_rvalid_i[0] & icache_rvalid_i[1];
        else icache_result_valid = icache_rvalid_i[0];

        if (is_flushing) icache_result_valid = 0;
    end

    // If last req to icache is valid, then accept another ftq input
    assign accept_ftq_input = icache_result_valid;

    // P2
    // Send instr info to IB
    logic [FETCH_WIDTH*2-1:0][DATA_WIDTH-1:0] cacheline_combined;
    assign cacheline_combined = {cacheline_1, cacheline_0};
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                instr_buffer_o[i] <= 0;
            end
        end else if (stallreq_i) begin
            // Hold output
        end else begin
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                // Default
                instr_buffer_o[i].is_last_in_block <= 0;

                if (i < current_fetch_block.length && ~stallreq_i && icache_result_valid && ~is_flushing && ~flush_i) begin
                    if (i == current_fetch_block.length - 1) begin
                        instr_buffer_o[i].valid <= 1;
                        instr_buffer_o[i].is_last_in_block <= 1;
                        instr_buffer_o[i].pc <= current_fetch_block.start_pc + i * 4;  // Instr is 4 bytes long
                        instr_buffer_o[i].instr <= cacheline_combined[current_fetch_block.start_pc[3:2]+i];
                    end else begin
                        instr_buffer_o[i].valid <= 1;
                        instr_buffer_o[i].pc <= current_fetch_block.start_pc + i * 4;  // Instr is 4 bytes long
                        instr_buffer_o[i].instr <= cacheline_combined[current_fetch_block.start_pc[3:2]+i];
                    end
                end else begin
                    instr_buffer_o[i] <= 0;
                end
            end
        end
    end

endmodule
