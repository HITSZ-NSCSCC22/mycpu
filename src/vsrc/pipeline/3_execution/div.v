//div module
module div (
    input wire clk,
    input wire rst,
    input wire [31:0]dividend,
    input wire [31:0]divisor,
    input wire valid1,//enable signal for div IP
    input wire valid2,
    input wire isSigned, 
    input wire div_start,   
    // output wire ready1,
    // output wire ready2,
    output wire ready, //finish flag
    output wire[63:0] result,
    output reg[31:0] cnt
);
    //use IP to div
    wire [63:0]dataSigned;
    wire [63:0]dataUnsigned;

            //signed
    div_gen_0_1 div_gen_0_1_0(
                .aclk                    (clk),
                .s_axis_divisor_tvalid   (valid2),
                .s_axis_divisor_tdata    (divisor),
                .s_axis_dividend_tvalid  (valid1),
                .s_axis_dividend_tdata   (dividend),
                .m_axis_dout_tvalid      (ready),
                .m_axis_dout_tdata       (dataSigned)
            );
            //unsigned
    divUnsigned divUnSigned0(
                .aclk                    (clk),
                .s_axis_divisor_tvalid   (valid2),
                .s_axis_divisor_tdata    (divisor),
                .s_axis_dividend_tvalid  (valid1),
                .s_axis_dividend_tdata   (dividend),
                .m_axis_dout_tvalid      (ready),
                .m_axis_dout_tdata       (dataUnsigned)
            ); 
    
     assign result=ready?(isSigned?dataSigned[63:0]:dataUnsigned[63:0]):0;

     //counter to reset valid1 and valid2
     always @(posedge clk)
     begin
         if(rst)    cnt<=32'b0;
         else if(div_start==0)  cnt<=32'b0;
         else if(div_start)     cnt<=cnt+32'h1;
         else cnt<=cnt;
     end

endmodule