`include "TLB/tlb_types.sv"

module tlb_lutram #(
    parameter WIDTH = 89,
    parameter DEPTH = 8
) (
    input clk,

    //inst_match
    input logic [$clog2(DEPTH)-1:0] inst_addr,
    output logic [WIDTH-1:0] inst_tlb_entry,

    //data_match
    input logic [$clog2(DEPTH)-1:0] data_addr,
    output logic [WIDTH-1:0] data_tlb_entry,

    //write-port
    input logic we,
    input logic [$clog2(DEPTH)-1:0] waddr,
    input logic [WIDTH-1:0] wdata,

    //read-port
    input logic [$clog2(DEPTH)-1:0] raddr,
    output logic [WIDTH-1:0] rdata
);

    (* ramstyle = "MLAB, no_rw_check", ram_style = "distributed" *) logic [WIDTH-1:0] ram [DEPTH-1:0];


    always_ff @(posedge clk) begin
        if (we) ram[waddr] <= wdata;
    end

    assign inst_tlb_entry = ram[inst_addr];



    assign data_tlb_entry = ram[data_addr];


    assign rdata = ram[raddr];


endmodule
