// FPA detect the first 1 in input, from high to low

`ifndef FPA_V
`define FPA_V

module fpa #(
    parameter LINES = 16,
    parameter WIDTH = $clog2(LINES)
) (
    input  logic [LINES-1:0] unitary_in,
    output logic [WIDTH-1:0] binary_out
);

    logic [LINES-1:0] fliped_in;

    always @(*) begin
        for (integer i = 0; i < LINES; i = i + 1) begin
            fliped_in[i] = unitary_in[LINES-i-1];
        end
    end

    logic [LINES-1:0] one_hot;
    assign one_hot = fliped_in & ((~fliped_in) + 1);

    always @(*) begin
        binary_out = 0;
        for (integer i = 0; i < LINES; i = i + 1) begin
            if (one_hot[i]) binary_out = LINES[WIDTH-1:0] - i[WIDTH-1:0] - 1;
        end

    end

endmodule
`endif
