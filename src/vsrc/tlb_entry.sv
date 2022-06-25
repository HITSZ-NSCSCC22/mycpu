`include "tlb_types.sv"

module tlb_entry
    import tlb_types::*;
(
    input logic clk,

    // search port 0, next cycle return 
    input logic s0_fetch,  // enable signal
    input logic [18:0] s0_vppn,  // three search info input
    input logic s0_odd_page,
    input logic [9:0] s0_asid,
    output logic s0_found,  // found
    output logic [$clog2(TLBNUM)-1:0] s0_index,  // TLB index
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
    output logic [$clog2(TLBNUM)-1:0] s1_index,
    output logic [5:0] s1_ps,
    output logic [19:0] s1_ppn,
    output logic s1_v,
    output logic s1_d,
    output logic [1:0] s1_mat,
    output logic [1:0] s1_plv,

    // write port, write on posedge
    input logic we,
    input logic [$clog2(TLBNUM)-1:0] w_index,
    input tlb_wr_port write_port,

    // read port, immediate return in same cycle
    input logic [$clog2(TLBNUM)-1:0] r_index,
    output tlb_wr_port read_port,

    // invalid port, on posedge
    input tlb_inv_t inv_i
);

    // Data structure
    logic [`ENTRY_LEN-1:0] tlb_entrys[TLBNUM-1:0];

    // One-hot match table
    logic [TLBNUM-1:0] match0;
    logic [TLBNUM-1:0] match1;

    logic [TLBNUM-1:0] s0_odd_page_buffer;
    logic [TLBNUM-1:0] s1_odd_page_buffer;

    genvar i;
    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin : match
            always @(posedge clk) begin
                if (s0_fetch) begin
                    s0_odd_page_buffer[i] <= (tlb_entrys[i][`PS] == 6'd12) ? s0_odd_page : s0_vppn[8];
                    match0[i] <= (tlb_entrys[i][`E] == 1'b1) && ((tlb_entrys[i][`PS] == 6'd12) ? s0_vppn == tlb_entrys[i][`VPPN] : s0_vppn[18:9] == tlb_entrys[i][`VPPN][18:9]) && ((s0_asid == tlb_entrys[i][`TLB_ASID]) || tlb_entrys[i][`G]);
                end
                if (s1_fetch) begin
                    s1_odd_page_buffer[i] <= (tlb_entrys[i][`PS] == 6'd12) ? s1_odd_page : s1_vppn[8];
                    match1[i] <= (tlb_entrys[i][`E] == 1'b1) && ((tlb_entrys[i][`PS] == 6'd12) ? s1_vppn == tlb_entrys[i][`VPPN] : s1_vppn[18:9] == tlb_entrys[i][`VPPN][18:9]) && ((s1_asid == tlb_entrys[i][`TLB_ASID]) || tlb_entrys[i][`G]);
                end
            end
        end
    endgenerate

    assign s0_found = match0 != 32'b0;  //!(!match0);
    assign s1_found = match1 != 32'b0;  //!(!match1);

    always_comb begin
        // Default value
        {s0_index, s0_ps, s0_ppn, s0_v, s0_d, s0_mat, s0_plv} = 0;
        {s1_index, s1_ps, s1_ppn, s1_v, s1_d, s1_mat, s1_plv} = 0;
        // Match 
        for (integer j = 0; j < 32; j++) begin
            if (match0[j]) begin
                {s0_index, s0_ps, s0_ppn, s0_v, s0_d, s0_mat, s0_plv} = {37{s0_odd_page_buffer[j] }} & {j[4:0], tlb_entrys[j][`PS], tlb_entrys[j][`PPN0], tlb_entrys[j][`V0], tlb_entrys[j][`D0], tlb_entrys[j][`MAT0], tlb_entrys[j][`PLV0]} |
                                                                {37{~s0_odd_page_buffer[j] }} & {j[4:0], tlb_entrys[j][`PS], tlb_entrys[j][`PPN0], tlb_entrys[j][`V0], tlb_entrys[j][`D0], tlb_entrys[j][`MAT0], tlb_entrys[j][`PLV0]};
            end
            if (match1[j]) begin
                {s1_index, s1_ps, s1_ppn, s1_v, s1_d, s1_mat, s1_plv} = {37{s1_odd_page_buffer[j] }} & {j[4:0], tlb_entrys[j][`PS], tlb_entrys[j][`PPN1], tlb_entrys[j][`V1], tlb_entrys[j][`D1], tlb_entrys[j][`MAT1], tlb_entrys[j][`PLV1]} |
                                                                {37{~s1_odd_page_buffer[j] }} & {j[4:0], tlb_entrys[j][`PS], tlb_entrys[j][`PPN1], tlb_entrys[j][`V1], tlb_entrys[j][`D1], tlb_entrys[j][`MAT1], tlb_entrys[j][`PLV1]};
            end
        end
    end


    always @(posedge clk) begin
        if (we) begin
            tlb_entrys[w_index][`VPPN] <= write_port.vppn;
            tlb_entrys[w_index][`TLB_ASID] <= write_port.asid;
            tlb_entrys[w_index][`G]    <= write_port.g;
            tlb_entrys[w_index][`PS]   <= write_port.ps;
            tlb_entrys[w_index][`PPN0] <= write_port.ppn0;
            tlb_entrys[w_index][`PLV0] <= write_port.plv0;
            tlb_entrys[w_index][`MAT0] <= write_port.mat0;
            tlb_entrys[w_index][`D0]   <= write_port.d0;
            tlb_entrys[w_index][`V0]   <= write_port.v0;
            tlb_entrys[w_index][`PPN1] <= write_port.ppn1;
            tlb_entrys[w_index][`PLV1] <= write_port.plv1;
            tlb_entrys[w_index][`MAT1] <= write_port.mat1;
            tlb_entrys[w_index][`D1]   <= write_port.d1;
            tlb_entrys[w_index][`V1]   <= write_port.v1;
        end
    end

    assign read_port.vppn = tlb_entrys[r_index][`VPPN];
    assign read_port.asid = tlb_entrys[r_index][`TLB_ASID];
    assign read_port.g    = tlb_entrys[r_index][`G];
    assign read_port.ps   = tlb_entrys[r_index][`PS];
    assign read_port.e    = tlb_entrys[r_index][`E];
    assign read_port.v0   = tlb_entrys[r_index][`V0];
    assign read_port.d0   = tlb_entrys[r_index][`D0];
    assign read_port.mat0 = tlb_entrys[r_index][`MAT0];
    assign read_port.plv0 = tlb_entrys[r_index][`PLV0];
    assign read_port.ppn0 = tlb_entrys[r_index][`PPN0];
    assign read_port.v1   = tlb_entrys[r_index][`V1];
    assign read_port.d1   = tlb_entrys[r_index][`D1];
    assign read_port.mat1 = tlb_entrys[r_index][`MAT1];
    assign read_port.plv1 = tlb_entrys[r_index][`PLV1];
    assign read_port.ppn1 = tlb_entrys[r_index][`PPN1];

    // DEBUG
    logic [31:0] debug_asid_match, debug_vppn_match;
    logic [18:0] debug_inv_vpn = inv_i.vpn;
    always_comb begin
        for (integer ii = 0; ii < TLBNUM; ii++) begin
            debug_asid_match[ii] = tlb_entrys[ii][`TLB_ASID] == inv_i.asid;
            debug_vppn_match[ii] = tlb_entrys[ii][`VPPN] == inv_i.vpn;
        end
    end

    //tlb entry invalid 
    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin : invalid_tlb_entry
            always @(posedge clk) begin
                if (we && (w_index == i)) begin
                    tlb_entrys[i][`E] <= write_port.e;
                end else if (inv_i.en) begin
                    // invalid search
                    if (inv_i.op == 5'd0 || inv_i.op == 5'd1) tlb_entrys[i][`E] <= 1'b0;
                    else if (inv_i.op == 5'd2 && tlb_entrys[i][`G]) tlb_entrys[i][`E] <= 1'b0;
                    else if (inv_i.op == 5'd3 && !tlb_entrys[i][`G]) tlb_entrys[i][`E] <= 1'b0;
                    else if (inv_i.op == 5'd4 && !tlb_entrys[i][`G] && (tlb_entrys[i][`TLB_ASID] == inv_i.asid))
                        tlb_entrys[i][`E] <= 1'b0;
                    else if (inv_i.op == 5'd5 && !tlb_entrys[i][`G] && (tlb_entrys[i][`TLB_ASID] == inv_i.asid) && 
                           ((tlb_entrys[i][`PS] == 6'd12) ? (tlb_entrys[i][`VPPN] == inv_i.vpn) : (tlb_entrys[i][`VPPN][18:10] == inv_i.vpn[18:10])))
                        tlb_entrys[i][`E] <= 1'b0;
                    else if (inv_i.op == 5'd6 && (tlb_entrys[i][`G] || (tlb_entrys[i][`TLB_ASID] == inv_i.asid)) && 
                           ((tlb_entrys[i][`PS] == 6'd12) ? (tlb_entrys[i][`VPPN] == inv_i.vpn) : (tlb_entrys[i][`VPPN][18:10] == inv_i.vpn[18:10])))
                        tlb_entrys[i][`E] <= 1'b0;
                end
            end
        end
    endgenerate

endmodule
