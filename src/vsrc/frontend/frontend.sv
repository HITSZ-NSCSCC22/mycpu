`include "core_types.sv"
`include "core_config.sv"
`include "frontend/frontend_defines.sv"

`include "frontend/ftq.sv"
`include "frontend/ifu.sv"

module frontend
    import core_types::*;
    import core_config::*;
    import tlb_types::inst_tlb_t;
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
    input logic backend_commit_i,

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
    input logic [19:0] inst_tlb_tag,
    input logic inst_tlb_found,
    input logic inst_tlb_v,
    input logic inst_tlb_d,
    input logic [1:0] inst_tlb_mat,
    input logic [1:0] inst_tlb_plv

);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    // TODO: move excp to correct position
    logic excp_tlbr, excp_pif, excp_ppi, excp_adef;
    // assign excp_tlbr = !inst_tlb_found && inst_addr_trans_en;
    // assign excp_pif = !inst_tlb_v && inst_addr_trans_en;
    // assign excp_ppi = (csr_plv > inst_tlb_plv) && inst_addr_trans_en;
    // assign excp_adef = (pc[0] || pc[1]) | (pc[31] && (csr_plv == 2'd3) && inst_addr_trans_en);

    assign instr_buffer_o[0].excp = excp_tlbr | excp_pif | excp_ppi | excp_adef;
    assign instr_buffer_o[0].excp_num = {excp_ppi, excp_pif, excp_tlbr, excp_adef};

    assign instr_buffer_o[1].excp = excp_tlbr | excp_pif | excp_ppi | excp_adef;
    assign instr_buffer_o[1].excp_num = {excp_ppi, excp_pif, excp_tlbr, excp_adef};

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
        end else if (ftq_full) begin
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
            bpu_ftq_block.is_cross_cacheline = (pc[3:2] != 2'b00);
        end else begin
            bpu_ftq_block = 0;
        end
    end

    ftq_ifu_t ftq_ifu_block;
    logic ifu_ftq_accept;

    ftq u_ftq (
        .clk(clk),
        .rst(rst),

        // Flush
        .backend_flush_i(backend_flush_i),

        // <-> Frontend
        .instr_buffer_stallreq_i(instr_buffer_stallreq_i),

        // <-> BPU
        .bpu_i           (bpu_ftq_block),
        .bpu_queue_full_o(ftq_full),

        // <-> Backend
        .backend_commit_i(backend_commit_i),

        // <-> IFU
        .ifu_o       (ftq_ifu_block),
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
        .ftq_accept_o(ifu_ftq_accept),

        .csr_i({csr_pg, csr_da, csr_dmw0, csr_dmw1, csr_plv}),
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
