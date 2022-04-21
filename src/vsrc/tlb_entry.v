module tlb_entry 
#(
    parameter TLBNum = 32;
    parameter EntryLen = 88:0;
    parameter TLB_e = 0;
    parameter TLB_asid = 10:1;
    parameter TLB_g = 11;
    parameter TLB_ps = 17:12;
    parameter TLB_vppn = 36:18;
    parameter TLB_v0 = 37;
    parameter TLB_d0 = 38;
    parameter TLB_mat0 = 40:39;
    parameter TLB_plv0 = 42:41;
    parameter TLB_ppn0 = 62:43;
    parameter TLB_v1 = 63;
    parameter TLB_d1 = 64;
    parameter TLB_mat1 = 66:65;
    parameter TLB_plv1 = 68:67;
    parameter TLB_ppn1 = 88:69;
)
(
    input wire clk,
    input wire rst,

    input wire s0_match,
    input wire [18:0] s0_vppn,
    input wire s0_odd_page,
    input wire [9:0]s0_asid,
    
    output reg s0_found,
    output reg[$clog2(TLBNUM)-1:0] s0_index ,
    output reg[5:0] s0_ps,
    output reg[19:0] s0_ppn,
    output reg s0_v,
    output reg s0_d,
    output reg[1:0] s0_mat,
    output reg[1:0] s0_plv, 

    input wire s1_match,
    input wire [18:0] s1_vppn,
    input wire s1_odd_page,
    input wire [9:0]s1_asid,
    
    output reg s1_found,
    output reg[$clog2(TLBNUM)-1:0] s1_index ,
    output reg[5:0] s1_ps,
    output reg[19:0] s1_ppn,
    output reg s1_v,
    output reg s1_d,
    output reg[1:0] s1_mat,
    output reg[1:0] s1_plv, 

    input wire we,
    input wire[$clog2(TLBNUM)-1:0] w_index,
    input wire[18:0] w_vppn,
    input wire[ 9:0] w_asid,
    input wire w_g ,
    input wire [5:0]w_ps,
    input wire w_e,
    input wire w_v0,
    input wire w_d0,
    input wire [1:0] w_mat0,
    input wire [1:0] w_plv0,
    input wire [19:0] w_ppn0,
    input wire w_v1,
    input wire w_d1,
    input wire [1:0] w_mat1,
    input wire [1:0] w_plv1,
    input wire [19:0] w_ppn1,

    input wire[$clog2(TLBNUM)-1:0] r_index,
    output wire[18:0] r_vppn,
    output wire[ 9:0] r_asid,
    output wire r_g ,
    output wire[5:0] r_ps,
    output wire r_e,
    output wire r_v0,
    output wire r_d0,
    output wire[1:0]r_mat0,
    output wire[1:0]r_plv0,
    output wire[19:0]r_ppn0,
    output wire r_v1,
    output wire r_d1,
    output wire[1:0] r_mat1,
    output wire[1:0] r_plv1 ,
    output wire[19:0] r_ppn1,

    input wire  inv_en,
    input wire[ 4:0] inv_op,
    input wire[ 9:0] inv_asid,
    input wire[18:0] inv_vpn
);

reg [EntryLen] entry [TLBNum-1:0];
    
endmodule