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

    // <-> Dispatch stage
    input logic [DECODE_WIDTH-1:0] dispatch_issue_i,
    output id_dispatch_struct [DECODE_WIDTH-1:0] dispatch_o
);

    logic rst_n;
    assign rst_n = ~rst;

    logic [$clog2(DECODE_WIDTH):0] dispatch_issue_num;
    always_comb begin
        dispatch_issue_num = 0;
        for (integer i = 0; i < DECODE_WIDTH; i++) begin
            dispatch_issue_num = dispatch_issue_num + dispatch_issue_i[i];
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
                    dispatch_o[i] <= dispatch_o[i+dispatch_issue_num];
                else dispatch_o[i] <= id_i[i+DECODE_WIDTH-dispatch_issue_num];
            end
        end
    end

endmodule
