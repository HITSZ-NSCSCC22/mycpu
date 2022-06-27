`include "TLB/tlb_types.sv"

module tlb_lutram #(
    parameter WIDTH = 89,
    parameter DEPTH = 32,
    parameter GROUP = 8,
    parameter NWAY  = 4
) (
    input clk,

    //inst_match
    input logic inst_match,
    input logic [$clog2(DEPTH)-1:0] inst_addr,
    output logic [WIDTH-1:0] inst_tlb_entry,

    //data_match
    input logic data_match,
    input logic [$clog2(DEPTH)-1:0] data_addr,
    output logic [WIDTH-1:0] data_tlb_entry,

    //write-port
    input logic we,
    input logic [$clog2(DEPTH)-1:0] waddr,
    input logic [WIDTH-1:0] wdata,

    //read-port
    input logic [$clog2(DEPTH)-1:0] raddr,
    output logic [WIDTH-1:0] rdata,

    //
    input logic [$clog2(DEPTH)-1:0] match_search,
    output logic [WIDTH-1:0] searchout,

    input logic [$clog2(DEPTH)-1:0] invtlb_search,
    output logic [WIDTH-1:0] invtlbout
);

    (* ramstyle = "MLAB, no_rw_check", ram_style = "distributed" *) logic [WIDTH-1:0] ram [GROUP-1:0][NWAY-1:0];

    initial ram = '{default: 0};

    always_ff @(posedge clk) begin
        if (we) ram[waddr[4:2]][waddr[1:0]] <= wdata;
    end

    always_comb begin
        if (inst_match) begin
            inst_tlb_entry = [inst_addr[4:2]][inst_addr[1:0]];
        end else begin
            inst_tlb_entry = 0;
        end
    end

    always_comb begin
        if (data_match) begin
            data_tlb_entry = ram[data_addr[4:2]][data_addr[1:0]];
        end else begin
            data_tlb_entry = 0;
        end
    end

    assign rdata = ram[raddr[4:2]][raddr[1:0]];

    assign searchout = ram[match_search];

    assign invtlbout = ram[invtlb_search];

endmodule
