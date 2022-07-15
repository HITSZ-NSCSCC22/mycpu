`include "core_types.sv"
`include "core_config.sv"
`include "frontend/frontend_defines.sv"
`include "BPU/include/bpu_types.sv"

`include "frontend/ftq.sv"
`include "frontend/ifu.sv"
`include "BPU/bpu.sv"


module frontend
    import core_types::*;
    import core_config::*;
    import bpu_types::*;
    import tlb_types::inst_tlb_t;
    import tlb_types::tlb_inst_t;
(
    input logic clk,
    input logic rst,

    // <-> ICache
    // ICache is fixed dual port
    output logic [1:0] icache_read_req_o,
    output logic [1:0] icache_read_req_uncached_o,
    output logic [1:0][ADDR_WIDTH-1:0] icache_read_addr_o,
    input logic [1:0] icache_rreq_ack_i,
    input logic [1:0] icache_read_valid_i,
    input logic [1:0][ICACHELINE_WIDTH-1:0] icache_read_data_i,


    // <-> Backend
    input logic [ADDR_WIDTH-1:0] backend_next_pc_i,
    input logic backend_flush_i,
    input logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_flush_ftq_id_i,
    input logic [COMMIT_WIDTH-1:0] backend_commit_bitmask_i,
    input logic [COMMIT_WIDTH-1:0][$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_commit_ftq_id_i,
    input backend_commit_meta_t [COMMIT_WIDTH-1:0] backend_commit_meta_i,

    // <-> Instruction buffer
    input logic instr_buffer_stallreq_i,
    output instr_info_t instr_buffer_o[FETCH_WIDTH],

    // <- CSR
    input logic csr_pg,
    input logic csr_da,
    input logic [31:0] csr_dmw0,
    input logic [31:0] csr_dmw1,
    input logic [1:0] csr_plv,
    input logic [1:0] csr_datf,

    // <-> TLB
    output inst_tlb_t tlb_o,
    input  tlb_inst_t tlb_i
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;


    logic main_bpu_redirect;
    logic [ADDR_WIDTH-1:0] pc, next_pc, sequential_pc, main_bpu_redirect_pc;
    assign sequential_pc = pc + 4 * bpu_ftq_block.length;

    // BPU
    bpu_ftq_t bpu_ftq_block;
    ftq_bpu_meta_t ftq_bpu_meta;

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
        end else if (main_bpu_redirect) begin
            next_pc = main_bpu_redirect_pc;
        end else begin
            next_pc = sequential_pc;
        end
    end

    bpu u_bpu (
        .clk(clk),
        .rst(rst),
        .pc_i(pc),
        // FTQ
        .ftq_full_i(ftq_full),
        .ftq_predict_o(bpu_ftq_block),
        // Train
        .ftq_meta_i(ftq_bpu_meta),

        // PC
        .main_redirect_o(main_bpu_redirect),
        .main_redirect_pc_o(main_bpu_redirect_pc)

    );


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
        .bpu_meta_i      (),
        .bpu_queue_full_o(ftq_full),
        .bpu_meta_o      (ftq_bpu_meta),

        // <-> Backend
        .backend_commit_bitmask_i(backend_commit_bitmask_i),
        .backend_commit_ftq_id_i(backend_commit_ftq_id_i),
        .backend_commit_meta_i(backend_commit_meta_i),

        // <-> IFU
        .ifu_o       (ftq_ifu_block),
        .ifu_ftq_id_o(ftq_ifu_id),
        .ifu_accept_i(ifu_ftq_accept)
    );


    instr_info_t ifu_instr_output[FETCH_WIDTH];
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

        .csr_i({csr_pg, csr_da, csr_dmw0, csr_dmw1, csr_plv, csr_datf}),
        .tlb_i(tlb_i),
        .tlb_o(tlb_o),

        // <-> Frontend <-> ICache
        .icache_rreq_o(icache_read_req_o),
        .icache_rreq_uncached_o(icache_read_req_uncached_o),
        .icache_raddr_o(icache_read_addr_o),
        .icache_rreq_ack_i(icache_rreq_ack_i),
        .icache_rvalid_i(icache_read_valid_i),
        .icache_rdata_i(icache_read_data_i),


        // <-> Frontend <-> Instruction Buffer
        .stallreq_i    (instr_buffer_stallreq_i),
        .instr_buffer_o(ifu_instr_output)
    );



endmodule
