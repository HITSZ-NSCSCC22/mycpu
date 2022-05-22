`include "instr_info.sv"
`include "frontend/frontend_defines.sv"

`include "frontend/ftq.sv"
`include "frontend/ifu.sv"

module frontend #(
    parameter FETCH_WIDTH = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter CACHELINE_WIDTH = 128
) (
    input logic clk,
    input logic rst,

    // <-> ICache
    // ICache is fixed dual port
    output logic [1:0] icache_read_req_o,
    output logic [1:0][ADDR_WIDTH-1:0] icache_read_addr_o,
    input logic [1:0] icache_read_valid_i,
    input logic [1:0][CACHELINE_WIDTH-1:0] icache_read_data_i,


    // <-> Backend
    input branch_update_info_t branch_update_info_i,
    input logic [ADDR_WIDTH-1:0] backend_next_pc_i,
    input logic backend_flush_i,
    input logic backend_commit_i,

    // <-> Instruction buffer
    input logic instr_buffer_stallreq_i,
    output instr_buffer_info_t instr_buffer_o[FETCH_WIDTH]

);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    logic [ADDR_WIDTH-1:0] pc, next_pc;

    always_ff @(posedge clk or negedge rst_n) begin : pc_ff
        if (!rst_n) begin
            pc <= 32'h1c000000;
        end else begin
            pc <= next_pc;
        end
    end

    logic ftq_full;

    always_comb begin : next_pc_comb
        if (backend_flush_i) begin
            next_pc = backend_next_pc_i;
        end else if (instr_buffer_stallreq_i || ftq_full) begin
            next_pc = pc;
        end else begin
            next_pc = pc + FETCH_WIDTH * 4;
        end
    end

    // BPU
    bpu_ftq_t bpu_ftq_block;
    always_comb begin
        if (~ftq_full) begin
            bpu_ftq_block.start_pc = pc;
            bpu_ftq_block.valid = 1;
            bpu_ftq_block.length = 4;
            bpu_ftq_block.is_cross_cacheline = 0;
        end else begin
            bpu_ftq_block = 0;
        end
    end

    ftq_ifu_t ftq_ifu_block;
    logic ifu_ftq_accept;

    ftq #(
        .FETCH_WIDTH(4),
        .QUEUE_SIZE (4)
    ) u_ftq (
        .clk             (clk),
        .rst             (rst),
        .bpu_i           (bpu_ftq_block),
        .bpu_queue_full_o(ftq_full),
        .backend_commit_i(backend_commit_i),
        .ifu_o           (ftq_ifu_block),
        .ifu_accept_i    (ifu_ftq_accept)
    );


    ifu u_ifu (
        .clk            (clk),
        .rst            (rst),
        .ftq_i          (ftq_ifu_block),
        .ftq_accept_o   (ifu_ftq_accept),
        .icache_rreq_o  (icache_read_req_o),
        .icache_raddr_o (icache_read_addr_o),
        .icache_rvalid_i(icache_read_valid_i),
        .icache_rdata_i (icache_read_data_i),
        .stallreq_i     (instr_buffer_stallreq_i),
        .instr_buffer_o (instr_buffer_o)
    );



endmodule
