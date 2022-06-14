`include "core_types.sv"
`include "core_config.sv"
`include "frontend/frontend_defines.sv"

`include "frontend/ftq.sv"
`include "frontend/ifu.sv"

module frontend
    import core_types::*;
    import core_config::*;
    import tlb_types::inst_tlb_t;
    import tlb_types::tlb_inst_t;
(
    input logic clk,
    input logic rst,

    // <-> ICache
    // ICache is fixed dual port
    output logic [1:0] icache_read_req_o,
    output logic [1:0][ADDR_WIDTH-1:0] icache_read_addr_o,
    input logic [1:0] icache_read_valid_i,
    input logic [1:0][ICACHELINE_WIDTH-1:0] icache_read_data_i,


    // <-> Backend
    input branch_update_info_t branch_update_info_i,
    input logic [ADDR_WIDTH-1:0] backend_next_pc_i,
    input logic backend_flush_i,
    input logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_flush_ftq_id_i,
    input logic [COMMIT_WIDTH-1:0] backend_commit_i,

    // <-> Instruction buffer
    input logic instr_buffer_stallreq_i,
    output instr_buffer_info_t instr_buffer_o[FETCH_WIDTH],

    // <- CSR
    input logic csr_pg,
    input logic csr_da,
    input logic [31:0] csr_dmw0,
    input logic [31:0] csr_dmw1,
    input logic [1:0] csr_plv,
    input logic [1:0] csr_datf,
    input logic disable_cache,

    // <-> TLB
    output inst_tlb_t tlb_o,
    input  tlb_inst_t tlb_i
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;



    logic [ADDR_WIDTH-1:0] pc, next_pc, sequential_pc;
    assign sequential_pc = pc + 4 * bpu_ftq_block.length;

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
        end else if (ftq_full) begin
            next_pc = pc;
        end else begin
            next_pc = sequential_pc;
        end
    end

    // BPU
    bpu_ftq_t bpu_ftq_block;
    logic is_cross_page;
    assign is_cross_page = pc[11:0] > 12'hff0;  // if 4 instr already cross the page limit
    always_comb begin
        if (~ftq_full) begin
            if (is_cross_page) begin
                bpu_ftq_block.length = (12'h000 - pc[11:0]) >> 2;
            end else begin
                bpu_ftq_block.length = 4;
            end
            bpu_ftq_block.start_pc = pc;
            bpu_ftq_block.valid = 1;
            // If cross page, length will be cut, so ensures no cacheline cross
            bpu_ftq_block.is_cross_cacheline = (pc[3:2] != 2'b00) & ~is_cross_page;
        end else begin
            bpu_ftq_block = 0;
        end
    end

    ftq_ifu_t ftq_ifu_block;
    logic ifu_ftq_accept;
    logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] ftq_ifu_id;

    ftq u_ftq (
        .clk(clk),
        .rst(rst),

        // Flush
        .backend_flush_i(backend_flush_i),
        .backend_flush_ftq_id_i(backend_flush_ftq_id_i),

        // <-> BPU
        .bpu_i           (bpu_ftq_block),
        .bpu_queue_full_o(ftq_full),

        // <-> Backend
        .backend_commit_i(backend_commit_i),

        // <-> IFU
        .ifu_o       (ftq_ifu_block),
        .ifu_ftq_id_o(ftq_ifu_id),
        .ifu_accept_i(ifu_ftq_accept)
    );


    instr_buffer_info_t ifu_instr_output[FETCH_WIDTH];
    assign instr_buffer_o = instr_buffer_stallreq_i ? '{FETCH_WIDTH{0}} : ifu_instr_output;
    ifu u_ifu (
        .clk(clk),
        .rst(rst),

        // Flush
        .flush_i(backend_flush_i),

        // <-> FTQ
        .ftq_i       (ftq_ifu_block),
        .ftq_id_i    (ftq_ifu_id),
        .ftq_accept_o(ifu_ftq_accept),

        .csr_i({csr_pg, csr_da, csr_dmw0, csr_dmw1, csr_plv}),
        .tlb_i(tlb_i),
        .tlb_o(tlb_o),

        // <-> Frontend <-> ICache
        .icache_rreq_o  (icache_read_req_o),
        .icache_raddr_o (icache_read_addr_o),
        .icache_rvalid_i(icache_read_valid_i),
        .icache_rdata_i (icache_read_data_i),


        // <-> Frontend <-> Instruction Buffer
        .stallreq_i    (instr_buffer_stallreq_i),
        .instr_buffer_o(ifu_instr_output)
    );



endmodule
