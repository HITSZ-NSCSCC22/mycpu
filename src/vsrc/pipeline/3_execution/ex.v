`include "defines.v"

module ex (
    input wire rst,

    input wire[`AluOpBus] aluop_i,
    input wire[`AluSelBus] alusel_i,
    input wire[`RegBus] reg1_i,
    input wire[`RegBus] reg2_i,
    input wire[`RegAddrBus] wd_i,
    input wire wreg_i,
    input wire inst_valid_i,
    input wire[`InstAddrBus] inst_pc_i,
    input wire[`RegBus] inst_i,
    input wire[`RegBus] link_addr_i,
    input wire[1:0] excepttype_i,
    input wire[`RegBus] current_inst_address_i,

    output reg[`RegAddrBus] wd_o,
    output reg wreg_o,
    output reg[`RegBus] wdata_o,
    output reg inst_valid_o,
    output reg[`InstAddrBus] inst_pc_o,
    output wire[`AluOpBus] aluop_o,
    output wire[`RegBus] mem_addr_o,
    output wire[`RegBus] reg2_o,
    output wire[1:0] excepttype_o,
    output wire[`RegBus] current_inst_address_o,

    output wire stallreq
  );

  reg[`RegBus] logicout;
  reg[`RegBus] shiftout;
  reg[`RegBus] moveout;
  reg[`RegBus] arithout;

  assign aluop_o = aluop_i;
  assign mem_addr_o = reg1_i + {{20{inst_i[21]}},inst_i[21:10]};
  assign reg2_o = reg2_i;

  assign excepttype_o = excepttype_i;
  assign current_inst_address_o = current_inst_address_i;

  always @(*)
    begin
      if(rst == `RstEnable)
        begin
          logicout = `ZeroWord;
        end
      else
        begin
          inst_pc_o = inst_pc_i;
          inst_valid_o = inst_valid_i;
          case (aluop_i)
            `EXE_OR_OP:
              begin
                logicout = reg1_i | reg2_i;
              end
            `EXE_AND_OP:
              begin
                logicout = reg1_i & reg2_i;
              end
            `EXE_XOR_OP:
              begin
                logicout = reg1_i ^ reg2_i;
              end
            `EXE_NOR_OP:
              begin
                logicout = ~( reg1_i | reg2_i);
              end
            default:
              begin
              end
          endcase
        end
    end

  always @(*)
    begin
      if(rst == `RstEnable)
        begin
          shiftout = `ZeroWord;
        end
      else
        begin
          // inst_pc_o = inst_pc_i;
          // inst_valid_o = inst_valid_i;
          case (aluop_i)
            `EXE_SLL_OP:
              begin
                shiftout = reg1_i << reg2_i[4:0];
              end
            `EXE_SRL_OP:
              begin
                shiftout = reg1_i >> reg2_i[4:0];
              end
            `EXE_SRA_OP:
              begin
                shiftout = ({32{reg1_i[31]}} << (6'd32-{1'b0,reg2_i[4:0]})) | reg1_i >> reg2_i[4:0];
              end
            default:
              begin
              end
          endcase
        end
    end

  //比较模块
  wire reg1_lt_reg2;
  wire[`RegBus] reg2_i_mux;
  wire[`RegBus] reg1_i_mux;
  wire[`RegBus] result_compare;

  assign reg2_i_mux = (aluop_i == `EXE_SLT_OP) ? (~reg2_i)+1 : reg2_i;
  assign reg1_i_mux = (aluop_i == `EXE_SLT_OP) ? (~reg1_i)+1 : reg1_i;
  assign result_compare = reg1_i + reg2_i_mux;
  assign reg1_lt_reg2 = (reg1_i < reg2_i);

  //乘法模块

  wire[`RegBus] opdata1_mul;
  wire[`RegBus] opdata2_mul;
  wire[`DoubleRegBus] hilo_temp;
  reg[`DoubleRegBus]mulres;

  assign opdata1_mul = (((aluop_i == `EXE_MUL_OP) || (aluop_i == `EXE_MULH_OP))
                        && (reg1_i[31] == 1'b1)) ? (~reg1_i + 1) : reg1_i;

  assign opdata2_mul = (((aluop_i == `EXE_MUL_OP) || (aluop_i == `EXE_MULH_OP))
                        && (reg2_i[31] == 1'b1)) ? (~reg2_i + 1) : reg1_i;

  assign hilo_temp = opdata1_mul * opdata2_mul;

  always @(*)
    begin
      if(rst == `RstEnable)
        mulres = {`ZeroWord,`ZeroWord};
      else if((aluop_i == `EXE_MUL_OP) || (aluop_i == `EXE_MULH_OP))
        begin
          if(reg1_i[31] ^ reg2_i[31] == 1'b1)
            mulres = ~hilo_temp + 1;
          else
            mulres = hilo_temp;
        end
      else
        mulres = hilo_temp;
    end


  always @(*)
    begin
      if(rst == `RstEnable)
        begin
          arithout = `ZeroWord;
        end
      else
        begin
          //   inst_pc_o = inst_pc_i;
          //   inst_valid_o = inst_valid_i;
          case (aluop_i)
            `EXE_ADD_OP:
              arithout = reg1_i + reg2_i;
            `EXE_SUB_OP:
              arithout = reg1_i - reg2_i;
            `EXE_MUL_OP:
              arithout = mulres[31:0];
            `EXE_MULH_OP,`EXE_MULHU_OP:
              arithout = mulres[63:32];
            `EXE_DIV_OP:
              arithout = reg1_i / reg2_i;
            `EXE_MOD_OP:
              arithout = reg1_i % reg2_i;
            `EXE_SLT_OP,`EXE_SLTU_OP:
              arithout = {31'b0,reg1_lt_reg2};
            default:
              begin
              end
          endcase
        end
    end



  always @(*)
    begin
      if(rst == `RstEnable)
        begin
          moveout = `ZeroWord;
        end
      else
        begin
          //   inst_pc_o = inst_pc_i;
          //   inst_valid_o = inst_valid_i;
          case (aluop_i)
            `EXE_LUI_OP:
              begin
                moveout = reg2_i;
              end
            `EXE_PCADD_OP:
              begin
                moveout = reg2_i + inst_pc_o;
              end
            default:
              begin
              end
          endcase
        end
    end

  always @(*)
    begin
      wd_o = wd_i;
      wreg_o = wreg_i;
      case (alusel_i)
        `EXE_RES_LOGIC:
          begin
            wdata_o = logicout;
          end
        `EXE_RES_SHIFT:
          begin
            wdata_o = shiftout;
          end
        `EXE_RES_MOVE:
          begin
            wdata_o = moveout;
          end
        `EXE_RES_ARITH:
          begin
            wdata_o = arithout;
          end
        `EXE_RES_JUMP:
          begin
            wdata_o = link_addr_i;
          end
        default:
          begin
            wdata_o = `ZeroWord;
          end
      endcase
    end

endmodule
