`include "defines.sv"
`include "csr_defines.sv"
`include "core_types.sv"
`include "core_config.sv"

// id_dispatch is a sequential logic 
// merge all ID stage output to dispatch stage
//  ID ->                         -> EXE
//  ID -> id_dispatch -> dispatch -> EXE
// 

module id_dispatch
    import core_types::*;
    import core_config::*;
    import csr_defines::*;
(
    input logic clk,
    input logic rst,

    // Stall & flush
    // <-> Ctrl
    input logic stall,
    input logic flush,

    // <- ID stage
    input id_dispatch_struct [DECODE_WIDTH-1:0] id_i,
    output logic [DECODE_WIDTH-1:0] id_dispatch_accept_o,

    // <-> Dispatch stage
    input logic [DECODE_WIDTH-1:0] dispatch_issue_i,
    output id_dispatch_struct [DECODE_WIDTH-1:0] dispatch_o
);

    logic rst_n;

    logic [$clog2(DECODE_WIDTH):0] dispatch_issue_num;

    assign rst_n = ~rst;

    always_comb begin
        dispatch_issue_num = 0;
        for (integer i = 0; i < DECODE_WIDTH; i++) begin
            dispatch_issue_num = dispatch_issue_num + dispatch_issue_i[i];
        end
    end
    always_comb begin
        id_dispatch_accept_o = 0;
        for (integer i = 0; i < DECODE_WIDTH; i++) begin
            if (i < dispatch_issue_num) id_dispatch_accept_o[i] = id_i[i].instr_info.valid;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dispatch_o <= 0;
        end else if (flush) begin
            dispatch_o <= 0;
        end else if (stall) begin
            // Do nothing, hold output
        end else begin
            for (integer i = 0; i < DECODE_WIDTH; i++) begin
                if (i < DECODE_WIDTH - dispatch_issue_num)
                    dispatch_o[i] <= dispatch_o[dispatch_issue_num+i[$clog2(DECODE_WIDTH)-1:0]];
                else
                    dispatch_o[i] <= id_i[i[$clog2(
                        DECODE_WIDTH
                    )-1:0]-DECODE_WIDTH+dispatch_issue_num];
            end
        end
    end

    // DEBUG
    logic [ADDR_WIDTH-1:0] debug_pc0, debug_pc1;
    assign debug_pc0 = id_i[0].instr_info.pc;
    assign debug_pc1 = id_i[1].instr_info.pc;


endmodule
