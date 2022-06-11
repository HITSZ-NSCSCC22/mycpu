`include "core_types.sv"
`include "csr_defines.sv"

module mem
    import core_types::*;
    import csr_defines::*;
(
    input logic rst,

    input ex_mem_struct signal_i,

    output mem_wb_struct signal_o,

    output mem_cache_struct signal_cache_o,

    // -> Ctrl
    output logic stallreq,

    // <- cache
    input logic addr_ok,
    input logic data_ok,
    input logic [`RegBus] mem_data_i,

    output data_fetch,

    input logic LLbit_i,
    input logic wb_LLbit_we_i,
    input logic wb_LLbit_value_i,

    // Data forward
    // -> Dispatch
    // -> EX
    output mem_data_forward_t mem_data_forward_o,


    output reg LLbit_we_o,
    output reg LLbit_value_o

);

    logic [63:0] timer_test;
    assign timer_test = signal_i.timer_64;

    csr_write_signal csr_test;
    assign csr_test = signal_i.csr_signal;

    reg LLbit;
    logic access_mem;
    logic mem_store_op;
    logic mem_load_op;

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
    assign mem_addr = signal_i.mem_addr;
    assign reg2_i   = signal_i.reg2;

    logic excp_i;
    logic [9:0] excp_num_i;
    assign excp_i = signal_i.excp;
    assign excp_num_i = signal_i.excp_num;

    assign data_fetch = addr_ok | aluop_i == `EXE_TLBSRCH_OP;

    assign access_mem = mem_load_op || mem_store_op;

    assign stallreq = !data_ok & (mem_load_op | mem_store_op);
    assign mem_load_op = aluop_i == `EXE_LD_B_OP || aluop_i == `EXE_LD_BU_OP || aluop_i == `EXE_LD_H_OP || aluop_i == `EXE_LD_HU_OP ||
                       aluop_i == `EXE_LD_W_OP || aluop_i == `EXE_LL_OP || aluop_i == `EXE_SC_OP;

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

    // Data forward
    assign mem_data_forward_o = {mem_load_op, signal_o.wreg, signal_o.waddr, signal_o.wdata};

    assign signal_o.excp = excp_i;
    assign signal_o.excp_num = excp_num_i;
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
            signal_o.instr_info = 0;
            signal_o.wreg = 0;
            signal_o.wdata = 0;
            signal_o.waddr = 0;
            signal_o.csr_signal = 0;
            signal_o.aluop = 0;
            signal_o.inv_i = 0;
            signal_cache_o = 0;
            signal_o.store_data = 0;
            signal_o.mem_addr = 0;
            signal_o.timer_64 = 0;
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
            signal_o.inv_i = signal_i.inv_i;
            signal_o.mem_addr = mem_addr;
            signal_o.timer_64 = signal_i.timer_64;
            signal_cache_o = 0;
            signal_o.store_data = 0;
            case (aluop_i)
                `EXE_LD_B_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.sel = 4'b1111;
                    case (mem_addr[1:0])
                        2'b11: begin
                            signal_o.wdata = {{24{mem_data_i[31]}}, mem_data_i[31:24]};
                            signal_cache_o.sel = 4'b1000;
                        end
                        2'b10: begin
                            signal_o.wdata = {{24{mem_data_i[23]}}, mem_data_i[23:16]};
                            signal_cache_o.sel = 4'b0100;
                        end
                        2'b01: begin
                            signal_o.wdata = {{24{mem_data_i[15]}}, mem_data_i[15:8]};
                            signal_cache_o.sel = 4'b0010;
                        end
                        2'b00: begin
                            signal_o.wdata = {{24{mem_data_i[7]}}, mem_data_i[7:0]};
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
                    case (mem_addr[1:0])
                        2'b10: begin
                            signal_o.wdata = {{16{mem_data_i[31]}}, mem_data_i[31:16]};
                            signal_cache_o.sel = 4'b1100;
                        end

                        2'b00: begin
                            signal_o.wdata = {{16{mem_data_i[15]}}, mem_data_i[15:0]};
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
                    signal_o.wdata = mem_data_i;
                end
                `EXE_LD_BU_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    case (mem_addr[1:0])
                        2'b11: begin
                            signal_o.wdata = {{24{1'b0}}, mem_data_i[31:24]};
                            signal_cache_o.sel = 4'b1000;
                        end
                        2'b10: begin
                            signal_o.wdata = {{24{1'b0}}, mem_data_i[23:16]};
                            signal_cache_o.sel = 4'b0100;
                        end
                        2'b01: begin
                            signal_o.wdata = {{24{1'b0}}, mem_data_i[15:8]};
                            signal_cache_o.sel = 4'b0010;
                        end
                        2'b00: begin
                            signal_o.wdata = {{24{1'b0}}, mem_data_i[7:0]};
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
                    case (mem_addr[1:0])
                        2'b10: begin
                            signal_o.wdata = {{16{1'b0}}, mem_data_i[31:16]};
                            signal_cache_o.sel = 4'b1100;
                        end
                        2'b00: begin
                            signal_o.wdata = {{16{1'b0}}, mem_data_i[15:0]};
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
                    signal_cache_o.data = reg2_i;
                    signal_cache_o.sel = 4'b1111;
                    signal_o.store_data = reg2_i;
                end
                `EXE_LL_OP: begin
                    signal_cache_o.addr = mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.sel = 4'b1111;
                    signal_o.wdata = mem_data_i;
                    LLbit_we_o = 1'b1;
                    LLbit_value_o = 1'b1;
                end
                `EXE_SC_OP: begin
                    if (LLbit == 1'b1) begin
                        signal_cache_o.addr = mem_addr;
                        signal_cache_o.we = `WriteEnable;
                        signal_o.wreg = `WriteEnable;
                        signal_cache_o.ce = `ChipEnable;
                        signal_cache_o.data = reg2_i;
                        signal_o.store_data = reg2_i;
                        signal_cache_o.sel = 4'b1111;
                        LLbit_we_o = 1'b1;
                        LLbit_value_o = 1'b0;
                        signal_o.wdata = 32'b1;
                    end else begin
                        signal_o.wdata = 32'b0;
                    end
                end
                default: begin
                    // Reset AXI signals, IMPORTANT!
                    signal_cache_o = 0;
                end
            endcase
        end
    end

endmodule
