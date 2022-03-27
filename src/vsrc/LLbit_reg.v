`include "defines.v"
module LLbit_reg(
    input wire clk,
    input wire rst,
    
    input wire flush,
    
    input wire LLbit_i,
    input wire we,
    
    output reg LLbit_o
    );
    
    always @(posedge clk)
    begin   
        if(rst) 
            LLbit_o<=0;
        else if(flush)  
            LLbit_o<=0;
        else if(we) 
            LLbit_o<=LLbit_i;
        else 
            LLbit_o<=LLbit_o;
    end
endmodule
