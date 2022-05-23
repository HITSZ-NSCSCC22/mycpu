`include "instr_info.sv"
`include "pipeline_defines.sv"
module frontend #(
    parameter FETCH_WIDTH = 2,
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32
) (
    input logic clk,
    input logic rst,

    // <-> ICache
    output logic [ADDR_WIDTH-1:0] icache_read_addr_o[FETCH_WIDTH],
    input logic icache_stallreq_i,  // ICache cannot accept more addr input
    input logic icache_read_valid_i[FETCH_WIDTH],
    input logic [ADDR_WIDTH-1:0] icache_read_addr_i[FETCH_WIDTH],
    input logic [DATA_WIDTH-1:0] icache_read_data_i[FETCH_WIDTH],


    // <-> Backend
    input branch_update_info_t branch_update_info_i,
    input logic [ADDR_WIDTH-1:0] backend_next_pc_i,
    input logic backend_flush_i,

    // <-> Instruction buffer
    input logic instr_buffer_stallreq_i,
    output instr_buffer_info_t instr_buffer_o[FETCH_WIDTH],

    // <- CSR
    input logic csr_pg,
    input logic csr_da,
    input logic [31:0] csr_dmw0,
    input logic [31:0] csr_dmw1,
    input logic [1:0]  csr_plv,
    input logic [1:0]  csr_datf,
    input logic disable_cache,

    // <-> TLB
    output logic[31:0]inst_addr,
    output logic inst_addr_trans_en,
    output logic dmw0_en,
    output logic dmw1_en,
    input logic  inst_tlb_found,
    input logic  inst_tlb_v,
    input logic  inst_tlb_d,
    input logic [1:0]inst_tlb_mat,
    input logic [1:0]inst_tlb_plv      

);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    //addr trans TODO:修改dmw的赋值(还不确定双发射情况下pc的赋值方式)
    assign inst_addr = pc;
    assign inst_addr_trans_en = csr_pg && !csr_da && !dmw0_en && !dmw1_en;
    assign dmw0_en = ((csr_dmw0[`PLV0] && csr_plv == 2'd0) || (csr_dmw0[`PLV3] && csr_plv == 2'd3)) && (pc[31:29] == csr_dmw0[`VSEG]);
    assign dmw1_en = ((csr_dmw1[`PLV0] && csr_plv == 2'd0) || (csr_dmw1[`PLV3] && csr_plv == 2'd3)) && (pc[31:29] == csr_dmw1[`VSEG]);

    //excp
    logic excp_tlbr,excp_pif,excp_ppi,excp_adef;
    assign excp_tlbr = !inst_tlb_found && inst_addr_trans_en;
    assign excp_pif  = !inst_tlb_v && inst_addr_trans_en;
    assign excp_ppi  = (csr_plv > inst_tlb_plv) && inst_addr_trans_en;
    assign excp_adef = (pc[0] || pc[1]) | (pc[31] && (csr_plv == 2'd3) && inst_addr_trans_en);

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

    always_comb begin : next_pc_comb
        if (backend_flush_i) begin
            next_pc = backend_next_pc_i;
        end else if (instr_buffer_stallreq_i) begin
            next_pc = pc;
        end else if (icache_stallreq_i) begin
            next_pc = pc;
        end else begin
            next_pc = pc + 8;
        end
    end

    // ICache read_addr_o
    always_comb begin : icache_read_addr_o_comb
        for (integer i = 0; i < FETCH_WIDTH; i++) begin
            icache_read_addr_o[i] = pc + i * 4;
        end
    end

    typedef struct packed {
        bit valid;
        bit [ADDR_WIDTH-1:0] pc;
        bit [DATA_WIDTH-1:0] instr;
    } icache_resp_t;
    icache_resp_t icache_resp_buffer[FETCH_WIDTH];
    always_ff @(posedge clk or negedge rst_n) begin : icache_resp_buffer_ff
        if (!rst_n || icache_resp_ready) begin
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                icache_resp_buffer[i] <= 0;
            end
        end else begin
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                if (icache_read_valid_i[i]) begin
                    icache_resp_buffer[i].valid <= 1;
                    icache_resp_buffer[i].pc <= icache_read_addr_i[i];
                    icache_resp_buffer[i].instr <= icache_read_data_i[i];
                end
            end
        end
    end
    logic icache_resp_ready;  // 1 if all the instr in icache_resp_buffer is valid
    always_comb begin : icache_resp_ready_comb
        icache_resp_ready = 1;
        for (integer i = 0; i < FETCH_WIDTH; i++) begin
            icache_resp_ready = icache_resp_ready & icache_resp_buffer[i].valid;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin : instr_buffer_o_ff
        if (!rst_n || backend_flush_i) begin
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                instr_buffer_o[i] <= 0;
            end
        end else begin
            // Keep 0 for most of the time
            for (integer i = 0; i < FETCH_WIDTH; i++) begin
                instr_buffer_o[i] <= 0;
            end
            if (icache_resp_ready && !instr_buffer_stallreq_i) begin
                for (integer i = 0; i < FETCH_WIDTH; i++) begin
                    instr_buffer_o[i].valid <= 1;
                    instr_buffer_o[i].pc <= icache_resp_buffer[i].pc;
                    instr_buffer_o[i].instr <= icache_resp_buffer[i].instr;
                end
            end
        end
    end

endmodule
