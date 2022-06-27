`include "TLB/tlb_types.sv"
`include "TLB/tlb_lutram.sv"

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
    logic tlb_e[TLBNUM-1:0];

    logic [TLBNUM-1:0] match0;
    logic [TLBNUM-1:0] match1;

    //指令查找口
    logic inst_match, inst_odd_page;
    logic [$clog2(TLBNUM)-1:0] inst_addr;
    logic [`ENTRY_LEN-1:0] inst_entry;

    //数据查找口
    logic data_match, data_odd_page;
    logic [$clog2(TLBNUM)-1:0] data_addr;
    logic [`ENTRY_LEN-1:0] data_entry;

    //对比查找口
    logic [$clog2(TLBNUM)-1:0] match_search;
    logic [`ENTRY_LEN-1:0] searchout;

    //invtlb查找口
    logic [$clog2(TLBNUM)-1:0] invtlb_search;
    logic [`ENTRY_LEN-1:0] invtlbout;

    logic [TLBNUM-1:0] s0_odd_page_buffer;
    logic [TLBNUM-1:0] s1_odd_page_buffer;

    tlb_wr_port read_port_buffer;

    tlb_lutram tlb_lutram0 (
        .clk(clk),

        .inst_match(inst_match),
        .inst_addr(inst_addr),
        .inst_tlb_entry(inst_entry),

        .data_match(data_match),
        .data_addr(data_addr),
        .data_tlb_entry(data_entry),

        //write-port
        .we(we),
        .waddr(w_index),
        .wdata(write_port),

        .raddr(r_index),
        .rdata(read_port_buffer),

        .match_search(match_search),
        .searchout(searchout),

        .invtlb_search(invtlb_search),
        .invtlbout(invtlbout)
    );

    logic [31:0] inst_tag;
    logic [31:0] data_tag;
    assign inst_tag = {29'b0, s0_vppn[2:0]};
    assign data_tag = {29'b0, s1_vppn[2:0]};

    genvar i;
    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin : inst_search
            assign match_search = i;
            always @(posedge clk) begin
                if (s0_fetch) begin
                    s0_odd_page_buffer[i] <= (searchout[`ENTRY_PS] == 6'd12) ? s0_odd_page : s0_vppn[8];
                    match0[i] <= (tlb_e[i] == 1'b1) && ((searchout[`ENTRY_PS] == 6'd12) ? s0_vppn == searchout[`ENTRY_VPPN] : s0_vppn[18:9] == searchout[`ENTRY_VPPN_H0]) && ((s0_asid == searchout[`ENTRY_ASID]) || searchout[`ENTRY_G]);
                end
            end
        end
    endgenerate

    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin : data_search
            assign match_search = i;
            always @(posedge clk) begin
                if (s1_fetch) begin
                    s1_odd_page_buffer[i] <= (searchout[`ENTRY_PS] == 6'd12) ? s1_odd_page : s1_vppn[8];
                    match1[i] <= (tlb_e[i] == 1'b1) && ((searchout[`ENTRY_PS] == 6'd12) ? s1_vppn == searchout[`ENTRY_VPPN] : s1_vppn[18:9] == searchout[`ENTRY_VPPN_H0]) && ((s1_asid == searchout[`ENTRY_ASID]) || searchout[`ENTRY_G]);
                end
            end
        end
    endgenerate

    assign s0_found = match0 != 32'b0;  //!(!match0);
    assign s1_found = match1 != 32'b0;  //!(!match1);
    assign inst_match = match0 != 32'b0;
    assign data_match = match1 != 32'b0;
    assign inst_odd_page = s0_odd_page_buffer[inst_addr];
    assign data_odd_page = s1_odd_page_buffer[data_addr];

    always_comb begin
        for (integer j = 0; j < 32; j++) begin
            if (match0[j]) inst_addr = j[4:0];
            else inst_addr = 5'b0;
            if (match1[j]) data_addr = j[4:0];
            else data_addr = 5'b0;
        end
    end

    assign {s0_index, s0_ps, s0_ppn, s0_v, s0_d, s0_mat, s0_plv} = inst_odd_page ? {inst_addr, inst_entry[`ENTRY_PS], inst_entry[`ENTRY_PPN1], inst_entry[`ENTRY_V1], inst_entry[`ENTRY_D1], inst_entry[`ENTRY_MAT1], inst_entry[`ENTRY_PLV1]} :
                                                                {inst_addr, inst_entry[`ENTRY_PS], inst_entry[`ENTRY_PPN0], inst_entry[`ENTRY_V0], inst_entry[`ENTRY_D0], inst_entry[`ENTRY_MAT0], inst_entry[`ENTRY_PLV0]};
    assign {s1_index, s1_ps, s1_ppn, s1_v, s1_d, s1_mat, s1_plv} = data_odd_page ? {data_addr, data_entry[`ENTRY_PS], data_entry[`ENTRY_PPN1], data_entry[`ENTRY_V1], data_entry[`ENTRY_D1], data_entry[`ENTRY_MAT1], data_entry[`ENTRY_PLV1]} :
                                                                 {data_addr, data_entry[`ENTRY_PS], data_entry[`ENTRY_PPN0], data_entry[`ENTRY_V0], data_entry[`ENTRY_D0], data_entry[`ENTRY_MAT0], data_entry[`ENTRY_PLV0]};

    //read port driven
    assign read_port = {tlb_e[r_index], read_port_buffer[87:0]};


    //tlb entry invalid 
    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin : invalid_tlb_entry
            assign invtlb_search = i;
            always @(posedge clk) begin
                if (we && (w_index == i)) begin
                    tlb_e[i] <= write_port.e;
                end else if (inv_i.en) begin
                    // invalid search
                    if (inv_i.op == 5'd0 || inv_i.op == 5'd1) tlb_e[i] <= 1'b0;
                    else if (inv_i.op == 5'd2 && invtlbout[`ENTRY_G]) tlb_e[i] <= 1'b0;
                    else if (inv_i.op == 5'd3 && !invtlbout[`ENTRY_G]) tlb_e[i] <= 1'b0;
                    else if (inv_i.op == 5'd4 && !invtlbout[`ENTRY_G] && (invtlbout[`ENTRY_ASID] == inv_i.asid))
                        tlb_e[i] <= 1'b0;
                    else if (inv_i.op == 5'd5 && !invtlbout[`ENTRY_G] && (invtlbout[`ENTRY_ASID] == inv_i.asid) && 
                           ((invtlbout[`ENTRY_PS] == 6'd12) ? (invtlbout[`ENTRY_VPPN] == inv_i.vpn) : (invtlbout[`ENTRY_VPPN_H1] == inv_i.vpn[18:10])))
                        tlb_e[i] <= 1'b0;
                    else if (inv_i.op == 5'd6 && (invtlbout[`ENTRY_G] || (invtlbout[`ENTRY_ASID] == inv_i.asid)) && 
                           ((invtlbout[`ENTRY_PS] == 6'd12) ? (invtlbout[`ENTRY_VPPN] == inv_i.vpn) : (invtlbout[`ENTRY_VPPN_H1] == inv_i.vpn[18:10])))
                        tlb_e[i] <= 1'b0;
                end
            end
        end
    endgenerate

endmodule
