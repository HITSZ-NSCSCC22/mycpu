`include "TLB/tlb_types.sv"

module tlb_lutram #(
    parameter WIDTH = 89,
    parameter DEPTH = 32
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

    (* ramstyle = "MLAB, no_rw_check", ram_style = "distributed" *) logic [WIDTH-1:0] ram [DEPTH-1:0];

    initial ram = '{default: 0};

    always_ff @(posedge clk) begin
        if (we) ram[waddr] <= wdata;
    end

    always_comb begin
        if (inst_match) begin
            inst_tlb_entry = ram[inst_addr];
        end else begin
            inst_tlb_entry = 0;
        end
    end

    always_comb begin
        if (data_match) begin
            data_tlb_entry = ram[data_addr];
        end else begin
            data_tlb_entry = 0;
        end
    end

    assign rdata = ram[raddr];

    assign searchout = ram[match_search];

    assign invtlbout = ram[invtlb_search];

endmodule
