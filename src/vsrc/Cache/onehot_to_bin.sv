`timescale 1ns / 1ps

module onehot_to_bin #(
    parameter BIN_W = 2
) (
    input [2**BIN_W-1:1] onehot,
    output reg [BIN_W-1:0] bin
);
    always @(onehot) begin : onehot_to_binary_encoder
        integer i;
        reg [BIN_W-1:0] bin_cnt;
        bin_cnt = 0;
        for (i = 1; i < 2 ** BIN_W; i = i + 1) if (onehot[i]) bin_cnt = bin_cnt | i;
        bin = bin_cnt;
    end
endmodule
