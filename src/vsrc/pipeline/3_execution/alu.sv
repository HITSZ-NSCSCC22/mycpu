`include "core_types.sv"
`include "core_config.sv"

module alu
    import core_types::*;
    import core_config::*;
(

    input logic rst,

    input logic [  `RegBus] inst_pc_i,
    input logic [`AluOpBus] aluop,
    input logic [  `RegBus] oprand1,
    input logic [  `RegBus] oprand2,
    input logic [  `RegBus] imm,

    output logic [`RegBus] logicout,
    output logic [`RegBus] shiftout,
    output logic branch_flag,
    output logic [`RegBus] branch_target_address
);

    always @(*) begin
        if (rst == `RstEnable) begin
            logicout = `ZeroWord;
        end else begin
            case (aluop)
                `EXE_OR_OP: begin
                    logicout = oprand1 | oprand2;
                end
                `EXE_AND_OP: begin
                    logicout = oprand1 & oprand2;
                end
                `EXE_XOR_OP: begin
                    logicout = oprand1 ^ oprand2;
                end
                `EXE_NOR_OP: begin
                    logicout = ~(oprand1 | oprand2);
                end
                `EXE_ORN_OP: begin
                    logicout = oprand1 | ~(oprand2);
                end
                `EXE_ANDN_OP: begin
                    logicout = oprand1 & ~(oprand2);
                end
                default: begin
                    logicout = `ZeroWord;
                end
            endcase
        end
    end

    always @(*) begin
        if (rst == `RstEnable) begin
            shiftout = `ZeroWord;
        end else begin
            case (aluop)
                `EXE_SLL_OP: begin
                    shiftout = oprand1 << oprand2[4:0];
                end
                `EXE_SRL_OP: begin
                    shiftout = oprand1 >> oprand2[4:0];
                end
                `EXE_SRA_OP: begin
                    shiftout = ({32{oprand1[31]}} << (6'd32-{1'b0,oprand2[4:0]})) | oprand1 >> oprand2[4:0];
                end
                default: begin
                    shiftout = `ZeroWord;
                end
            endcase
        end
    end


    always @(*) begin
        if (rst == `RstEnable) begin
            branch_flag = 1'b0;
            branch_target_address = `ZeroWord;
        end else begin
            // Default is not branching
            branch_flag = 1'b0;
            branch_target_address = `ZeroWord;
            case (aluop)
                `EXE_B_OP, `EXE_BL_OP: begin
                    branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_JIRL_OP: begin
                    branch_flag = 1'b1;
                    branch_target_address = oprand1 + imm;
                end
                `EXE_BEQ_OP: begin
                    if (oprand1 == oprand2) branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_BNE_OP: begin
                    if (oprand1 != oprand2) branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_BLT_OP: begin
                    if ({~oprand1[31], oprand1[30:0]} < {~oprand2[31], oprand2[30:0]})
                        branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_BGE_OP: begin
                    if ({~oprand1[31], oprand1[30:0]} >= {~oprand2[31], oprand2[30:0]})
                        branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_BLTU_OP: begin
                    if (oprand1 < oprand2) branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_BGEU_OP: begin
                    if (oprand1 >= oprand2) branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                default: begin

                end
            endcase
        end
    end


endmodule
