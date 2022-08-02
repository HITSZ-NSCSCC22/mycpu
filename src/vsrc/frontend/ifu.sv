`include "frontend/frontend_defines.sv"
`include "core_types.sv"
`include "core_config.sv"
`include "TLB/tlb_types.sv"

`include "frontend/predecoder.sv"
`include "utils/normal_priority_encoder.sv"


module ifu
    import core_types::*;
    import core_config::*;
    import tlb_types::inst_tlb_t;
    import tlb_types::tlb_inst_t;
(
    input logic clk,
    input logic rst,

    // Flush
    input logic backend_flush_i,
    input logic frontend_redirect_i,


    // <-> Fetch Target Queue
    input ftq_block_t ftq_i,
    input logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] ftq_id_i,
    output logic ftq_accept_o,  // In current cycle

    // Addr translation related
    // <- Frontend <- CSR regs
    input  ifu_csr_t  csr_i,
    // <-> Frontend <-> TLB
    output inst_tlb_t tlb_o,
    input  tlb_inst_t tlb_i,

    // Predecoder Redirect
    output logic predecoder_redirect_o,
    output logic [ADDR_WIDTH-1:0] predecoder_redirect_target_o,
    output logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] predecoder_redirect_ftq_id_o,

    // <-> Frontend <-> ICache
    output logic [1:0] icache_rreq_o,
    output logic [1:0] icache_rreq_uncached_o,
    output logic [1:0][ADDR_WIDTH-1:0] icache_raddr_o,
    input logic [1:0] icache_rreq_ack_i,
    input logic [1:0] icache_rvalid_i,
    input logic [1:0][ICACHELINE_WIDTH-1:0] icache_rdata_i,


    // <-> Frontend <-> Instruction Buffer
    input logic stallreq_i,
    output instr_info_t instr_buffer_o[FETCH_WIDTH]
);

    // Pipeline control signals
    logic p0_advance, p1_advance, p2_advance;
    // P1 signal
    logic p1_send_rreq, p1_send_rreq_delay1;
    ftq_block_t p1_ftq_block;
    // P2 signal
    logic p2_read_done, p2_read_already_done;  // Read done is same cycle as ICache return valid
    logic p2_rreq_ack;  // Read request is accepted by ICache
    logic p2_in_transaction;  // Currently in transaction and not done yet
    ftq_block_t p2_ftq_block;
    // Flush state
    logic is_flushing_r;


    // FTQ handshake, FTQ can move to next block
    assign ftq_accept_o = p0_advance;
    // Pipeline control signals
    assign p0_advance = (p1_advance | ~p1_ftq_block.valid) & ftq_i.valid;
    assign p1_advance = p1_ftq_block.valid & ~p2_in_transaction & ~stallreq_i;
    assign p2_advance   = p2_ftq_block.valid & (p2_read_done | ~p2_read_transaction.sent_req) & ~stallreq_i;
    // FTQ block
    assign p1_ftq_block = p1_data.ftq_block;
    assign p2_ftq_block = p2_read_transaction.ftq_block;

    // P3
    // Predecoder
    logic [FETCH_WIDTH-1:0] predecoder_is_unconditional;
    logic [FETCH_WIDTH-1:0] predecoder_is_register_jump;
    logic [FETCH_WIDTH-1:0][ADDR_WIDTH-1:0] predecoder_jump_target;
    logic [$clog2(FETCH_WIDTH)-1:0] predecoder_unconditional_index;


    /////////////////////////////////////////////////////////////////////////////////
    // P0, send read req to TLB
    /////////////////////////////////////////////////////////////////////////////////
    // P0 PC
    logic [ADDR_WIDTH-1:0] p0_pc;
    assign p0_pc = ftq_i.start_pc;
    // TLB search req
    logic dmw0_en, dmw1_en, trans_en;
    assign dmw0_en = ((csr_i.dmw0[`PLV0] && csr_i.plv == 2'd0) || (csr_i.dmw0[`PLV3] && csr_i.plv == 2'd3)) && (p0_pc[31:29] == csr_i.dmw0[`VSEG]); // Direct map window 0
    assign dmw1_en = ((csr_i.dmw1[`PLV0] && csr_i.plv == 2'd0) || (csr_i.dmw1[`PLV3] && csr_i.plv == 2'd3)) && (p0_pc[31:29] == csr_i.dmw1[`VSEG]); // Direct map window 1
    assign trans_en = csr_i.pg && !csr_i.da && !dmw0_en && !dmw1_en; // Not in direct map windows, enable paging
    // Send req to TLB
    assign tlb_o.fetch = p0_advance;
    assign tlb_o.dmw0_en = dmw0_en;
    assign tlb_o.dmw1_en = dmw1_en;
    assign tlb_o.trans_en = trans_en;
    assign tlb_o.vaddr = p0_pc;


    ////////////////////////////////////////////////////////////////////////////////
    // P1, send read req to ICache or generate exception
    ////////////////////////////////////////////////////////////////////////////////
    // P1 data structure
    typedef struct packed {
        ftq_block_t ftq_block;
        logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] ftq_id;
        inst_tlb_t tlb_rreq;
        ifu_csr_t csr;
    } p1_t;
    p1_t p1_data;
    logic [ADDR_WIDTH-1:0] p1_pc;
    logic p1_uncache;  // Fetch request is uncached, generated using csr & tlb

    assign p1_pc = p1_data.ftq_block.start_pc;
    assign p1_uncache = p1_data.csr.da ?p1_data.csr.datf == 0:
                        p1_data.tlb_rreq.dmw0_en ? p1_data.csr.dmw0[`DMW_MAT] == 0 :
                        p1_data.tlb_rreq.dmw1_en ? p1_data.csr.dmw1[`DMW_MAT] == 0 : 
                        tlb_i.tlb_mat == 0;
    always_ff @(posedge clk) begin
        if (backend_flush_i | predecoder_redirect_o) begin
            p1_data <= 0;
        end else if (p0_advance & frontend_redirect_i) begin
            p1_data <= 0;
        end else if (p0_advance) begin
            p1_data.ftq_block <= ftq_i;
            p1_data.ftq_id <= ftq_id_i;
            p1_data.tlb_rreq <= tlb_o;
            p1_data.csr <= csr_i;
        end else if (p1_advance) begin
            p1_data <= 0;
        end
    end

    // Condition when to send rreq to ICache
    // p1_advance and no exception
    logic excp, excp_tlbr, excp_pif, excp_ppi, excp_adef;
    assign excp = excp_tlbr | excp_pif | excp_ppi | excp_adef;
    // TLB not found, trigger a TLBR
    assign excp_tlbr = !tlb_i.tlb_found && p1_data.tlb_rreq.trans_en;
    // TLB found with invalid page, trigger a PIF
    assign excp_pif = !tlb_i.tlb_v && p1_data.tlb_rreq.trans_en;
    // TLB found with not enough PLV, trigger a PPI
    assign excp_ppi = (p1_data.csr.plv > tlb_i.tlb_plv) && p1_data.tlb_rreq.trans_en;
    // PC is not aligned
    assign excp_adef = (p1_pc[0] || p1_pc[1]) | (p1_pc[31]&& p1_data.csr.plv == 2'd3&& p1_data.tlb_rreq.trans_en);
    assign p1_send_rreq = p1_advance & ~excp;




    // Send read req to ICache
    always_comb begin
        if (p1_send_rreq) begin
            // Send rreq to ICache if FTQ input is valid and not in flushing state
            icache_rreq_o[0] = 1;
            icache_rreq_o[1] = p1_data.ftq_block.is_cross_cacheline ? 1 : 0;
            icache_rreq_uncached_o[0] = p1_uncache;
            icache_rreq_uncached_o[1] = p1_data.ftq_block.is_cross_cacheline ? p1_uncache : 0;
            icache_raddr_o[0] = {tlb_i.tag, p1_pc[11:4], 4'b0};
            icache_raddr_o[1] = p1_data.ftq_block.is_cross_cacheline ? {tlb_i.tag, p1_pc[11:4], 4'b0} + 16 : 0; // TODO: remove magic number
        end else if (p2_in_transaction) begin
            // Or P1 is in transaction
            icache_rreq_o[0] = 1;
            icache_rreq_o[1] = p2_ftq_block.is_cross_cacheline ? 1 : 0;
            icache_rreq_uncached_o[0] = p2_read_transaction.uncached;
            icache_rreq_uncached_o[1] = p2_ftq_block.is_cross_cacheline ? p2_read_transaction.uncached : 0;
            icache_raddr_o[0] = {
                p2_read_transaction.tlb_result.tag, p2_ftq_block.start_pc[11:4], 4'b0
            };
            icache_raddr_o[1] = p2_ftq_block.is_cross_cacheline ? {p2_read_transaction.tlb_result.tag, p2_ftq_block.start_pc[11:4], 4'b0} + 16 : 0; // TODO: remove magic number
        end else begin
            icache_rreq_o = 0;
            icache_rreq_uncached_o = 0;
            icache_raddr_o = 0;
        end
    end

    /////////////////////////////////////////////////////////////////////////////////
    // P2, read transaction, wait for read valid from ICache
    /////////////////////////////////////////////////////////////////////////////////
    // Flush state
    always_ff @(posedge clk) begin : is_flushing_ff
        if (rst) begin
            is_flushing_r <= 0;
        end else if ((backend_flush_i | predecoder_redirect_o) & (p2_in_transaction | p1_send_rreq)) begin
            // Enter a flusing state if flush_i and read transaction on-the-fly
            is_flushing_r <= 1;
        end else if (stallreq_i) begin
            // Hold
        end else if (p2_read_done | p2_read_already_done) begin
            // Reset when read transaction is done
            is_flushing_r <= 0;
        end
    end

    // P2 data structure
    typedef struct packed {
        logic sent_req;
        logic uncached;
        logic excp;
        logic [15:0] excp_num;
        ftq_block_t ftq_block;
        logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] ftq_id;
        logic [1:0] icache_rreq_ack_r;
        logic [1:0] icache_rvalid_r;
        logic [1:0][ICACHELINE_WIDTH-1:0] icache_rdata_r;
        inst_tlb_t tlb_rreq;
        tlb_inst_t tlb_result;
        ifu_csr_t csr;
    } read_transaction_t;
    read_transaction_t p2_read_transaction;
    logic [ADDR_WIDTH-1:0] p2_pc;
    assign p2_pc = p2_read_transaction.ftq_block.start_pc;


    assign p2_in_transaction = p2_read_transaction.sent_req & ~p2_read_done;
    assign p2_read_done = p2_rreq_ack & ( p2_ftq_block.is_cross_cacheline ?
            (icache_rvalid_i[0] | p2_read_transaction.icache_rvalid_r[0]) & (icache_rvalid_i[1] | p2_read_transaction.icache_rvalid_r[1]) :
            (icache_rvalid_i[0] | p2_read_transaction.icache_rvalid_r[0]));
    assign p2_rreq_ack =  p2_ftq_block.is_cross_cacheline ?
            (p2_read_transaction.icache_rreq_ack_r[0]) & (p2_read_transaction.icache_rreq_ack_r[1]) :
            (p2_read_transaction.icache_rreq_ack_r[0]);
    always_ff @(posedge clk) begin
        if (rst) p2_read_already_done <= 0;
        else if (p1_send_rreq) p2_read_already_done <= 0;
        else if (p2_read_done) p2_read_already_done <= 1;
    end
    always_ff @(posedge clk) begin : p2_ff
        if (rst) begin
            p2_read_transaction <= 0;
        end else if (((~p1_send_rreq & p1_advance) | ~(p2_in_transaction | p1_send_rreq)) & (backend_flush_i| predecoder_redirect_o)) begin
            p2_read_transaction <= 0;
        end else if (p1_advance) begin
            p2_read_transaction.sent_req <= p1_send_rreq;
            p2_read_transaction.uncached <= p1_uncache;
            p2_read_transaction.excp <= excp;
            p2_read_transaction.excp_num <= {11'b0, excp_ppi, excp_pif, excp_tlbr, excp_adef, 1'b0};
            p2_read_transaction.ftq_block <= p1_ftq_block;
            p2_read_transaction.ftq_id <= p1_data.ftq_id;
            p2_read_transaction.icache_rreq_ack_r <= icache_rreq_ack_i;
            p2_read_transaction.icache_rvalid_r <= 0;
            p2_read_transaction.icache_rdata_r <= 0;
            p2_read_transaction.tlb_rreq <= p1_data.tlb_rreq;
            p2_read_transaction.tlb_result <= tlb_i;
            p2_read_transaction.csr <= p1_data.csr;
        end else if (p2_advance) begin
            // Reset if done and not stalling
            p2_read_transaction <= 0;
        end else begin
            // Store rvalid in P1 data structure
            // This is required since ICache do not guarantee rvalid of the two ports is returned in the same cycle
            if (icache_rvalid_i[0]) begin
                p2_read_transaction.icache_rvalid_r[0] <= 1;
                p2_read_transaction.icache_rdata_r[0]  <= icache_rdata_i[0];
            end
            if (icache_rvalid_i[1]) begin
                p2_read_transaction.icache_rvalid_r[1] <= 1;
                p2_read_transaction.icache_rdata_r[1]  <= icache_rdata_i[1];
            end
            // Store ACK in P1 data structure
            if (icache_rreq_ack_i[0]) p2_read_transaction.icache_rreq_ack_r[0] <= 1;
            if (icache_rreq_ack_i[1]) p2_read_transaction.icache_rreq_ack_r[1] <= 1;
        end
    end

    logic [FETCH_WIDTH*2-1:0][DATA_WIDTH-1:0] cacheline_combined; // Same cycle as ICache return, used in P2
    assign cacheline_combined = {
        icache_rvalid_i[1] ? icache_rdata_i[1] : p2_read_transaction.icache_rdata_r[1],
        icache_rvalid_i[0] ? icache_rdata_i[0] : p2_read_transaction.icache_rdata_r[0]
    };
    logic [FETCH_WIDTH-1:0][DATA_WIDTH-1:0] p2_instructions;
    logic [FETCH_WIDTH-1:0][ADDR_WIDTH-1:0] p2_pcs;
    always_comb begin
        for (integer i = 0; i < FETCH_WIDTH; i++) begin
            p2_instructions[i] = cacheline_combined[p2_ftq_block.start_pc[3:2]+i];
            p2_pcs[i] = p2_ftq_block.start_pc + i * 4;
        end
    end

    // P1 debug, for observability
    logic [1:0] debug_p2_rvalid_r = p2_read_transaction.icache_rvalid_r;



    /////////////////////////////////////////////////////////////////////////////////
    // P3, send instr info to IB & Predecoder
    /////////////////////////////////////////////////////////////////////////////////
    logic [FETCH_WIDTH-1:0] debug_predicted_taken;
    always_comb begin
        for (integer i = 0; i < FETCH_WIDTH; ++i) begin
            debug_predicted_taken[i] = instr_buffer_o[i].special_info.predicted_taken;
        end
    end
    logic [$clog2(FETCH_WIDTH+1)-1:0] p2_block_length;
    assign p2_block_length = predecoder_redirect_o ? (predecoder_unconditional_index+1 < p2_ftq_block.length ? predecoder_unconditional_index +1 : p2_ftq_block.length) : p2_ftq_block.length;
    always_ff @(posedge clk) begin : p3_ff
        if (rst) begin
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                instr_buffer_o[i] <= 0;
            end
        end else if (backend_flush_i) begin
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                instr_buffer_o[i] <= 0;
            end
        end else if (stallreq_i) begin
            // Hold output
        end else if (p2_advance & ~is_flushing_r) begin
            // Default 0
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                instr_buffer_o[i] <= 0;
            end
            // If p1 read done, pass data to IB
            // However, if p1 read done comes from flushing, do not pass down to IB
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                if (i < p2_block_length) begin
                    if (i == p2_block_length - 1) begin
                        // Mark the instruction as last in block, used when commit
                        instr_buffer_o[i].is_last_in_block <= 1;
                        // Mark the last instruction if:
                        // 1. prediction valid
                        // 2. no TLBR or other exception detected
                        instr_buffer_o[i].special_info.predicted_taken <= p2_ftq_block.predicted_taken | predecoder_redirect_o;
                        instr_buffer_o[i].special_info.predict_valid <= p2_ftq_block.predict_valid | predecoder_redirect_o;
                    end
                    instr_buffer_o[i].valid <= 1;
                    instr_buffer_o[i].pc <= p2_ftq_block.start_pc + i * 4;  // Instr is 4 bytes long
                    // Set to 0 is exception occurs
                    instr_buffer_o[i].instr <= p2_read_transaction.excp ? 0 : p2_instructions[i];
                    // Exception info
                    instr_buffer_o[i].excp <= p2_read_transaction.excp;
                    instr_buffer_o[i].excp_num <= p2_read_transaction.excp_num;
                    instr_buffer_o[i].ftq_id <= p2_read_transaction.ftq_id;
                    instr_buffer_o[i].ftq_block_idx <= i[1:0];
                end
            end
        end else begin
            // Otherwise keep 0
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                instr_buffer_o[i] <= 0;
            end
        end
    end
    // Predecoder
    generate
        for (genvar i = 0; i < FETCH_WIDTH; i++) begin
            predecoder u_predecoder (
                .instr_i              (p2_instructions[i]),
                .pc_i                 (p2_pcs[i]),
                .is_unconditional_o   (predecoder_is_unconditional[i]),
                .is_register_jump_o   (predecoder_is_register_jump[i]),
                .jump_target_address_o(predecoder_jump_target[i])
            );

        end
    endgenerate
    normal_priority_encoder #(
        .WIDTH(FETCH_WIDTH)
    ) u_predecoder_uncondtional_index_encoder (
        .priority_vector(predecoder_is_unconditional & ~predecoder_is_register_jump),
        .encoded_result (predecoder_unconditional_index)
    );
    // Predecoder output
    assign predecoder_redirect_o = |(predecoder_is_unconditional & ~predecoder_is_register_jump) & ~is_flushing_r & (predecoder_unconditional_index +1 < p2_ftq_block.length) & p2_advance;
    assign predecoder_redirect_target_o = predecoder_jump_target[predecoder_unconditional_index];
    assign predecoder_redirect_ftq_id_o = predecoder_redirect_o ? p2_read_transaction.ftq_id : 0;



endmodule
