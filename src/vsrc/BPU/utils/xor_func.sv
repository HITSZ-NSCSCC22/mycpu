// xor_func accept input, fold and xor, then extend to original length

module xor_func #(
    parameter HALF_DATA_WIDTH = 4
) (
    input  logic [HALF_DATA_WIDTH*2-1:0] i,
    output logic [HALF_DATA_WIDTH*2-1:0] o
);


    assign o = {
        {HALF_DATA_WIDTH{1'b0}}, i[HALF_DATA_WIDTH*2-1:HALF_DATA_WIDTH] ^ i[HALF_DATA_WIDTH-1:0]
    };

endmodule
