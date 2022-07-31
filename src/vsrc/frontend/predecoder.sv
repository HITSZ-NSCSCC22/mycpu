`include "core_config.sv"
`include "defines.sv"



module predecoder
    import core_config::*;
(
    input logic [DATA_WIDTH-1:0] instr_i,

    output logic is_unconditional_o,
    output logic is_register_jump_o,
    output logic [ADDR_WIDTH-1:0] jump_target_address_o
);


    // imm26
    logic [25:0] imm_26;
    assign imm_26 = {instr_i[9:0], instr_i[25:10]};

    always_comb begin
        case (instr_i[31:26])
            `EXE_B, `EXE_BL: begin
                is_unconditional_o = 1;
                is_register_jump_o = 0;
                jump_target_address_o = {{4{imm_26[25]}}, imm_26, 2'b0};
            end
            `EXE_JIRL: begin
                is_unconditional_o = 1;
                is_register_jump_o = 1;
                jump_target_address_o = 0;
            end
            default: begin
                is_unconditional_o = 0;
                is_register_jump_o = 0;
                jump_target_address_o = 0;
            end
        endcase
    end

endmodule
