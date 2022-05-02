`include "branch_predictor/utils/xor_func.sv"

module folder_func #(
    parameter INPUT_LENGTH   = 10,
    parameter OUTPUT_LENGTH  = 8,
    parameter MAX_FOLD_ROUND = 3
) (
    input  wire [ INPUT_LENGTH-1:0] var_i,
    output wire [OUTPUT_LENGTH-1:0] var_o
);


    wire [2**MAX_FOLD_ROUND*OUTPUT_LENGTH-1:0] workspace[MAX_FOLD_ROUND];

    // Extend the input to working length
    assign workspace[0] = {{2 ** MAX_FOLD_ROUND * OUTPUT_LENGTH - INPUT_LENGTH{1'b0}}, var_i};
    // assign workspace[0] = {var_i};

    // Fold the input from workspace[0] to workspace[MAX_FOLD_ROUND-1]
    // using XOR
    generate
        genvar i;
        for (i = 1; i < MAX_FOLD_ROUND; i = i + 1) begin
            xor_func #(
                .HALF_DATA_WIDTH(2 ** (MAX_FOLD_ROUND - i) * OUTPUT_LENGTH)
            ) u_xor_func (
                .i(workspace[i-1][2**(MAX_FOLD_ROUND-i+1)*OUTPUT_LENGTH-1:0]),
                .o(workspace[i][2**(MAX_FOLD_ROUND-i+1)*OUTPUT_LENGTH-1:0])
            );
        end
    endgenerate

    assign var_o = workspace[MAX_FOLD_ROUND-1][OUTPUT_LENGTH-1:0];

endmodule
