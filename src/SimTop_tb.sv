`include "vsrc/defines.sv"
`timescale 1ns/1ps

module SimTop_tb();

reg CLOCK_50;
reg rst;
reg[63:0] io_logCtrl_log_begin;
reg[63:0] io_logCtrl_log_end;
reg[63:0] io_logCtrl_log_level;
reg io_perfInfo_clean;
reg io_perfInfo_dump;
wire io_uart_out_valid;
wire[7:0] io_uart_out_ch;
wire io_uart_in_valid;
wire[7:0] io_uart_in_ch;
  
       
initial begin
    CLOCK_50 = 1'b0;
    forever #10 CLOCK_50 = ~CLOCK_50;
end
      
initial begin
    rst = `RstEnable;
    #195 rst= `RstDisable;
    #1000 $stop;
end

initial begin
  io_logCtrl_log_begin = 64'b0;
  io_logCtrl_log_end = 64'b0;
  io_logCtrl_log_level = 64'b0;
  io_perfInfo_clean = 1'b0;
  io_perfInfo_dump = 1'b0;
end

       
SimTop u_SimTop(
    .clock(CLOCK_50),
    .reset(rst),
    .io_logCtrl_log_begin(io_logCtrl_log_begin),
    .io_logCtrl_log_end(io_logCtrl_log_end),
    .io_logCtrl_log_level(io_logCtrl_log_level),
    .io_perfInfo_clean(io_perfInfo_clean),
    .io_perfInfo_dump(io_perfInfo_dump),
    .io_uart_out_valid(io_uart_out_valid),
    .io_uart_out_ch(io_uart_out_ch),
    .io_uart_in_valid(io_uart_in_valid),
    .io_uart_in_ch(io_uart_in_ch)
);
endmodule