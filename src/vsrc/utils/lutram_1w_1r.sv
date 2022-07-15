module lutram_1w_1r 
#(
    parameter WIDTH = 32,
    parameter DEPTH = 32
)(
    input logic clk,

    input logic[$clog2(DEPTH)-1:0] waddr,
    input logic[$clog2(DEPTH)-1:0] raddr,

    input logic ram_write,
    input logic[WIDTH-1:0] new_ram_data,
    output logic[WIDTH-1:0] ram_data_out
);

(* ramstyle = "MLAB, no_rw_check", ram_style = "distributed" *) logic [WIDTH-1:0] ram [DEPTH-1:0];

initial ram = '{default : 0};

always_ff @( posedge clk ) begin 
    if(ram_write)
        ram[waddr] <= new_ram_data;
end

assign ram_data_out = ram[raddr];
    
endmodule
