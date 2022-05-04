`include "instr_info.sv"

module instr_buffer #(
    parameter IF_WIDTH = 2,
    parameter ID_WIDTH = 2
) (
    input logic clk,
    input logic rst,

    // <-> Frontend
    input instr_buffer_info_t if_instr_i[IF_WIDTH],
    output logic frontend_stallreq_o,  // Require frontend to stop

    // <-> Backend
    input logic backend_stallreq_i,  // Backend is stalling
    input logic flush_i,  // Backend require flush, maybe branch miss
    output instr_buffer_info_t id_instr_o[ID_WIDTH]

);

endmodule
