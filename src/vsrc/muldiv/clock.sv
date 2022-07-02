module clock
(

    input logic [31:0] clz_input,
    output logic [4:0] clz
);

    logic [1:0] low_order_clz [7:0];
    logic [7:0] sub_clz;

    logic [1:0] upper_lower [3:0];

    const logic [1:0] clz_low_table [8] = '{2'd3, 2'd2, 2'd1, 2'd1, 2'd0, 2'd0, 2'd0, 2'd0};
    always_comb begin
        for (int i=0; i<8; i++) begin
            sub_clz[7-i] = ~|clz_input[(i*4) +: 4];
            low_order_clz[7-i] = clz_low_table[clz_input[(i*4) + 1 +: 3]];
        end

        clz[4] = &sub_clz[3:0]; //upper 16 all zero
        clz[3] = clz[4] ? &sub_clz[5:4] : &sub_clz[1:0];//upper 24 zero, or first 8 zero
        clz[2] =
            (sub_clz[0] & ~sub_clz[1]) |
            (&sub_clz[2:0] & ~sub_clz[3]) |
            (&sub_clz[4:0] & ~sub_clz[5]) |
            (&sub_clz[6:0]);

        for (int i=0; i<8; i+=2) begin
            upper_lower[i/2] = low_order_clz[{i[2:1],  sub_clz[i]}];
        end

        clz[1:0] = upper_lower[clz[4:3]];
    end

endmodule
