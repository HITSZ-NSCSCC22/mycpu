`include "defines.sv"
`include "muldiv/clz.sv"

module div_unit #(
    parameter DIV_WIDTH = 32
) (
    input logic clk,
    input logic rst,

    input logic [1:0] op,
    input logic [DIV_WIDTH-1:0] dividend,
    input logic [DIV_WIDTH-1:0] divisor,
    input logic [DIV_WIDTH-1:0] divisor_is_zero,
    input logic start,

    output logic is_running,
    output logic [DIV_WIDTH-1:0] remainder_out,
    output logic [DIV_WIDTH-1:0] quotient_out,
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

    logic signed_divop;
    logic negate_dividend;
    logic negate_divisor;
    logic negate_quotient;
    logic negate_remainder;
    logic [`RegBus] unsigned_dividend;
    logic [`RegBus] unsigned_divisor;
    logic [`RegBus] quotient;
    logic [`RegBus] remainder;
    logic [$clog2(32)-1:0] dividend_CLZ;
    logic [$clog2(32)-1:0] divisor_CLZ;

    assign signed_divop = ~op[0];

    assign negate_dividend = signed_divop & dividend[31];
    assign negate_divisor = signed_divop & divisor[31];

    assign negate_quotient = signed_divop & (dividend[31] ^ divisor[31]);
    assign negate_remainder = signed_divop & (dividend[31]);

    function logic [31:0] negate_if(input logic [31:0] a, logic b);
        return ({32{b}} ^ a) + 32'(b);
    endfunction


    assign unsigned_dividend = negate_if(dividend, negate_dividend);
    assign unsigned_divisor  = negate_if(divisor, negate_divisor);

    //Note: If this becomes the critical path, we can use the one's complemented input instead.
    //It will potentially overestimate (only when the input is a negative power-of-two), and
    //the divisor width will need to be increased by one to safely handle the case where the divisor CLZ is overestimated
    clz dividend_clz_block (
        .clz_input(unsigned_dividend),
        .clz_out  (dividend_CLZ)
    );
    clz divisor_clz_block (
        .clz_input(unsigned_divisor),
        .clz_out  (divisor_CLZ)
    );

    logic start_delay;

    always_ff @(posedge clk) begin
        if (rst) {divisor_greater_than_dividend, CLZ_delta} <= 0;
        else {divisor_greater_than_dividend, CLZ_delta} <= divisor_CLZ - dividend_CLZ;
    end

    always_ff @(posedge clk) begin
        if (rst) start_delay <= 1'b0;
        else if (start) start_delay <= 1'b1;
        else start_delay <= 1'b0;
    end

    always_ff @(posedge clk) begin
        if (running) shifted_divisor <= {2'b0, shifted_divisor[DIV_WIDTH-1:2]};
        else
            shifted_divisor <= unsigned_divisor << {CLZ_delta[CLZ_W-1:1], 1'b0};//Rounding down when CLZ_delta is odd
    end

    //Subtractions
    logic sub2x_toss;
    assign {sub_2x_overflow, sub2x_toss, sub_2x} = {1'b0, remainder} - {shifted_divisor, 1'b0};
    assign {sub_1x_overflow, sub_1x} = sub_2x_overflow ? {sub2x_toss, sub_2x} + {1'b0, shifted_divisor} : {sub2x_toss, sub_2x} - {1'b0, shifted_divisor};

    assign new_quotient_bits[1] = ~sub_2x_overflow;
    assign new_quotient_bits[0] = ~sub_1x_overflow;

    always_ff @(posedge clk) begin
        if (start_delay) quotient <= '0;
        else if (running) quotient <= {quotient[(DIV_WIDTH-3):0], new_quotient_bits};
    end

    //Remainder mux, when quotient bits are zero value is held
    always_ff @(posedge clk) begin
        if (start_delay | (running & |new_quotient_bits)) begin  //enable: on div.start_delay for init and so long as we are in the running state and the quotient pair is not zero
            case ({
                ~running, sub_1x_overflow
            })
                0: remainder <= sub_1x;
                1: remainder <= sub_2x;
                default:
                remainder <= unsigned_dividend;//Overloading the quotient zero case to fit the initial loading of the dividend in
            endcase
        end
    end

    assign {terminate, cycles_remaining_next} = cycles_remaining - 1;
    always_ff @(posedge clk) begin
        cycles_remaining <= running ? cycles_remaining_next : CLZ_delta[CLZ_W-1:1];
    end

    always_ff @(posedge clk) begin
        if (rst) running <= 0;
        else running <= (running & ~terminate) | (start_delay & ~divisor_greater_than_dividend);
    end

    assign is_running = running;


    // assign done = (running & terminate) | (start_delay & divisor_greater_than_dividend);

    logic running_delay;
    logic terminate_delay;
    logic start_delay_2;
    logic divisor_greater_than_dividend_delay;

    always_ff @(posedge clk) begin
        running_delay <= running;
        terminate_delay <= terminate;
        start_delay_2 <= start_delay;
        divisor_greater_than_dividend_delay <= divisor_greater_than_dividend;
    end

    always_comb begin
        if (dividend == 0) begin
            quotient_out  = 0;
            remainder_out = 0;
        end else begin
            quotient_out  = negate_quotient ? ~quotient + 1'b1 : quotient;
            remainder_out = negate_remainder ? ~remainder + 1'b1 : remainder;
        end
    end

    assign done = (running_delay & terminate_delay) | (start_delay_2 & divisor_greater_than_dividend_delay);


endmodule




