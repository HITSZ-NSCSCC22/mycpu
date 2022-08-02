module one_hot_to_index #(
    parameter C_WIDTH = 40
) (
    input logic [C_WIDTH-1:0] one_hot,
    output logic [(C_WIDTH == 1) ? 0 : ($clog2(C_WIDTH)-1) : 0] int_out
);
    generate
        if (C_WIDTH == 1) begin : gen_width_one
            assign int_out = 0;
        end else begin : gen_width_two_plus
            always_comb begin
                int_out = 0;
                foreach (one_hot[i]) int_out |= one_hot[i] ? $clog2(C_WIDTH)'(i) : 0;
            end
        end
    endgenerate

endmodule
