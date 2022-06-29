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

    (* ram_style = "distributed" *) logic [WIDTH-1:0] ram[DEPTH-1:0];


    always_ff @(posedge clk) begin
        if (we) ram[waddr] <= wdata;
    end

    assign inst_tlb_entry = ram[inst_addr];

    assign data_tlb_entry = ram[data_addr];

    assign rdata = ram[raddr];


    //debug用的信号
    logic [18:0] tlb_vppn[DEPTH-1:0];
    logic [ 9:0] tlb_asid[DEPTH-1:0];
    logic        tlb_g   [DEPTH-1:0];
    logic [ 5:0] tlb_ps  [DEPTH-1:0];
    logic [19:0] tlb_ppn0[DEPTH-1:0];
    logic [ 1:0] tlb_plv0[DEPTH-1:0];
    logic [ 1:0] tlb_mat0[DEPTH-1:0];
    logic        tlb_d0  [DEPTH-1:0];
    logic        tlb_v0  [DEPTH-1:0];
    logic [19:0] tlb_ppn1[DEPTH-1:0];
    logic [ 1:0] tlb_plv1[DEPTH-1:0];
    logic [ 1:0] tlb_mat1[DEPTH-1:0];
    logic        tlb_d1  [DEPTH-1:0];
    logic        tlb_v1  [DEPTH-1:0];

    generate
        for (genvar i = 0; i < DEPTH; i = i + 1) begin
            assign tlb_vppn[i] = ram[i][36:18];
            assign tlb_asid[i] = ram[i][10:1];
            assign tlb_g[i] = ram[i][11];
            assign tlb_ps[i] = ram[i][17:12];
            assign tlb_ppn0[i] = ram[i][62:43];
            assign tlb_plv0[i] = ram[i][42:41];
            assign tlb_mat0[i] = ram[i][40:39];
            assign tlb_v0[i] = ram[i][37];
            assign tlb_d0[i] = ram[i][38];
            assign tlb_ppn1[i] = ram[i][88:69];
            assign tlb_plv1[i] = ram[i][68:67];
            assign tlb_mat1[i] = ram[i][66:65];
            assign tlb_v1[i] = ram[i][63];
            assign tlb_d1[i] = ram[i][64];
        end
    endgenerate


endmodule
