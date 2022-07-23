`include "core_config.sv"
`include "core_types.sv"
`include "csr_defines.sv"
`include "TLB/tlb_types.sv"

module mem1
    import core_config::*;
    import core_types::*;
    import csr_defines::*;
    import tlb_types::*;
(
    input logic clk,
    input logic rst,

    // Pipeline control signals
    input  logic flush,
    input  logic clear,
    input  logic advance,
    output logic advance_ready,

    // Previous stage
    input ex_mem_struct ex_i,


    // <-> DCache
    output mem_dcache_rreq_t dcache_rreq_o,
    input logic dcache_ready_i,
    input logic dcache_ack_i,

    // <- TLB
    input tlb_data_t tlb_result_i,

    input logic LLbit_i,

    // Data forward
    // -> Dispatch
    // -> EX
    output data_forward_t data_forward_o,


    input [1:0] csr_plv,

    // <-> ICache, CACOP
    output logic icacop_en_o,
    output logic [1:0] icacop_mode_o,
    input logic icacop_ack_i,

    output logic dcacop_en_o,
    output logic [1:0] dcacop_mode_o,
    input logic dcacop_ack_i,

    // Next stage
    output mem1_mem2_struct mem2_o_buffer

);

    mem1_mem2_struct mem2_o;

    // Assign input
    special_info_t special_info;
    instr_info_t instr_info;

    logic mem_access_valid;

    logic access_mem, mem_store_op, mem_load_op;
    logic cacop_en, icache_op_en, dcache_op_en;
    logic [4:0] cacop_op;

    logic [`AluOpBus] aluop_i;

    logic [`RegBus] reg2_i;
    logic [ADDR_WIDTH-1:0] mem_vaddr, mem_paddr;

    // DCache ACK
    logic dcache_ack_r;

    // Exception handling
    logic excp, excp_adem, excp_tlbr, excp_pil, excp_pis, excp_ppi, excp_pme;
    logic [15:0] excp_num;

    logic uncache_en;

    assign instr_info = ex_i.instr_info;
    assign special_info = ex_i.instr_info.special_info;

    assign cacop_en = ex_i.cacop_en;
    assign icache_op_en = ex_i.icache_op_en;
    assign dcache_op_en = ex_i.dcache_op_en;
    assign cacop_op = ex_i.cacop_op;
    // ICACOP
    assign icacop_en_o = icache_op_en;
    assign icacop_mode_o = cacop_op[4:3];
    // DCACOP
    assign dcacop_en_o = dcache_op_en;
    assign dcacop_mode_o = cacop_op[4:3];

    assign aluop_i = ex_i.aluop;

    assign mem_paddr = {tlb_result_i.tag, tlb_result_i.index, tlb_result_i.offset};
    assign mem_vaddr = ex_i.mem_addr;
    assign reg2_i = ex_i.reg2;

    always_ff @(posedge clk) begin
        if (rst) dcache_ack_r <= 0;
        else if (advance | flush) dcache_ack_r <= 0;
        else if (dcache_ack_i) dcache_ack_r <= 1;
    end

    assign uncache_en = ex_i.data_uncache_en || (ex_i.data_addr_trans_en && (tlb_result_i.tlb_mat == 2'b0));

    assign access_mem = mem_load_op | mem_store_op;

    // Anything can trigger stall and modify register is considerd a "load" instr
    assign mem_load_op = special_info.mem_load;
    assign mem_store_op = special_info.mem_store & ~(aluop_i == `EXE_SC_OP & LLbit_i == 0);

    assign excp_adem = (access_mem || cacop_en) && ex_i.data_addr_trans_en && (csr_plv == 2'd3) && mem_vaddr[31];
    assign excp_tlbr = (access_mem || cacop_en) && !tlb_result_i.found && ex_i.data_addr_trans_en;
    assign excp_pil  = (mem_load_op | cacop_en)  && !tlb_result_i.tlb_v && ex_i.data_addr_trans_en;  // CACOP will generate pil exception
    assign excp_pis = mem_store_op && !tlb_result_i.tlb_v && ex_i.data_addr_trans_en;
    assign excp_ppi = access_mem && tlb_result_i.tlb_v && (csr_plv > tlb_result_i.tlb_plv) && ex_i.data_addr_trans_en;
    assign excp_pme  = mem_store_op && tlb_result_i.tlb_v && (csr_plv <= tlb_result_i.tlb_plv) && !tlb_result_i.tlb_d && ex_i.data_addr_trans_en;
    assign excp = excp_tlbr || excp_pil || excp_pis || excp_ppi || excp_pme || excp_adem || instr_info.excp;
    assign excp_num = {
        excp_pil, excp_pis, excp_ppi, excp_pme, excp_tlbr, excp_adem, instr_info.excp_num[9:0]
    };

    // Difftest mem info
    difftest_mem_info_t difftest_mem_info;
    assign difftest_mem_info.inst_ld_en = access_mem ? {
        2'b0,
        aluop_i == `EXE_LL_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_W_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_HU_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_H_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_BU_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_B_OP ? 1'b1 : 1'b0
    } : 0;

    assign difftest_mem_info.inst_st_en = access_mem ? {
        4'b0,
        aluop_i == `EXE_SC_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_ST_W_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_ST_H_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_ST_B_OP ? 1'b1 : 1'b0
    } : 0;

    assign difftest_mem_info.load_addr = mem_load_op ? mem_paddr : 0;
    assign difftest_mem_info.store_addr = mem_store_op ? mem_paddr : 0;
    assign difftest_mem_info.timer_64 = ex_i.timer_64;

    // Data forward
    assign data_forward_o = {mem2_o.wreg, !mem_load_op, mem2_o.waddr, mem2_o.wdata};


    //if mem1 has a mem request and cache is working 
    //then wait until cache finish its work
    assign advance_ready = (access_mem & mem_access_valid ) ? dcache_ready_i :
                            icache_op_en ? icacop_ack_i : 1;

    // Sanity check
    assign mem_access_valid = instr_info.valid;  //~excp & instr_info.valid;


    // DCache memory access request
    always_comb begin
        dcache_rreq_o = 0;
        if (advance & access_mem & mem_access_valid & dcache_ready_i & ~dcache_ack_r) begin
            dcache_rreq_o.ce = 1;
            dcache_rreq_o.uncache = uncache_en;
            dcache_rreq_o.pc = ex_i.instr_info.pc;
            case (aluop_i)
                `EXE_LD_B_OP, `EXE_LD_BU_OP: begin
                    dcache_rreq_o.addr = mem_paddr;
                    dcache_rreq_o.sel = 4'b0001 << mem_paddr[1:0];
                    dcache_rreq_o.req_type = 3'b000;
                end
                `EXE_LD_H_OP, `EXE_LD_HU_OP: begin
                    dcache_rreq_o.addr = mem_paddr;
                    dcache_rreq_o.sel = 4'b0011 << mem_paddr[1:0];
                    dcache_rreq_o.req_type = 3'b001;
                end
                `EXE_LD_W_OP: begin
                    dcache_rreq_o.addr = mem_paddr;
                    dcache_rreq_o.sel = 4'b1111;
                    dcache_rreq_o.req_type = 3'b010;
                end
                `EXE_ST_B_OP: begin
                    dcache_rreq_o.addr = mem_paddr;
                    dcache_rreq_o.we = 1;
                    dcache_rreq_o.req_type = 3'b000;
                    dcache_rreq_o.sel = 4'b0001 << mem_paddr[1:0];
                    dcache_rreq_o.data = {24'b0, reg2_i[7:0]} << (8 * mem_paddr[1:0]);
                end
                `EXE_ST_H_OP: begin
                    dcache_rreq_o.addr = mem_paddr;
                    dcache_rreq_o.we = 1;
                    dcache_rreq_o.req_type = 3'b001;
                    dcache_rreq_o.sel = 4'b0011 << mem_paddr[1:0];
                    dcache_rreq_o.data = {16'b0, reg2_i[15:0]} << (8 * mem_paddr[1:0]);
                end
                `EXE_ST_W_OP: begin
                    dcache_rreq_o.addr = mem_paddr;
                    dcache_rreq_o.we = 1;
                    dcache_rreq_o.req_type = 3'b010;
                    dcache_rreq_o.sel = 4'b1111;
                    dcache_rreq_o.data = reg2_i;
                end
                `EXE_LL_OP: begin
                    dcache_rreq_o.addr = mem_paddr;
                    dcache_rreq_o.sel = 4'b1111;
                    dcache_rreq_o.req_type = 3'b010;
                end
                `EXE_SC_OP: begin
                    if (LLbit_i == 1'b1) begin
                        dcache_rreq_o.addr = mem_paddr;
                        dcache_rreq_o.we = 1;
                        dcache_rreq_o.req_type = 3'b010;
                        dcache_rreq_o.sel = 4'b1111;
                        dcache_rreq_o.data = reg2_i;
                    end else begin
                        dcache_rreq_o = 0;
                    end
                end
                default: begin
                    // Reset AXI signals, IMPORTANT!
                    dcache_rreq_o = 0;
                end
            endcase
        end
    end

    // Output to next stage
    always_comb begin
        // Instr Info
        mem2_o.instr_info = ex_i.instr_info;
        mem2_o.instr_info.excp = excp;
        mem2_o.instr_info.excp_num = excp_num;

        mem2_o.wreg = ex_i.wreg;
        mem2_o.waddr = ex_i.waddr;
        mem2_o.wdata = ex_i.wdata;
        mem2_o.LLbit_we = 1'b0;
        mem2_o.LLbit_value = 1'b0;

        mem2_o.aluop = aluop_i;
        mem2_o.csr_signal = ex_i.csr_signal;
        mem2_o.mem_access_valid = mem_access_valid;
        mem2_o.mem_addr = mem_vaddr;
        mem2_o.inv_i = ex_i.inv_i;

        mem2_o.difftest_mem_info = difftest_mem_info;
        mem2_o.difftest_mem_info.store_data = dcache_rreq_o.data;
        if (mem_access_valid) begin  // if tlb miss,then do nothing
            case (aluop_i)
                `EXE_LL_OP: begin
                    mem2_o.LLbit_we = 1'b1;
                    mem2_o.LLbit_value = 1'b1;
                end
                `EXE_SC_OP: begin
                    if (LLbit_i == 1'b1) begin
                        mem2_o.LLbit_we = 1'b1;
                        mem2_o.LLbit_value = 1'b0;
                        mem2_o.wreg = 1;
                        mem2_o.difftest_mem_info.store_data = reg2_i;
                        mem2_o.wdata = 32'b1;
                    end else begin
                        mem2_o.wreg = 1;
                        mem2_o.difftest_mem_info.store_data = 0;
                        mem2_o.wdata = 32'b0;
                        mem2_o.instr_info.special_info.mem_store = 0;
                    end
                end
                default: begin
                end
            endcase
        end
    end


    always_ff @(posedge clk) begin
        if (rst) mem2_o_buffer <= 0;
        else if (flush | clear) mem2_o_buffer <= 0;
        else if (advance) mem2_o_buffer <= mem2_o;
    end
`ifdef SIMU
    // DEBUG
    logic [`InstAddrBus] debug_pc_i;
    assign debug_pc_i = ex_i.instr_info.pc;
    logic [`RegBus] debug_wdata_o;
    assign debug_wdata_o = mem2_o.wdata;
    logic debug_instr_valid;
    assign debug_instr_valid = ex_i.instr_info.valid;
    logic [`RegBus] debug_cache_data;
    assign debug_cache_data = dcache_rreq_o.data;
`endif
endmodule
