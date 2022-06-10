`include "frontend/frontend_defines.sv"
`include "core_types.sv"
`include "core_config.sv"
`include "tlb_types.sv"


module ifu
    import core_types::*;
    import core_config::*;
    import tlb_types::inst_tlb_t;
(
    input logic clk,
    input logic rst,

    // Flush
    input flush_i,

    // <-> Fetch Target Queue
    input ftq_ifu_t ftq_i,
    output logic ftq_accept_o,  // In current cycle

    // Addr translation related
    // <- Frontend <- CSR regs
    input  ifu_csr_t  csr_i,
    // -> Frontend -> TLB
    output inst_tlb_t tlb_o,

    // <-> Frontend <-> ICache
    output logic [1:0] icache_rreq_o,
    output logic [1:0][ADDR_WIDTH-1:0] icache_raddr_o,
    input logic [1:0] icache_rvalid_i,
    input logic [1:0][ICACHELINE_WIDTH-1:0] icache_rdata_i,


    // <-> Frontend <-> Instruction Buffer
    input logic stallreq_i,
    output instr_buffer_info_t instr_buffer_o[FETCH_WIDTH]
);
    /////////////////////////////////////////////////////////////////////////////////
    // P0, send read req to ICache & TLB
    /////////////////////////////////////////////////////////////////////////////////
    logic p0_send_rreq;
    // Condition when to send rreq to ICache, see doc for detail
    assign p0_send_rreq = ftq_i.valid & ~is_flushing & ~stallreq_i & ~p1_stallreq;
    assign ftq_accept_o = p0_send_rreq;  // FTQ handshake, same cycle as ftq_i

    // P0 PC
    logic [ADDR_WIDTH-1:0] p0_pc = ftq_i.start_pc;

    // TLB search req
    logic dmw0_en, dmw1_en;
    assign dmw0_en = ((csr_i.dmw0[`PLV0] && csr_i.plv == 2'd0) || (csr_i.dmw0[`PLV3] && csr_i.plv == 2'd3)) && (p0_pc[31:29] == csr_i.dmw0[`VSEG]); // Direct map window 0
    assign dmw1_en = ((csr_i.dmw1[`PLV0] && csr_i.plv == 2'd0) || (csr_i.dmw1[`PLV3] && csr_i.plv == 2'd3)) && (p0_pc[31:29] == csr_i.dmw1[`VSEG]); // Direct map window 1
    assign tlb_o.dmw0_en = dmw0_en;
    assign tlb_o.dmw1_en = dmw1_en;
    assign tlb_o.trans_en = csr_i.pg && !csr_i.da && !dmw0_en && !dmw1_en; // Not in direct map windows, enable paging
    assign tlb_o.vaddr = p0_pc;

    // Send read req to ICache & TLB
    always_comb begin
        if (p0_send_rreq) begin
            // Send rreq to ICache if FTQ input is valid and not in flushing state
            icache_rreq_o[0] = 1;
            icache_rreq_o[1] = ftq_i.is_cross_cacheline ? 1 : 0;
            icache_raddr_o[0] = {ftq_i.start_pc[ADDR_WIDTH-1:4], 4'b0};
            icache_raddr_o[1] = ftq_i.is_cross_cacheline ? {ftq_i.start_pc[ADDR_WIDTH-1:4], 4'b0} + 16 : 0; // TODO: remove magic number
            // Send req to TLB
            tlb_o.fetch = 1;
        end else begin
            icache_rreq_o = 0;
            icache_raddr_o = 0;
            tlb_o.fetch = 0;
        end
    end

    /////////////////////////////////////////////////////////////////////////////////
    // P1
    /////////////////////////////////////////////////////////////////////////////////
    // Flush state
    logic is_flushing_r, is_flushing;
    assign is_flushing = is_flushing_r | flush_i;
    always_ff @(posedge clk) begin : is_flushing_ff
        if (rst) begin
            is_flushing_r <= 0;
        end else if (flush_i & p1_read_transaction.valid & (~p1_read_done | stallreq_i)) begin
            // Enter a flusing state if flush_i and read transaction on-the-fly
            is_flushing_r <= 1;
        end else if (p1_read_done) begin
            // Reset when read transaction is done
            is_flushing_r <= 0;
        end
    end

    // P1 data structure
    typedef struct packed {
        logic valid;
        logic [`InstAddrBus] start_pc;
        logic is_cross_cacheline;
        logic [$clog2(`FETCH_WIDTH+1)-1:0] length;
        logic [1:0] icache_rvalid_r;
        logic [1:0][ICACHELINE_WIDTH-1:0] icache_rdata_r;
    } read_transaction_t;
    read_transaction_t p1_read_transaction;

    logic p1_read_done;  // Read done is same cycle as ICache return valid
    assign p1_read_done = p1_read_transaction.is_cross_cacheline ?
    (icache_rvalid_i[0] | p1_read_transaction.icache_rvalid_r[0]) & (icache_rvalid_i[1]| p1_read_transaction.icache_rvalid_r[1]) :
    (icache_rvalid_i[0] | p1_read_transaction.icache_rvalid_r[0]);
    logic p1_stallreq;  // Currently in transaction and not done yet
    assign p1_stallreq = p1_read_transaction.valid & ~p1_read_done;
    always_ff @(posedge clk) begin : p1_ff
        if (rst) begin
            p1_read_transaction <= 0;
        end else if (p0_send_rreq) begin
            // If P0 sent rreq to ICache, move info from P0 to P1
            p1_read_transaction.valid <= 1;
            p1_read_transaction.start_pc <= ftq_i.start_pc;
            p1_read_transaction.is_cross_cacheline <= ftq_i.is_cross_cacheline;
            p1_read_transaction.length <= ftq_i.length;
            p1_read_transaction.icache_rvalid_r <= 0;
            p1_read_transaction.icache_rdata_r <= 0;
        end else if (p1_read_done & ~stallreq_i) begin
            // Reset if done and not stalling
            p1_read_transaction <= 0;
        end else begin
            // Store rvalid in P1 data structure
            // This is required since ICache do not guarantee rvalid of the two ports is returned in the same cycle
            if (icache_rvalid_i[0]) begin
                p1_read_transaction.icache_rvalid_r[0] <= 1;
                p1_read_transaction.icache_rdata_r[0]  <= icache_rdata_i[0];
            end
            if (icache_rvalid_i[1]) begin
                p1_read_transaction.icache_rvalid_r[1] <= 1;
                p1_read_transaction.icache_rdata_r[1]  <= icache_rdata_i[1];
            end
        end
    end

    logic [FETCH_WIDTH*2-1:0][DATA_WIDTH-1:0] cacheline_combined; // Same cycle as ICache return, used in P2
    assign cacheline_combined = {
        icache_rvalid_i[1] ? icache_rdata_i[1] : p1_read_transaction.icache_rdata_r[1],
        icache_rvalid_i[0] ? icache_rdata_i[0] : p1_read_transaction.icache_rdata_r[0]
    };

    // P1 debug, for observability
    logic [ADDR_WIDTH-1:0] debug_p1_pc = p1_read_transaction.start_pc;  // DEBUG
    logic [1:0] debug_p1_rvalid_r = p1_read_transaction.icache_rvalid_r;


    /////////////////////////////////////////////////////////////////////////////////
    // P2, send instr info to IB
    /////////////////////////////////////////////////////////////////////////////////
    always_ff @(posedge clk) begin : p2_ff
        if (rst) begin
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                instr_buffer_o[i] <= 0;
            end
        end else if (is_flushing) begin
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                instr_buffer_o[i] <= 0;
            end
        end else if (stallreq_i) begin
            // Hold output
        end else if (p1_read_done) begin
            // If p1 read done, pass data to IB
            // However, if p1 read done comes from flushing, do not pass down to IB
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                // Default
                instr_buffer_o[i].is_last_in_block <= 0;

                if (i < p1_read_transaction.length) begin
                    if (i == p1_read_transaction.length - 1) begin
                        instr_buffer_o[i].valid <= 1;
                        instr_buffer_o[i].is_last_in_block <= 1; // Mark the instruction as last in block, used when commit
                        instr_buffer_o[i].pc <= p1_read_transaction.start_pc + i * 4;  // Instr is 4 bytes long
                        instr_buffer_o[i].instr <= cacheline_combined[p1_read_transaction.start_pc[3:2]+i];
                    end else begin
                        instr_buffer_o[i].valid <= 1;
                        instr_buffer_o[i].pc <= p1_read_transaction.start_pc + i * 4;  // Instr is 4 bytes long
                        instr_buffer_o[i].instr <= cacheline_combined[p1_read_transaction.start_pc[3:2]+i];
                    end
                end else begin
                    instr_buffer_o[i] <= 0;
                end
            end
        end else begin
            // Otherwise keep 0
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                instr_buffer_o[i] <= 0;
            end
        end
    end

endmodule
