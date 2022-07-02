module set_clr_reg_with_rst#(
    parameter SET_OVER_CLR = 0, 
    parameter WIDTH = 16, 
    parameter logic[WIDTH-1:0] RST_VALUE = '0
    )
    (
        input logic clk,
        input logic rst,

        input logic [WIDTH-1:0] set,
        input logic [WIDTH-1:0] clr,
        output logic [WIDTH-1:0] result
    );

    ////////////////////////////////////////////////////
    //Implementation
    generate if (SET_OVER_CLR) begin : gen_set_over_clear
        always_ff @ (posedge clk) begin
            if (rst)
                result <= RST_VALUE;
            else
                result <= set | (result & ~clr);
        end
    end else begin
        always_ff @ (posedge clk) begin : gen_clear_over_set
            if (rst)
                result <= RST_VALUE;
            else
                result <= (set | result) & ~clr;
        end
    end
    endgenerate

endmodule

