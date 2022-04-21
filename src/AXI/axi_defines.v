// signal width
`define ID 3:0
`define ADDR 31:0
`define Len 7:0
`define Size 2:0
`define Burst 1:0
`define Lock 1:0
`define Cache 3:0
`define Prot 2:0
`define Data 31:0
`define Resp 1:0


//Master read state
`define R_FREE 4'b0000
`define R_ADDR 4'b0001
`define R_DATA 4'b0010

//Master write state
`define W_FREE 4'b0011
`define W_ADDR 4'b0100
`define W_DATA 4'b0101
`define W_RESP 4'b0110

//burst
`define FIXED 2'b00
`define INCR 2'b01
`define WRAP 2'b10