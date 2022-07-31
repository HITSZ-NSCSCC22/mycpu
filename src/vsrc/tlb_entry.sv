`include "core_config.sv"
`include "TLB/tlb_types.sv"
`include "utils/one_hot_to_index.sv"

module tlb_entry
    import tlb_types::*;
    import core_config::*;
(
    input logic clk,

    // search port 0, next cycle return 
    input logic s0_fetch,  // enable signal
    input logic [18:0] s0_vppn,  // three search info input
    input logic s0_odd_page,
    input logic [9:0] s0_asid,
    output logic s0_found,  // found
    output logic [$clog2(TLB_NUM)-1:0] s0_index,  // TLB index
    output logic [5:0] s0_ps,  // ps
    output logic [19:0] s0_ppn,  // Physical page number, same as tag
    output logic s0_v,  // valid flag
    output logic s0_d,  // dirty flag
    output logic [1:0] s0_mat,  // mat
    output logic [1:0] s0_plv,  // plv, privilege level flag

    //search port 1, next cycle return
    input logic s1_fetch,
    input logic [18:0] s1_vppn,
    input logic s1_odd_page,
    input logic [9:0] s1_asid,
    output logic s1_found,
    output logic [$clog2(TLB_NUM)-1:0] s1_index,
    output logic [5:0] s1_ps,
    output logic [19:0] s1_ppn,
    output logic s1_v,
    output logic s1_d,
    output logic [1:0] s1_mat,
    output logic [1:0] s1_plv,

    // write port, write on posedge
    input logic we,
    input logic [$clog2(TLB_NUM)-1:0] w_index,
    input tlb_wr_port write_port,

    // read port, immediate return in same cycle
    input logic [$clog2(TLB_NUM)-1:0] r_index,
    output tlb_wr_port read_port,

    // invalid port, on posedge
    input tlb_inv_t inv_i
);

    // Parameters
    localparam TLB_INDEX_WIDTH = $clog2(TLB_NUM);

    // Data structure
    logic [18:0] tlb_vppn[TLB_NUM-1:0];
    logic [TLB_NUM-1:0] tlb_e;
    logic [9:0] tlb_asid[TLB_NUM-1:0];
    logic [TLB_NUM-1:0] tlb_g;
    logic [5:0] tlb_ps[TLB_NUM-1:0];
    logic [19:0] tlb_ppn0[TLB_NUM-1:0];
    logic [1:0] tlb_plv0[TLB_NUM-1:0];
    logic [1:0] tlb_mat0[TLB_NUM-1:0];
    logic tlb_d0[TLB_NUM-1:0];
    logic tlb_v0[TLB_NUM-1:0];
    logic [19:0] tlb_ppn1[TLB_NUM-1:0];
    logic [1:0] tlb_plv1[TLB_NUM-1:0];
    logic [1:0] tlb_mat1[TLB_NUM-1:0];
    logic tlb_d1[TLB_NUM-1:0];
    logic tlb_v1[TLB_NUM-1:0];

    // One-hot match table
    logic [TLB_NUM-1:0] match0;
    logic [TLB_NUM-1:0] match1;

    logic [TLB_NUM-1:0] s0_odd_page_buffer;
    logic [TLB_NUM-1:0] s1_odd_page_buffer;

    genvar i;
    generate
        for (i = 0; i < TLB_NUM; i = i + 1) begin : match
            always @(posedge clk) begin
                if (s0_fetch) begin
                    s0_odd_page_buffer[i] <= (tlb_ps[i] == 6'd12) ? s0_odd_page : s0_vppn[8];
                    match0[i] <= (tlb_e[i] == 1'b1) && ((tlb_ps[i] == 6'd12) ? s0_vppn == tlb_vppn[i] : s0_vppn[18:9] == tlb_vppn[i][18:9]) && ((s0_asid == tlb_asid[i]) || tlb_g[i]);
                end
                if (s1_fetch) begin
                    s1_odd_page_buffer[i] <= (tlb_ps[i] == 6'd12) ? s1_odd_page : s1_vppn[8];
                    match1[i] <= (tlb_e[i] == 1'b1) && ((tlb_ps[i] == 6'd12) ? s1_vppn == tlb_vppn[i] : s1_vppn[18:9] == tlb_vppn[i][18:9]) && ((s1_asid == tlb_asid[i]) || tlb_g[i]);
                end
            end
        end
    endgenerate

    assign s0_found = match0 != 0;
    assign s1_found = match1 != 0;

    one_hot_to_index #(
        .C_WIDTH(TLB_NUM)
    ) u_s0_index (
        .one_hot(match0),
        .int_out(s0_index)
    );
    one_hot_to_index #(
        .C_WIDTH(TLB_NUM)
    ) u_s1_index (
        .one_hot(match1),
        .int_out(s1_index)
    );



    assign  {s0_ps, s0_ppn, s0_v, s0_d, s0_mat, s0_plv} = 
    {32{s0_odd_page_buffer[s0_index] }} & {tlb_ps[s0_index], tlb_ppn1[s0_index], tlb_v1[s0_index], tlb_d1[s0_index], tlb_mat1[s0_index], tlb_plv1[s0_index]} |
    {32{~s0_odd_page_buffer[s0_index] }} & {tlb_ps[s0_index], tlb_ppn0[s0_index], tlb_v0[s0_index], tlb_d0[s0_index], tlb_mat0[s0_index], tlb_plv0[s0_index]};
    assign   {s1_ps, s1_ppn, s1_v, s1_d, s1_mat, s1_plv} = 
    {32{s1_odd_page_buffer[s1_index] }} & {tlb_ps[s1_index], tlb_ppn1[s1_index], tlb_v1[s1_index], tlb_d1[s1_index], tlb_mat1[s1_index], tlb_plv1[s1_index]} |
    {32{~s1_odd_page_buffer[s1_index] }} & {tlb_ps[s1_index], tlb_ppn0[s1_index], tlb_v0[s1_index], tlb_d0[s1_index], tlb_mat0[s1_index], tlb_plv0[s1_index]};



    always @(posedge clk) begin
        if (we) begin
            tlb_vppn[w_index] <= write_port.vppn;
            tlb_asid[w_index] <= write_port.asid;
            tlb_g[w_index]    <= write_port.g;
            tlb_ps[w_index]   <= write_port.ps;
            tlb_ppn0[w_index] <= write_port.ppn0;
            tlb_plv0[w_index] <= write_port.plv0;
            tlb_mat0[w_index] <= write_port.mat0;
            tlb_d0[w_index]   <= write_port.d0;
            tlb_v0[w_index]   <= write_port.v0;
            tlb_ppn1[w_index] <= write_port.ppn1;
            tlb_plv1[w_index] <= write_port.plv1;
            tlb_mat1[w_index] <= write_port.mat1;
            tlb_d1[w_index]   <= write_port.d1;
            tlb_v1[w_index]   <= write_port.v1;
        end
    end

    assign read_port.vppn = tlb_vppn[r_index];
    assign read_port.asid = tlb_asid[r_index];
    assign read_port.g    = tlb_g[r_index];
    assign read_port.ps   = tlb_ps[r_index];
    assign read_port.e    = tlb_e[r_index];
    assign read_port.v0   = tlb_v0[r_index];
    assign read_port.d0   = tlb_d0[r_index];
    assign read_port.mat0 = tlb_mat0[r_index];
    assign read_port.plv0 = tlb_plv0[r_index];
    assign read_port.ppn0 = tlb_ppn0[r_index];
    assign read_port.v1   = tlb_v1[r_index];
    assign read_port.d1   = tlb_d1[r_index];
    assign read_port.mat1 = tlb_mat1[r_index];
    assign read_port.plv1 = tlb_plv1[r_index];
    assign read_port.ppn1 = tlb_ppn1[r_index];

    // DEBUG
    logic [31:0] debug_asid_match, debug_vppn_match;
    logic [18:0] debug_inv_vpn = inv_i.vpn;
    always_comb begin
        for (integer ii = 0; ii < TLB_NUM; ii++) begin
            debug_asid_match[ii] = tlb_asid[ii] == inv_i.asid;
            debug_vppn_match[ii] = tlb_vppn[ii] == inv_i.vpn;
        end
    end

    //tlb entry invalid 
    generate
        for (i = 0; i < TLB_NUM; i = i + 1) begin : invalid_tlb_entry
            always @(posedge clk) begin
                if (we && (w_index == i)) begin
                    tlb_e[i] <= write_port.e;
                end else if (inv_i.en) begin
                    // invalid search
                    if (inv_i.op == 5'd0 || inv_i.op == 5'd1) tlb_e[i] <= 1'b0;
                    else if (inv_i.op == 5'd2 && tlb_g[i]) tlb_e[i] <= 1'b0;
                    else if (inv_i.op == 5'd3 && !tlb_g[i]) tlb_e[i] <= 1'b0;
                    else if (inv_i.op == 5'd4 && !tlb_g[i] && (tlb_asid[i] == inv_i.asid))
                        tlb_e[i] <= 1'b0;
                    else if (inv_i.op == 5'd5 && !tlb_g[i] && (tlb_asid[i] == inv_i.asid) && 
                           ((tlb_ps[i] == 6'd12) ? (tlb_vppn[i] == inv_i.vpn) : (tlb_vppn[i][18:10] == inv_i.vpn[18:10])))
                        tlb_e[i] <= 1'b0;
                    else if (inv_i.op == 5'd6 && (tlb_g[i] || (tlb_asid[i] == inv_i.asid)) && 
                           ((tlb_ps[i] == 6'd12) ? (tlb_vppn[i] == inv_i.vpn) : (tlb_vppn[i][18:10] == inv_i.vpn[18:10])))
                        tlb_e[i] <= 1'b0;
                end
            end
        end
    endgenerate

endmodule
