`include "../../defines.v"

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

    output reg[`RegAddrBus] wd_o,
    output reg wreg_o,
    output reg[`RegBus] wdata_o,
    output reg inst_valid_o,
    output reg[`InstAddrBus] inst_pc_o
);
    
reg[`RegBus] logicout;
reg[`RegBus] shiftout;
reg[`RegBus] moveout;

always @(*) begin
    if(rst == `RstEnable)begin
        logicout = `ZeroWord;
    end else begin
        inst_pc_o = inst_pc_i;
        inst_valid_o = inst_valid_i;
        case (aluop_i)
            `EXE_OR_OP:begin
                logicout = reg1_i | reg2_i;
            end 
            `EXE_AND_OP:begin
                logicout = reg1_i & reg2_i;
            end
            `EXE_XOR_OP:begin
                logicout = reg1_i ^ reg2_i;
            end
            `EXE_NOR_OP:begin
                logicout = ~( reg1_i | reg2_i);
            end
            default:begin
            end
        endcase
    end
end

always @(*) begin
    if(rst == `RstEnable)begin
        shiftout = `ZeroWord;
    end else begin
        inst_pc_o = inst_pc_i;
        inst_valid_o = inst_valid_i;
        case (aluop_i)
            `EXE_SLL_OP:begin
                shiftout = reg1_i << reg2_i[4:0];
            end 
            `EXE_SRL_OP:begin
                shiftout = reg1_i >> reg2_i[4:0];
            end
            `EXE_SRA_OP:begin
                shiftout = ({32{reg1_i[31]}} << (6'd32-{1'b0,reg2_i[4:0]})) | reg1_i >> reg2_i[4:0];
            end
            default: begin
            end
        endcase
    end
end

always @(*) begin
    if(rst == `RstEnable)begin
        moveout = `ZeroWord;
    end else begin
        inst_pc_o = inst_pc_i;
        inst_valid_o = inst_valid_i;
        case (aluop_i)
            `EXE_LUI_OP:begin
                moveout = reg1_i;
            end
            default: begin
            end
        endcase
    end
end

always @(*) begin
    wd_o = wd_i;
    wreg_o = wreg_i;
    case (alusel_i)
        `EXE_RES_LOGIC: begin
            wdata_o = logicout;
        end
        `EXE_RES_SHIFT:begin
            wdata_o = shiftout;
        end
        `EXE_RES_MOVE:begin
            wdata_o = moveout;
        end
        default: begin
            wdata_o = `ZeroWord;
        end
    endcase
end

endmodule