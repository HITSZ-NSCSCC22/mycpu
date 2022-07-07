`include "core_types.sv"
`include "csr_defines.sv"
`include "tlb_types.sv"

module mem1
    import core_types::*;
    import csr_defines::*;
    import tlb_types::*;
(
    input logic clk,
    input logic rst,
    input logic stall,
    input logic flush,

    input ex_mem_struct signal_i,

    output mem1_mem2_struct signal_o_buffer,

    output mem_cache_struct signal_cache_o,

    // -> TLB
    input tlb_data_t tlb_mem_signal,

    input logic LLbit_i,
    input logic wb_LLbit_we_i,
    input logic wb_LLbit_value_i,

    // Data forward
    // -> Dispatch
    // -> EX
    output mem1_data_forward_t mem_data_forward_o,

    //if cache is working
    input cache_ack,

    output stallreq,

    input [1:0] csr_plv,


    output reg LLbit_we_o,
    output reg LLbit_value_o

);

    mem1_mem2_struct signal_o;

    reg LLbit;
    logic access_mem, mem_store_op, mem_load_op;
    logic cacop_en, icache_op_en;
    logic [4:0] cacop_op;
    assign cacop_en = signal_i.cacop_en;
    assign icache_op_en = signal_i.icache_op_en;
    assign cacop_op = signal_i.cacop_op;

    // DEBUG
    logic [`InstAddrBus] debug_pc_i;
    assign debug_pc_i = signal_i.instr_info.pc;
    logic [`RegBus] debug_wdata_o;
    assign debug_wdata_o = signal_o.wdata;
    logic debug_instr_valid;
    assign debug_instr_valid = signal_i.instr_info.valid;

    logic [`AluOpBus] aluop_i;
    assign aluop_i = signal_i.aluop;

    logic [`RegBus] mem_addr, reg2_i;
    assign mem_addr = {tlb_mem_signal.tag, tlb_mem_signal.index, tlb_mem_signal.offset};
    assign reg2_i   = signal_i.reg2;

    logic excp_i;
    logic [9:0] excp_num_i;
    assign excp_i = signal_i.excp;
    assign excp_num_i = signal_i.excp_num;

    assign access_mem = signal_cache_o.ce;

    // Anything can trigger stall and modify register is considerd a "load" instr
    assign mem_load_op = aluop_i == `EXE_LD_B_OP || aluop_i == `EXE_LD_BU_OP || aluop_i == `EXE_LD_H_OP || aluop_i == `EXE_LD_HU_OP ||
                       aluop_i == `EXE_LD_W_OP || aluop_i == `EXE_LL_OP || aluop_i == `EXE_SC_OP;

    assign mem_store_op = aluop_i == `EXE_ST_B_OP || aluop_i == `EXE_ST_H_OP || aluop_i == `EXE_ST_W_OP || aluop_i == `EXE_SC_OP;

    logic excp, excp_adem, excp_tlbr, excp_pil, excp_pis, excp_ppi, excp_pme;
    logic [15:0] excp_num;
    assign excp_adem = (access_mem || cacop_en) && signal_i.data_addr_trans_en && (csr_plv == 2'd3) && mem_addr[31];
    assign excp_tlbr = (access_mem || cacop_en) && !tlb_mem_signal.found && signal_i.data_addr_trans_en;
    assign excp_pil  = mem_load_op  && !tlb_mem_signal.tlb_v && signal_i.data_addr_trans_en;  //cache will generate pil exception??
    assign excp_pis = mem_store_op && !tlb_mem_signal.tlb_v && signal_i.data_addr_trans_en;
    assign excp_ppi = access_mem && tlb_mem_signal.tlb_v && (csr_plv > tlb_mem_signal.tlb_plv) && signal_i.data_addr_trans_en;
    assign excp_pme  = mem_store_op && tlb_mem_signal.tlb_v && (csr_plv <= tlb_mem_signal.tlb_plv) && !tlb_mem_signal.tlb_d && signal_i.data_addr_trans_en;
    assign excp = excp_tlbr || excp_pil || excp_pis || excp_ppi || excp_pme || excp_adem || excp_i;
    assign excp_num = {excp_pil, excp_pis, excp_ppi, excp_pme, excp_tlbr, excp_adem, excp_num_i};

    //difftest
    assign signal_o.inst_ld_en = access_mem ? {
        2'b0,
        aluop_i == `EXE_LL_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_W_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_HU_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_H_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_BU_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_B_OP ? 1'b1 : 1'b0
    } : 0;

    assign signal_o.inst_st_en = access_mem ? {
        4'b0,
        aluop_i == `EXE_SC_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_ST_W_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_ST_H_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_ST_B_OP ? 1'b1 : 1'b0
    } : 0;

    assign signal_o.load_addr = mem_load_op ? mem_addr : 0;
    assign signal_o.store_addr = mem_store_op ? mem_addr : 0;

    // Data forward
    assign mem_data_forward_o = {mem_load_op, signal_o.wreg, signal_o.waddr, signal_o.wdata};

    assign signal_o.excp = excp;
    assign signal_o.excp_num = excp_num;
    assign signal_o.refetch = signal_i.refetch;

    //if mem1 has a mem request and cache is working 
    //then wait until cache finish its work
    assign stallreq = cache_ack & access_mem;

    always @(*) begin
        if (rst == `RstEnable) LLbit = 1'b0;
        else begin
            if (wb_LLbit_we_i == 1'b1) LLbit = wb_LLbit_value_i;
            else LLbit = LLbit_i;
        end
    end

    always_comb begin
        LLbit_we_o = 1'b0;
        LLbit_value_o = 1'b0;
        // FIXME: information should be passed to next stage
        // currently not carefully designed
        signal_o.instr_info = signal_i.instr_info;
        signal_o.wreg = signal_i.wreg;
        signal_o.waddr = signal_i.waddr;
        signal_o.wdata = signal_i.wdata;
        signal_o.aluop = aluop_i;
        signal_o.csr_signal = signal_i.csr_signal;
        signal_o.inv_i = signal_i.inv_i;
        signal_o.mem_addr = mem_addr;
        signal_o.timer_64 = signal_i.timer_64;
        signal_cache_o = 0;
        signal_o.store_data = 0;
        signal_cache_o.rd_type = 0;
        signal_cache_o.wr_type = 0;
        signal_o.cacop_en = cacop_en;
        signal_o.icache_op_en = icache_op_en;
        signal_o.cacop_op = cacop_op;
        signal_o.tlb_signal = tlb_mem_signal;
        if (!excp & (!signal_i.data_addr_trans_en | tlb_mem_signal.found)) begin // if tlb miss,then do nothing
            case (aluop_i)
                `EXE_LD_B_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.sel = 4'b1111;
                    signal_cache_o.rd_type = 0;
                    case (mem_addr[1:0])
                        2'b11: begin
                            signal_cache_o.sel = 4'b1000;
                        end
                        2'b10: begin
                            signal_cache_o.sel = 4'b0100;
                        end
                        2'b01: begin
                            signal_cache_o.sel = 4'b0010;
                        end
                        2'b00: begin
                            signal_cache_o.sel = 4'b0001;
                        end
                        default: begin
                            signal_o.wdata = `ZeroWord;
                        end
                    endcase
                end
                `EXE_LD_H_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.rd_type = 3'b001;
                    case (mem_addr[1:0])
                        2'b10: begin
                            signal_cache_o.sel = 4'b1100;
                        end

                        2'b00: begin
                            signal_cache_o.sel = 4'b0011;
                        end

                        default: begin
                            signal_o.wdata = `ZeroWord;
                        end
                    endcase
                end
                `EXE_LD_W_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.sel = 4'b1111;
                    signal_cache_o.rd_type = 3'b010;
                end
                `EXE_LD_BU_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.rd_type = 3'b000;
                    case (mem_addr[1:0])
                        2'b11: begin
                            signal_cache_o.sel = 4'b1000;
                        end
                        2'b10: begin
                            signal_cache_o.sel = 4'b0100;
                        end
                        2'b01: begin
                            signal_cache_o.sel = 4'b0010;
                        end
                        2'b00: begin
                            signal_cache_o.sel = 4'b0001;
                        end
                        default: begin
                            signal_o.wdata = `ZeroWord;
                        end
                    endcase
                end
                `EXE_LD_HU_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.rd_type = 3'b001;
                    case (mem_addr[1:0])
                        2'b10: begin
                            signal_cache_o.sel = 4'b1100;
                        end
                        2'b00: begin
                            signal_cache_o.sel = 4'b0011;
                        end
                        default: begin
                            signal_o.wdata = `ZeroWord;
                        end
                    endcase
                end
                `EXE_ST_B_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.we = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.wr_type = 3'b000;
                    signal_cache_o.data = {reg2_i[7:0], reg2_i[7:0], reg2_i[7:0], reg2_i[7:0]};
                    case (mem_addr[1:0])
                        2'b11: begin
                            signal_cache_o.sel  = 4'b1000;
                            signal_o.store_data = {reg2_i[7:0], 24'b0};
                        end
                        2'b10: begin
                            signal_cache_o.sel  = 4'b0100;
                            signal_o.store_data = {8'b0, reg2_i[7:0], 16'b0};
                        end
                        2'b01: begin
                            signal_cache_o.sel  = 4'b0010;
                            signal_o.store_data = {16'b0, reg2_i[7:0], 8'b0};
                        end
                        2'b00: begin
                            signal_cache_o.sel  = 4'b0001;
                            signal_o.store_data = {24'b0, reg2_i[7:0]};
                        end
                    endcase
                end
                `EXE_ST_H_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.we = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.wr_type = 3'b001;
                    signal_cache_o.data = {reg2_i[15:0], reg2_i[15:0]};
                    case (mem_addr[1:0])
                        2'b10: begin
                            signal_cache_o.sel  = 4'b1100;
                            signal_o.store_data = {reg2_i[15:0], 16'b0};
                        end
                        2'b00: begin
                            signal_cache_o.sel  = 4'b0011;
                            signal_o.store_data = {16'b0, reg2_i[15:0]};
                        end
                        default: begin
                            signal_cache_o.sel = 4'b0000;
                        end
                    endcase
                end
                `EXE_ST_W_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.we = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.wr_type = 3'b010;
                    signal_cache_o.data = reg2_i;
                    signal_cache_o.sel = 4'b1111;
                    signal_o.store_data = reg2_i;
                end
                `EXE_LL_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.sel = 4'b1111;
                    LLbit_we_o = 1'b1;
                    LLbit_value_o = 1'b1;
                    signal_cache_o.rd_type = 3'b010;
                end
                `EXE_SC_OP: begin
                    if (LLbit == 1'b1) begin
                        signal_cache_o.addr = mem_addr;
                        signal_cache_o.we = `WriteEnable;
                        signal_cache_o.ce = `ChipEnable;
                        signal_cache_o.data = reg2_i;
                        signal_cache_o.sel = 4'b1111;
                        signal_cache_o.wr_type = 3'b010;
                        LLbit_we_o = 1'b1;
                        LLbit_value_o = 1'b0;
                        signal_o.wreg = `WriteEnable;
                        signal_o.store_data = reg2_i;
                        signal_o.wdata = 32'b1;
                    end else begin
                        signal_cache_o = 0;
                        signal_o.wreg = `WriteEnable;
                        signal_o.store_data = 0;
                        signal_o.wdata = 32'b0;
                        signal_cache_o.wr_type = 3'b000;
                    end
                end
                default: begin
                    // Reset AXI signals, IMPORTANT!
                    signal_cache_o = 0;
                end
            endcase
        end
    end


    always_ff @(posedge clk) begin
        if (rst) signal_o_buffer <= 0;
        else if (stall | flush) signal_o_buffer <= 0;
        else signal_o_buffer <= signal_o;
    end

endmodule
