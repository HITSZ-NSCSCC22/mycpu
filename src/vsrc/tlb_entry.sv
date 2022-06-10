`include "tlb_types.sv"


module tlb_entry
    import tlb_types::*;
(
    input logic clk,
    // search port 0
    input logic s0_fetch,
    input logic [18:0] s0_vppn,
    input logic s0_odd_page,
    input logic [9:0] s0_asid,
    output logic s0_found,
    output logic [$clog2(TLBNUM)-1:0] s0_index,
    output logic [5:0] s0_ps,
    output logic [19:0] s0_ppn,
    output logic s0_v,
    output logic s0_d,
    output logic [1:0] s0_mat,
    output logic [1:0] s0_plv,
    //search port 1
    input logic s1_fetch,
    input logic [18:0] s1_vppn,
    input logic s1_odd_page,
    input logic [9:0] s1_asid,
    output logic s1_found,
    output logic [$clog2(TLBNUM)-1:0] s1_index,
    output logic [5:0] s1_ps,
    output logic [19:0] s1_ppn,
    output logic s1_v,
    output logic s1_d,
    output logic [1:0] s1_mat,
    output logic [1:0] s1_plv,
    // write port 
    input logic we,
    input logic [$clog2(TLBNUM)-1:0] w_index,
    input tlb_wr_port write_port,
    // read port
    input logic [$clog2(TLBNUM)-1:0] r_index,
    output tlb_wr_port read_port,
    // invalid port 
    input tlb_inv_in_struct inv_i
);

    logic [18:0] tlb_vppn[TLBNUM-1:0];
    logic tlb_e[TLBNUM-1:0];
    logic [9:0] tlb_asid[TLBNUM-1:0];
    logic tlb_g[TLBNUM-1:0];
    logic [5:0] tlb_ps[TLBNUM-1:0];
    logic [19:0] tlb_ppn0[TLBNUM-1:0];
    logic [1:0] tlb_plv0[TLBNUM-1:0];
    logic [1:0] tlb_mat0[TLBNUM-1:0];
    logic tlb_d0[TLBNUM-1:0];
    logic tlb_v0[TLBNUM-1:0];
    logic [19:0] tlb_ppn1[TLBNUM-1:0];
    logic [1:0] tlb_plv1[TLBNUM-1:0];
    logic [1:0] tlb_mat1[TLBNUM-1:0];
    logic tlb_d1[TLBNUM-1:0];
    logic tlb_v1[TLBNUM-1:0];

    logic [TLBNUM-1:0] match0;
    logic [TLBNUM-1:0] match1;

    logic [TLBNUM-1:0] s0_odd_page_buffer;
    logic [TLBNUM-1:0] s1_odd_page_buffer;

    genvar i;
    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin : match
            always @(posedge clk) begin
                if (s0_fetch) begin
                    s0_odd_page_buffer[i] <= (tlb_ps[i] == 6'd12) ? s0_odd_page : s0_vppn[9];
                    match0[i] <= (tlb_e[i] == 1'b1) && ((tlb_ps[i] == 6'd12) ? s0_vppn == tlb_vppn[i] : s0_vppn[18:10] == tlb_vppn[i][18:10]) && ((s0_asid == tlb_asid[i]) || tlb_g[i]);
                end
                if (s1_fetch) begin
                    s1_odd_page_buffer[i] <= (tlb_ps[i] == 6'd12) ? s1_odd_page : s1_vppn[9];
                    match1[i] <= (tlb_e[i] == 1'b1) && ((tlb_ps[i] == 6'd12) ? s1_vppn == tlb_vppn[i] : s1_vppn[18:10] == tlb_vppn[i][18:10]) && ((s1_asid == tlb_asid[i]) || tlb_g[i]);
                end
            end
        end
    endgenerate

    assign s0_found = match0 != 32'b0;  //!(!match0);
    assign s1_found = match1 != 32'b0;  //!(!match1);

    always_comb begin
        for (integer j = 0; j < 32; j++) begin
            if (match0[j]) begin
                {s0_index, s0_ps, s0_ppn, s0_v, s0_d, s0_mat, s0_plv} = {37{s0_odd_page_buffer[j] }} & {j[4:0], tlb_ps[j], tlb_ppn1[j], tlb_v1[j], tlb_d1[j], tlb_mat1[j], tlb_plv1[j]} |
                                                                {37{~s0_odd_page_buffer[j] }} & {j[4:0], tlb_ps[j], tlb_ppn0[j], tlb_v0[j], tlb_d0[j], tlb_mat0[j], tlb_plv0[j]};
            end
            if (match1[j]) begin
                {s1_index, s1_ps, s1_ppn, s1_v, s1_d, s1_mat, s1_plv} = {37{s1_odd_page_buffer[j] }} & {j[4:0], tlb_ps[j], tlb_ppn1[j], tlb_v1[j], tlb_d1[j], tlb_mat1[j], tlb_plv1[j]} |
                                                                {37{~s1_odd_page_buffer[j] }} & {j[4:0], tlb_ps[j], tlb_ppn0[j], tlb_v0[j], tlb_d0[j], tlb_mat0[j], tlb_plv0[j]};
            end
        end
    end


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

    //tlb entry invalid 
    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin : invalid_tlb_entry
            always @(posedge clk) begin
                if (we && (w_index == i)) tlb_e[i] <= write_port.e;
                else if (inv_i.en) begin
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
