`timescale 1ns / 1ns

`include "pipeline_defines.sv"

module mem (
    input logic rst,

    input ex_mem_struct signal_i,

    output mem_wb_struct signal_o,

    output mem_axi_struct signal_axi_o,

    // -> Ctrl
    output stallreq,

    // <- AXI Controller
    input logic axi_busy_i,
    input logic [`RegBus] mem_data_i,

    input logic LLbit_i,
    input logic wb_LLbit_we_i,
    input logic wb_LLbit_value_i,

    //from csr 
    input csr_to_mem_struct csr_mem_signal,
    input logic disable_cache,

    output mem_dispatch_struct mem_data_forward,

    //to addr trans 
    output logic data_addr_trans_en,
    output logic dmw0_en,
    output logic dmw1_en,
    output logic cacop_op_mode_di,

    //tlb 
    input tlb_to_mem_struct tlb_mem_signal,

    output reg LLbit_we_o,
    output reg LLbit_value_o

);

    reg LLbit;
    logic access_mem;
    logic mem_store_op;
    logic mem_load_op;
    logic excp_adem;
    logic pg_mode;
    logic da_mode;
    logic excp_tlbr;
    logic excp_pil;
    logic excp_pis;
    logic excp_pme;
    logic excp_ppi;

    logic [`InstAddrBus] debug_pc_i;
    assign debug_pc_i = signal_i.instr_info.pc;

    logic [`AluOpBus] aluop_i;
    assign aluop_i = signal_i.aluop;

    logic [`RegBus] mem_addr, reg2_i;
    assign mem_addr = signal_i.mem_addr;
    assign reg2_i   = signal_i.reg2;

    logic excp_i;
    logic [9:0] excp_num_i;
    assign excp_i = signal_i.excp;
    assign excp_num_i = signal_i.excp_num;

    assign access_mem = mem_load_op || mem_store_op;

    assign stallreq = axi_busy_i & (mem_load_op | mem_store_op);
    assign mem_load_op = aluop_i == `EXE_LD_B_OP || aluop_i == `EXE_LD_BU_OP || aluop_i == `EXE_LD_H_OP || aluop_i == `EXE_LD_HU_OP ||
                       aluop_i == `EXE_LD_W_OP || aluop_i == `EXE_LL_OP;

    assign mem_store_op = aluop_i == `EXE_ST_B_OP || aluop_i == `EXE_ST_H_OP || aluop_i == `EXE_ST_W_OP || aluop_i == `EXE_SC_OP;

    //difftest
    assign signal_o.inst_ld_en = {
        2'b0,
        aluop_i == `EXE_LL_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_W_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_HU_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_H_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_BU_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_LD_B_OP ? 1'b1 : 1'b0
    };

    assign signal_o.inst_st_en = {
        4'b0,
        aluop_i == `EXE_SC_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_ST_W_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_ST_H_OP ? 1'b1 : 1'b0,
        aluop_i == `EXE_ST_B_OP ? 1'b1 : 1'b0
    };

    assign signal_o.load_addr = mem_load_op ? mem_addr : 0;
    assign signal_o.store_addr = mem_store_op ? mem_addr : 0;
    assign signal_o.store_data = signal_axi_o.data;

    //addr dmw trans
    assign dmw0_en = ((csr_mem_signal.csr_dmw0[`PLV0] && csr_mem_signal.csr_plv == 2'd0) || (csr_mem_signal.csr_dmw0[`PLV3] && csr_mem_signal.csr_plv == 2'd3)) && (signal_i.wdata[31:29] == csr_mem_signal.csr_dmw0[`VSEG]);
    assign dmw1_en = ((csr_mem_signal.csr_dmw1[`PLV0] && csr_mem_signal.csr_plv == 2'd0) || (csr_mem_signal.csr_dmw1[`PLV3] && csr_mem_signal.csr_plv == 2'd3)) && (signal_i.wdata[31:29] == csr_mem_signal.csr_dmw1[`VSEG]);

    assign pg_mode = !csr_mem_signal.csr_da && csr_mem_signal.csr_pg;
    assign da_mode = csr_mem_signal.csr_da && !csr_mem_signal.csr_pg;

    assign data_addr_trans_en = pg_mode && !dmw0_en && !dmw1_en && !cacop_op_mode_di;

    assign mem_data_forward = {signal_o.wreg, signal_o.waddr, signal_o.wdata};

    assign excp_tlbr = access_mem && !tlb_mem_signal.data_tlb_found && data_addr_trans_en;
    assign excp_pil  = mem_load_op  && !tlb_mem_signal.data_tlb_v && data_addr_trans_en;  //cache will generate pil exception??
    assign excp_pis = mem_store_op && !tlb_mem_signal.data_tlb_v && data_addr_trans_en;
    assign excp_ppi = access_mem && tlb_mem_signal.data_tlb_v && (csr_mem_signal.csr_plv > tlb_mem_signal.data_tlb_plv) && data_addr_trans_en;
    assign excp_pme  = mem_store_op && tlb_mem_signal.data_tlb_v && (csr_mem_signal.csr_plv <= tlb_mem_signal.data_tlb_plv) && !tlb_mem_signal.data_tlb_d && data_addr_trans_en;

    assign signal_o.excp = excp_tlbr || excp_pil || excp_pis || excp_ppi || excp_pme || excp_adem || excp_i;
    assign signal_o.excp_num = {
        excp_pil, excp_pis, excp_ppi, excp_pme, excp_tlbr, excp_adem, excp_num_i
    };
    assign signal_o.refetch = signal_i.refetch;

    always @(*) begin
        if (rst == `RstEnable) LLbit = 1'b0;
        else begin
            if (wb_LLbit_we_i == 1'b1) LLbit = wb_LLbit_value_i;
            else LLbit = LLbit_i;
        end
    end

    always @(*) begin
        if (rst == `RstEnable) begin
            signal_o = 0;
            signal_axi_o = 0;
            LLbit_we_o = 1'b0;
            LLbit_value_o = 1'b0;
            signal_o.instr_info.pc = `ZeroWord;
            signal_axi_o = 0;
        end else begin
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
            case (aluop_i)
                `EXE_LD_B_OP: begin
                    signal_axi_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    case (mem_addr[1:0])
                        2'b00: begin
                            signal_o.wdata   = {{24{mem_data_i[31]}}, mem_data_i[31:24]};
                            signal_axi_o.sel = 4'b1000;
                        end
                        2'b01: begin
                            signal_o.wdata   = {{24{mem_data_i[23]}}, mem_data_i[23:16]};
                            signal_axi_o.sel = 4'b0100;
                        end
                        2'b10: begin
                            signal_o.wdata   = {{24{mem_data_i[15]}}, mem_data_i[15:8]};
                            signal_axi_o.sel = 4'b0010;
                        end
                        2'b11: begin
                            signal_o.wdata   = {{24{mem_data_i[7]}}, mem_data_i[7:0]};
                            signal_axi_o.sel = 4'b0001;
                        end
                        default: begin
                            signal_o.wdata = `ZeroWord;
                        end
                    endcase
                end
                `EXE_LD_H_OP: begin
                    signal_axi_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    case (mem_addr[1:0])
                        2'b00: begin
                            signal_o.wdata   = {{16{mem_data_i[31]}}, mem_data_i[31:16]};
                            signal_axi_o.sel = 4'b1100;
                        end

                        2'b10: begin
                            signal_o.wdata   = {{16{mem_data_i[15]}}, mem_data_i[15:0]};
                            signal_axi_o.sel = 4'b0011;
                        end

                        default: begin
                            signal_o.wdata = `ZeroWord;
                        end
                    endcase
                end
                `EXE_LD_W_OP: begin
                    signal_axi_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    signal_axi_o.sel = 4'b1111;
                    signal_o.wdata = mem_data_i;
                end
                `EXE_LD_BU_OP: begin
                    signal_axi_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    case (mem_addr[1:0])
                        2'b00: begin
                            signal_o.wdata   = {{24{1'b0}}, mem_data_i[31:24]};
                            signal_axi_o.sel = 4'b1000;
                        end
                        2'b01: begin
                            signal_o.wdata   = {{24{1'b0}}, mem_data_i[23:16]};
                            signal_axi_o.sel = 4'b0100;
                        end
                        2'b10: begin
                            signal_o.wdata   = {{24{1'b0}}, mem_data_i[15:8]};
                            signal_axi_o.sel = 4'b0010;
                        end
                        2'b11: begin
                            signal_o.wdata   = {{24{1'b0}}, mem_data_i[7:0]};
                            signal_axi_o.sel = 4'b0001;
                        end
                        default: begin
                            signal_o.wdata = `ZeroWord;
                        end
                    endcase
                end
                `EXE_LD_HU_OP: begin
                    signal_axi_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    case (mem_addr[1:0])
                        2'b00: begin
                            signal_o.wdata   = {{16{1'b0}}, mem_data_i[31:16]};
                            signal_axi_o.sel = 4'b1100;
                        end
                        2'b10: begin
                            signal_o.wdata   = {{16{1'b0}}, mem_data_i[15:0]};
                            signal_axi_o.sel = 4'b0011;
                        end
                        default: begin
                            signal_o.wdata = `ZeroWord;
                        end
                    endcase
                end
                `EXE_ST_B_OP: begin
                    signal_axi_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.we = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    signal_axi_o.data = {reg2_i[7:0], reg2_i[7:0], reg2_i[7:0], reg2_i[7:0]};
                    case (mem_addr[1:0])
                        2'b00: begin
                            signal_axi_o.sel = 4'b1000;
                        end
                        2'b01: begin
                            signal_axi_o.sel = 4'b0100;
                        end
                        2'b10: begin
                            signal_axi_o.sel = 4'b0010;
                        end
                        2'b11: begin
                            signal_axi_o.sel = 4'b0001;
                        end
                        default: begin
                            signal_axi_o.sel = 4'b0000;
                        end
                    endcase
                end
                `EXE_ST_H_OP: begin
                    signal_axi_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.we = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    signal_axi_o.data = {reg2_i[15:0], reg2_i[15:0]};
                    case (mem_addr[1:0])
                        2'b00: begin
                            signal_axi_o.sel = 4'b1100;
                        end
                        2'b10: begin
                            signal_axi_o.sel = 4'b0011;
                        end
                        default: begin
                            signal_axi_o.sel = 4'b0000;
                        end
                    endcase
                end
                `EXE_ST_W_OP: begin
                    signal_axi_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.we = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    signal_axi_o.data = reg2_i;
                    signal_axi_o.sel = 4'b1111;
                end
                `EXE_LL_OP: begin
                    signal_axi_o.addr = mem_addr;
                    signal_o.wreg = `WriteDisable;
                    signal_axi_o.ce = `ChipEnable;
                    signal_axi_o.sel = 4'b1111;
                    signal_o.wdata = mem_data_i;
                    LLbit_we_o = 1'b1;
                    LLbit_value_o = 1'b1;
                end
                `EXE_SC_OP: begin
                    if (LLbit == 1'b1) begin
                        signal_axi_o.addr = mem_addr;
                        signal_axi_o.we = `WriteEnable;
                        signal_o.wreg = `WriteEnable;
                        signal_axi_o.ce = `ChipEnable;
                        signal_axi_o.data = reg2_i;
                        signal_axi_o.sel = 4'b1111;
                        LLbit_we_o = 1'b1;
                        LLbit_value_o = 1'b0;
                        signal_o.wdata = 32'b1;
                    end else begin
                        signal_o.wdata = 32'b0;
                    end
                end
                default: begin
                    // Reset AXI signals, IMPORTANT!
                    signal_axi_o = 0;
                end
            endcase
        end
    end

endmodule
