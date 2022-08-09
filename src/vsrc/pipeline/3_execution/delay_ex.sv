`include "core_types.sv"
`include "core_config.sv"

module delay_ex
    import core_types::*;
    import core_config::*;
(
    input logic rst,

    input logic [`RegBus] inst_pc_i,
    input logic [`AluOpBus] aluop_i,
    input logic [`AluSelBus] alusel_i,
    input logic [`RegBus] oprand1,
    input logic [`RegBus] oprand2,
    input logic [`RegBus] imm,

    output logic [`RegBus] wdata
);

    logic [`RegBus] logicout;
    logic [`RegBus] shiftout;

    alu u_alu (
        .rst(rst),

        .inst_pc_i(inst_pc_i),
        .aluop(aluop_i),
        .oprand1(oprand1),
        .oprand2(oprand2),
        .imm(imm),

        .logicout(logicout),
        .shiftout(shiftout),
        .branch_flag(branch_flag),
        .branch_target_address(jump_target_address)
    );


    always_comb begin
        wdata = 0;
        case (alusel_i)
            `EXE_RES_LOGIC: begin
                wdata = logicout;
            end
            `EXE_RES_SHIFT: begin
                wdata = shiftout;
            end
            default: begin

            end
        endcase
    end
endmodule
