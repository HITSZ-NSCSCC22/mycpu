`timescale 1ns / 1ns

`include "pipeline_defines.sv"

module mem (
    input logic rst,

    input ex_mem_struct signal_i,

    output mem_wb_struct signal_o,

    output mem_axi_struct signal_axi_o,


    input logic [`RegBus] mem_data_i,

    input logic LLbit_i,
    input logic wb_LLbit_we_i,
    input logic wb_LLbit_value_i,

    input logic excp_i,
    input logic [9:0] excp_num_i,

    //from csr 
    input logic csr_pg,
    input logic csr_da,
    input logic [31:0] csr_dmw0,
    input logic [31:0] csr_dmw1,
    input logic [1:0] csr_plv,
    input logic [1:0] csr_datf,
    input logic disable_cache,

    //to addr trans 
    output logic data_addr_trans_en,
    output logic dmw0_en,
    output logic dmw1_en,
    output logic cacop_op_mode_di,

    //tlb 
    input logic data_tlb_found,
    input logic [4:0] data_tlb_index,
    input logic data_tlb_v,
    input logic data_tlb_d,
    input logic [1:0] data_tlb_mat,
    input logic [1:0] data_tlb_plv,

    output reg LLbit_we_o,
    output reg LLbit_value_o,

    output logic excp_o,
    output logic [15:0] excp_num_o
);

    reg   LLbit;
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

    assign access_mem = mem_load_op || mem_store_op;

    assign mem_load_op = signal_i.aluop == `EXE_LD_B_OP || signal_i.aluop == `EXE_LD_BU_OP || signal_i.aluop == `EXE_LD_H_OP || signal_i.aluop == `EXE_LD_HU_OP ||
                       signal_i.aluop == `EXE_LD_W_OP || signal_i.aluop == `EXE_LL_OP;

    assign mem_store_op = signal_i.aluop == `EXE_ST_B_OP || signal_i.aluop == `EXE_ST_H_OP || signal_i.aluop == `EXE_ST_W_OP || signal_i.aluop == `EXE_SC_OP;


    //addr dmw trans
    assign dmw0_en = ((csr_dmw0[`PLV0] && csr_plv == 2'd0) || (csr_dmw0[`PLV3] && csr_plv == 2'd3)) && (signal_i.wdata[31:29] == csr_dmw0[`VSEG]);
    assign dmw1_en = ((csr_dmw1[`PLV0] && csr_plv == 2'd0) || (csr_dmw1[`PLV3] && csr_plv == 2'd3)) && (signal_i.wdata[31:29] == csr_dmw1[`VSEG]);

    assign pg_mode = !csr_da && csr_pg;
    assign da_mode = csr_da && !csr_pg;

    assign data_addr_trans_en = pg_mode && !dmw0_en && !dmw1_en && !cacop_op_mode_di;

    assign excp_tlbr = access_mem && !data_tlb_found && data_addr_trans_en;
    assign excp_pil  = mem_load_op  && !data_tlb_v && data_addr_trans_en;  //cache will generate pil exception??
    assign excp_pis = mem_store_op && !data_tlb_v && data_addr_trans_en;
    assign excp_ppi = access_mem && data_tlb_v && (csr_plv > data_tlb_plv) && data_addr_trans_en;
    assign excp_pme  = mem_store_op && data_tlb_v && (csr_plv <= data_tlb_plv) && !data_tlb_d && data_addr_trans_en;

    assign excp_o = excp_tlbr || excp_pil || excp_pis || excp_ppi || excp_pme || excp_adem || excp_i;
    assign excp_num_o = {excp_pil, excp_pis, excp_ppi, excp_pme, excp_tlbr, excp_adem, excp_num_i};

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
        end else begin
            LLbit_we_o = 1'b0;
            LLbit_value_o = 1'b0;
            // FIXME: information should be passed to next stage
            // currently not carefully designed
            signal_o.instr_info = signal_i.instr_info;
            signal_o.wreg = signal_i.wreg;
            signal_o.waddr = signal_i.waddr;
            signal_o.wdata = signal_i.wdata;
            signal_o.aluop = signal_i.aluop;
            signal_o.csr_signal = signal_i.csr_signal;
            case (signal_i.aluop)
                `EXE_LD_B_OP: begin
                    signal_axi_o.addr = signal_i.mem_addr;
                    signal_o.wreg = `WriteDisable;
                    signal_axi_o.ce = `ChipEnable;
                    case (signal_i.mem_addr[1:0])
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
                    signal_axi_o.addr = signal_i.mem_addr;
                    signal_o.wreg = `WriteDisable;
                    signal_axi_o.ce = `ChipEnable;
                    case (signal_i.mem_addr[1:0])
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
                    signal_axi_o.addr = signal_i.mem_addr;
                    signal_o.wreg = `WriteDisable;
                    signal_axi_o.ce = `ChipEnable;
                    signal_axi_o.sel = 4'b1111;
                    signal_o.wdata = mem_data_i;
                end
                `EXE_LD_BU_OP: begin
                    signal_axi_o.addr = signal_i.mem_addr;
                    signal_o.wreg = `WriteDisable;
                    signal_axi_o.ce = `ChipEnable;
                    case (signal_i.mem_addr[1:0])
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
                    signal_axi_o.addr = signal_i.mem_addr;
                    signal_o.wreg = `WriteDisable;
                    signal_axi_o.ce = `ChipEnable;
                    case (signal_i.mem_addr[1:0])
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
                    signal_axi_o.addr = signal_i.mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    signal_axi_o.data = {
                        signal_i.reg2[7:0],
                        signal_i.reg2[7:0],
                        signal_i.reg2[7:0],
                        signal_i.reg2[7:0]
                    };
                    case (signal_i.mem_addr[1:0])
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
                    signal_axi_o.addr = signal_i.mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    signal_axi_o.data = {signal_i.reg2[15:0], signal_i.reg2[15:0]};
                    case (signal_i.mem_addr[1:0])
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
                    signal_axi_o.addr = signal_i.mem_addr;
                    signal_o.wreg = `WriteEnable;
                    signal_axi_o.ce = `ChipEnable;
                    signal_axi_o.data = signal_i.reg2;
                    signal_axi_o.sel = 4'b1111;
                end
                `EXE_LL_OP: begin
                    signal_axi_o.addr = signal_i.mem_addr;
                    signal_o.wreg = `WriteDisable;
                    signal_axi_o.ce = `ChipEnable;
                    signal_axi_o.sel = 4'b1111;
                    signal_o.wdata = mem_data_i;
                    LLbit_we_o = 1'b1;
                    LLbit_value_o = 1'b1;
                end
                `EXE_SC_OP: begin
                    if (LLbit == 1'b1) begin
                        signal_axi_o.addr = signal_i.mem_addr;
                        signal_o.wreg = `WriteEnable;
                        signal_axi_o.ce = `ChipEnable;
                        signal_axi_o.data = signal_i.reg2;
                        signal_axi_o.sel = 4'b1111;
                        LLbit_we_o = 1'b1;
                        LLbit_value_o = 1'b0;
                        signal_o.wdata = 32'b1;
                    end else begin
                        signal_o.wdata = 32'b0;
                    end
                end
                default: begin

                end
            endcase
        end
    end

endmodule
