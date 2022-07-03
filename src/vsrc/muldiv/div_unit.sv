module div_unit #(
    parameter DIV_WIDTH = 32
) (
    input logic clk,
    input logic rst,

    input logic [DIV_WIDTH-1:0] dividend,
    input logic [$clog2(DIV_WIDTH)-1:0] dividend_CLZ,
    input logic [DIV_WIDTH-1:0] divisor,
    input logic [$clog2(DIV_WIDTH)-1:0] divisor_CLZ,
    input logic [DIV_WIDTH-1:0] divisor_is_zero,
    input logic start,

    output logic [DIV_WIDTH-1:0] remainder,
    output logic [DIV_WIDTH-1:0] quotient,
    output logic done
);

    localparam CLZ_W = $clog2(DIV_WIDTH);
    logic [CLZ_W-1:0] CLZ_delta;

    logic divisor_greater_than_dividend;

    logic [DIV_WIDTH-1:0] shifted_divisor;

    logic [1:0] new_quotient_bits;
    logic [DIV_WIDTH-1:0] sub_1x;
    logic [DIV_WIDTH-1:0] sub_2x;
    logic sub_1x_overflow;
    logic sub_2x_overflow;

    logic [CLZ_W-2:0] cycles_remaining;
    logic [CLZ_W-2:0] cycles_remaining_next;

    logic running;
    logic terminate;
    ////////////////////////////////////////////////////
    //Implementation
    //First cycle
    assign {divisor_greater_than_dividend, CLZ_delta} = divisor_CLZ - dividend_CLZ;

    always_ff @(posedge clk) begin
        if (running) shifted_divisor <= {2'b0, shifted_divisor[DIV_WIDTH-1:2]};
        else
            shifted_divisor <= divisor << {CLZ_delta[CLZ_W-1:1], 1'b0};//Rounding down when CLZ_delta is odd
    end

    //Subtractions
    logic sub2x_toss;
    assign {sub_2x_overflow, sub2x_toss, sub_2x} = {1'b0, remainder} - {shifted_divisor, 1'b0};
    assign {sub_1x_overflow, sub_1x} = sub_2x_overflow ? {sub2x_toss, sub_2x} + {1'b0, shifted_divisor} : {sub2x_toss, sub_2x} - {1'b0, shifted_divisor};

    assign new_quotient_bits[1] = ~sub_2x_overflow;
    assign new_quotient_bits[0] = ~sub_1x_overflow;

    always_ff @(posedge clk) begin
        if (start) quotient <= '0;
        else if (running) quotient <= {quotient[(DIV_WIDTH-3):0], new_quotient_bits};
    end

    //Remainder mux, when quotient bits are zero value is held
    always_ff @(posedge clk) begin
        if (start | (running & |new_quotient_bits)) begin  //enable: on div.start for init and so long as we are in the running state and the quotient pair is not zero
            case ({
                ~running, sub_1x_overflow
            })
                0: remainder <= sub_1x;
                1: remainder <= sub_2x;
                default:
                remainder <= dividend;//Overloading the quotient zero case to fit the initial loading of the dividend in
            endcase
        end
    end

    ////////////////////////////////////////////////////
    //Control Signals

    //can merge with CLZ subtraction and remove mux on divisor if inputs held constant
    assign {terminate, cycles_remaining_next} = cycles_remaining - 1;
    always_ff @(posedge clk) begin
        cycles_remaining <= running ? cycles_remaining_next : CLZ_delta[CLZ_W-1:1];
    end

    always_ff @(posedge clk) begin
        if (rst) running <= 0;
        else running <= (running & ~terminate) | (start & ~divisor_greater_than_dividend);
    end

    assign done = (running & terminate) | (start & divisor_greater_than_dividend);

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions

endmodule
