`timescale 1ns/1ns

`include "../../defines.v"
`include "../../csr_defines.v"

module mem (
    input wire rst,

    input wire[`InstAddrBus] inst_pc_i,
    input wire[`RegAddrBus] wd_i,
    input wire wreg_i,
    input wire[`RegBus] wdata_i,
    input wire[`AluOpBus] aluop_i,
    input wire[`RegBus] mem_addr_i,
    input wire[`RegBus] reg2_i,

    input wire[`RegBus] mem_data_i,

    input wire LLbit_i,
    input wire wb_LLbit_we_i,
    input wire wb_LLbit_value_i,

    input wire[1:0] excepttype_i,
    input wire[`RegBus] current_inst_address_i,

    input wire mem_csr_we_i,
    input wire[13:0] mem_csr_addr_i,
    input wire[`RegBus] mem_csr_data_i,

    input wire excp_i,
    input wire [9:0] excp_num_i,

    //from csr 
    input wire csr_pg,
    input wire csr_da,
    input wire [31:0]csr_dmw0,
    input wire [31:0]csr_dmw1,
    input wire [1:0]csr_plv,
    input wire [1:0]csr_datf,
    input wire disable_cache,   

    //to addr trans 
    output wire data_addr_trans_en,   
    output wire dmw0_en,
    output wire dmw1_en,
    output wire cacop_op_mode_di,   

    //tlb 
    input wire data_tlb_found,
    input wire [4:0]data_tlb_index,
    input wire data_tlb_v,
    input wire data_tlb_d,
    input wire [1:0] data_tlb_mat,
    input wire [1:0] data_tlb_plv,

    output reg[`InstAddrBus] inst_pc_o,
    output reg[`RegAddrBus] wd_o,
    output reg wreg_o,
    output reg[`RegBus] wdata_o,
    output reg[`AluOpBus] aluop_o,

    output reg[`RegBus] mem_addr_o,
    output wire mem_we_o,
    output reg[3:0] mem_sel_o,
    output reg[`RegBus] mem_data_o,
    output reg mem_ce_o,

    output reg LLbit_we_o,
    output reg LLbit_value_o,

    output wire[1:0] excepttype_o,
    output wire[`RegBus] current_inst_address_o,

    output wire mem_csr_we_o,
    output wire[13:0] mem_csr_addr_o,
    output wire[`RegBus] mem_csr_data_o,

    output wire excp_o,
    output wire[15:0] excp_num_o
  );

  reg mem_we;
  reg LLbit;
  wire access_mem;
  wire mem_store_op;
  wire mem_load_op;
  wire excp_adem;
  wire pg_mode;
  wire da_mode;
  wire excp_tlbr;
  wire excp_pil;
  wire excp_pis;
  wire excp_pme;
  wire excp_ppi;

  assign access_mem = mem_load_op || mem_store_op;

  assign mem_load_op = aluop_i == `EXE_LD_B_OP || aluop_i == `EXE_LD_BU_OP || aluop_i == `EXE_LD_H_OP || aluop_i == `EXE_LD_HU_OP ||
                       aluop_i == `EXE_LD_W_OP || aluop_i == `EXE_LL_OP;
                    
  assign mem_store_op = aluop_i == `EXE_ST_B_OP || aluop_i == `EXE_ST_H_OP || aluop_i == `EXE_ST_W_OP || aluop_i == `EXE_SC_OP;

  assign mem_we_o = mem_we & (~(|excepttype_i));

  assign excepttype_o = excepttype_i;
  assign current_inst_address_o = current_inst_address_i;

  assign mem_csr_we_o = mem_csr_we_i;
  assign mem_csr_addr_o = mem_csr_we_o;
  assign mem_csr_data_o = mem_csr_data_i;

  //addr dmw trans
  assign dmw0_en = ((csr_dmw0[`PLV0] && csr_plv == 2'd0) || (csr_dmw0[`PLV3] && csr_plv == 2'd3)) && (wdata_i[31:29] == csr_dmw0[`VSEG]);
  assign dmw1_en = ((csr_dmw1[`PLV0] && csr_plv == 2'd0) || (csr_dmw1[`PLV3] && csr_plv == 2'd3)) && (wdata_i[31:29] == csr_dmw1[`VSEG]);

  assign pg_mode = !csr_da && csr_pg;
  assign da_mode =  csr_da && !csr_pg;

  assign data_addr_trans_en = pg_mode && !dmw0_en && !dmw1_en && !cacop_op_mode_di;

  assign excp_tlbr = access_mem  && !data_tlb_found && data_addr_trans_en;
  assign excp_pil  = mem_load_op  && !data_tlb_v && data_addr_trans_en;  //cache will generate pil exception??
  assign excp_pis  = mem_store_op && !data_tlb_v && data_addr_trans_en;
  assign excp_ppi  = access_mem && data_tlb_v && (csr_plv > data_tlb_plv) && data_addr_trans_en;
  assign excp_pme  = mem_store_op && data_tlb_v && (csr_plv <= data_tlb_plv) && !data_tlb_d && data_addr_trans_en;

  assign excp_o = excp_tlbr || excp_pil || excp_pis || excp_ppi || excp_pme || excp_adem || excp_i;
  assign excp_num_o = {excp_pil, excp_pis, excp_ppi, excp_pme, excp_tlbr, excp_adem, excp_num_i};

  always @(*)
    begin
      if(rst == `RstEnable)
        LLbit = 1'b0;
      else
        begin
          if(wb_LLbit_we_i == 1'b1)
            LLbit = wb_LLbit_value_i;
          else
            LLbit = LLbit_i;
        end
    end

  always @ (*)
    begin
      if (rst == `RstEnable)
        begin
          wd_o  = `NOPRegAddr;
          wreg_o = `WriteDisable;
          wdata_o = `ZeroWord;
          mem_addr_o = `ZeroWord;
          mem_we = `WriteDisable;
          mem_sel_o = 4'b0000;
          mem_data_o = `ZeroWord;
          mem_ce_o = `ChipDisable;
          LLbit_we_o = 1'b0;
          LLbit_value_o = 1'b0;
          inst_pc_o = `ZeroWord;
        end
      else
        begin
          wd_o    = wd_i;
          wreg_o  = wreg_i;
          wdata_o = wdata_i;
          mem_addr_o = `ZeroWord;
          mem_we = `WriteDisable;
          mem_ce_o = `ChipDisable;
          mem_sel_o = 4'b1111;
          LLbit_we_o = 1'b0;
          LLbit_value_o = 1'b0;
          inst_pc_o = inst_pc_i;
          case (aluop_i)
            `EXE_LD_B_OP:
              begin
                mem_addr_o = mem_addr_i;
                mem_we = `WriteDisable;
                mem_ce_o = `ChipEnable;
                case(mem_addr_i[1:0])
                  2'b00:
                    begin
                      wdata_o = {{24{mem_data_i[31]}},mem_data_i[31:24]};
                      mem_sel_o = 4'b1000;
                    end
                  2'b01:
                    begin
                      wdata_o = {{24{mem_data_i[23]}},mem_data_i[23:16]};
                      mem_sel_o = 4'b0100;
                    end
                  2'b10:
                    begin
                      wdata_o = {{24{mem_data_i[15]}},mem_data_i[15:8]};
                      mem_sel_o = 4'b0010;
                    end
                  2'b11:
                    begin
                      wdata_o = {{24{mem_data_i[7]}},mem_data_i[7:0]};
                      mem_sel_o = 4'b0001;
                    end
                  default:
                    begin
                      wdata_o = `ZeroWord;
                    end
                endcase
              end
            `EXE_LD_H_OP:
              begin
                mem_addr_o = mem_addr_i;
                mem_we = `WriteDisable;
                mem_ce_o = `ChipEnable;
                case(mem_addr_i[1:0])
                  2'b00:
                    begin
                      wdata_o = {{16{mem_data_i[31]}},mem_data_i[31:16]};
                      mem_sel_o = 4'b1100;
                    end

                  2'b10:
                    begin
                      wdata_o = {{16{mem_data_i[15]}},mem_data_i[15:0]};
                      mem_sel_o = 4'b0011;
                    end

                  default:
                    begin
                      wdata_o = `ZeroWord;
                    end
                endcase
              end
            `EXE_LD_W_OP:
              begin
                mem_addr_o = mem_addr_i;
                mem_we = `WriteDisable;
                mem_ce_o = `ChipEnable;
                mem_sel_o = 4'b1111;
                wdata_o = mem_data_i;
              end
            `EXE_LD_BU_OP:
              begin
                mem_addr_o = mem_addr_i;
                mem_we = `WriteDisable;
                mem_ce_o = `ChipEnable;
                case(mem_addr_i[1:0])
                  2'b00:
                    begin
                      wdata_o = {{24{1'b0}},mem_data_i[31:24]};
                      mem_sel_o = 4'b1000;
                    end
                  2'b01:
                    begin
                      wdata_o = {{24{1'b0}},mem_data_i[23:16]};
                      mem_sel_o = 4'b0100;
                    end
                  2'b10:
                    begin
                      wdata_o = {{24{1'b0}},mem_data_i[15:8]};
                      mem_sel_o = 4'b0010;
                    end
                  2'b11:
                    begin
                      wdata_o = {{24{1'b0}},mem_data_i[7:0]};
                      mem_sel_o = 4'b0001;
                    end
                  default:
                    begin
                      wdata_o = `ZeroWord;
                    end
                endcase
              end
            `EXE_LD_HU_OP:
              begin
                mem_addr_o = mem_addr_i;
                mem_we = `WriteDisable;
                mem_ce_o = `ChipEnable;
                case(mem_addr_i[1:0])
                  2'b00:
                    begin
                      wdata_o = {{16{1'b0}},mem_data_i[31:16]};
                      mem_sel_o = 4'b1100;
                    end
                  2'b10:
                    begin
                      wdata_o = {{16{1'b0}},mem_data_i[15:0]};
                      mem_sel_o = 4'b0011;
                    end
                  default:
                    begin
                      wdata_o = `ZeroWord;
                    end
                endcase
              end
            `EXE_ST_B_OP:
              begin
                mem_addr_o = mem_addr_i;
                mem_we = `WriteEnable;
                mem_ce_o = `ChipEnable;
                mem_data_o = {reg2_i[7:0],reg2_i[7:0],reg2_i[7:0],reg2_i[7:0]};
                case(mem_addr_i[1:0])
                  2'b00:
                    begin
                      mem_sel_o = 4'b1000;
                    end
                  2'b01:
                    begin
                      mem_sel_o = 4'b0100;
                    end
                  2'b10:
                    begin
                      mem_sel_o = 4'b0010;
                    end
                  2'b11:
                    begin
                      mem_sel_o = 4'b0001;
                    end
                  default:
                    begin
                      mem_sel_o = 4'b0000;
                    end
                endcase
              end
            `EXE_ST_H_OP:
              begin
                mem_addr_o = mem_addr_i;
                mem_we = `WriteEnable;
                mem_ce_o = `ChipEnable;
                mem_data_o = {reg2_i[15:0],reg2_i[15:0]};
                case(mem_addr_i[1:0])
                  2'b00:
                    begin
                      mem_sel_o = 4'b1100;
                    end
                  2'b10:
                    begin
                      mem_sel_o = 4'b0011;
                    end
                  default:
                    begin
                      mem_sel_o = 4'b0000;
                    end
                endcase
              end
            `EXE_ST_W_OP:
              begin
                mem_addr_o = mem_addr_i;
                mem_we = `WriteEnable;
                mem_ce_o = `ChipEnable;
                mem_data_o = reg2_i;
                mem_sel_o = 4'b1111;
              end
            `EXE_LL_OP:
              begin
                mem_addr_o = mem_addr_i;
                mem_we = `WriteDisable;
                mem_ce_o = `ChipEnable;
                mem_sel_o = 4'b1111;
                wdata_o = mem_data_i;
                LLbit_we_o = 1'b1;
                LLbit_value_o = 1'b1;
              end
            `EXE_SC_OP:
              begin
                if(LLbit == 1'b1)
                  begin
                    mem_addr_o = mem_addr_i;
                    mem_we = `WriteEnable;
                    mem_ce_o = `ChipEnable;
                    mem_data_o = reg2_i;
                    mem_sel_o = 4'b1111;
                    LLbit_we_o = 1'b1;
                    LLbit_value_o = 1'b0;
                    wdata_o = 32'b1;
                  end
                else
                  begin
                    wdata_o = 32'b0;
                  end
              end
            default:
              begin

              end
          endcase
        end
    end

endmodule
