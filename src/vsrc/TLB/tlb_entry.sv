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

    //match index
    logic [NWAY-1:0] match0;
    logic [NWAY-1:0] match1;

    //inst search port 
    logic inst_odd_page;
    logic [$clog2(NWAY)-1:0] inst_index;
    logic [$clog2(NSET)-1:0] inst_addr;
    logic [`ENTRY_LEN-1:0] inst_entry[NWAY-1:0];

    //data search port
    logic data_odd_page;
    logic [$clog2(NWAY)-1:0] data_index;
    logic [$clog2(NSET)-1:0] data_addr;
    logic [`ENTRY_LEN-1:0] data_entry[NWAY-1:0];

    //wirte port
    logic wen[NWAY-1:0];
    logic [$clog2(NSET)-1:0] waddr[NWAY-1:0];
    logic [`ENTRY_LEN-1:0] wdata[NWAY-1:0];

    //read port
    logic [$clog2(NSET)-1:0] raddr;
    logic [`ENTRY_LEN-1:0] rdata[NWAY-1:0];


    logic [NWAY-1:0] s0_odd_page_buffer;
    logic [NWAY-1:0] s1_odd_page_buffer;


    for (genvar i = 0; i < NWAY; i = i + 1) begin
        tlb_lutram tlb_lutram0 (
            .clk(clk),

            .inst_addr(inst_addr),
            .inst_tlb_entry(inst_entry[i]),

            .data_addr(data_addr),
            .data_tlb_entry(data_entry[i]),

            //write-port
            .we(wen[i]),
            .waddr(waddr[i]),
            .wdata(wdata[i]),

            .raddr(raddr),
            .rdata(rdata[i])
        );
    end

    assign inst_addr = s0_vppn[2:0];
    assign data_addr = s1_vppn[2:0];
    assign raddr = r_index[2:0];

    genvar i;
    generate
        for (i = 0; i < NWAY; i = i + 1) begin : inst_search
            always @(posedge clk) begin
                if (s0_fetch) begin
                    s0_odd_page_buffer[i] <= (inst_entry[i][`ENTRY_PS] == 6'd12) ? s0_odd_page : s0_vppn[8];
                    match0[i] <= (tlb_e[i] == 1'b1) && ((inst_entry[i][`ENTRY_PS] == 6'd12) ? s0_vppn == inst_entry[i][`ENTRY_VPPN] : s0_vppn[18:9] == inst_entry[i][`ENTRY_VPPN_H0]) && ((s0_asid == inst_entry[i][`ENTRY_ASID]) || inst_entry[i][`ENTRY_G]);
                end
                if (s1_fetch) begin
                    s1_odd_page_buffer[i] <= (data_entry[i][`ENTRY_PS] == 6'd12) ? s1_odd_page : s1_vppn[8];
                    match1[i] <= (tlb_e[i] == 1'b1) && ((data_entry[i][`ENTRY_PS] == 6'd12) ? s1_vppn == data_entry[i][`ENTRY_VPPN] : s1_vppn[18:9] == data_entry[i][`ENTRY_VPPN_H0]) && ((s1_asid == data_entry[i][`ENTRY_ASID]) || data_entry[i][`ENTRY_G]);
                end
            end
        end
    endgenerate

    assign s0_found = match0 != 4'b0;  //!(!match0);
    assign s1_found = match1 != 4'b0;  //!(!match1);
    generate
        for (genvar i = 0; i < NWAY; i = i + 1) begin
            always_comb begin
                if (match0[i] == 1'b1) begin
                    inst_index = i;
                    inst_odd_page = s0_odd_page_buffer[i];
                end else begin
                    inst_index = i;
                    inst_odd_page = 0;
                end
                if (match1[i] == 1'b1) begin
                    data_index = i;
                    data_odd_page = s1_odd_page_buffer[i];
                end else begin
                    data_index = i;
                    data_odd_page = 0;
                end
            end
        end
    endgenerate

    generate
        for (genvar i = 0; i < NWAY; i = i + 1) begin
            always_comb begin
                if (w_index[4:3] == i) begin
                    wen[i]   = we;
                    waddr[i] = w_index[2:0];
                    wdata[i] = write_port;
                end else begin
                    wen[i]   = 0;
                    waddr[i] = 0;
                    wdata[i] = 0;
                end
            end
        end
    endgenerate

    assign read_port = {tlb_e[r_index], rdata[r_index[4:3]][87:0]};

    assign {s0_index, s0_ps, s0_ppn, s0_v, s0_d, s0_mat, s0_plv} = inst_odd_page ? {inst_index,inst_addr, inst_entry[inst_index][`ENTRY_PS], inst_entry[inst_index][`ENTRY_PPN1], inst_entry[inst_index][`ENTRY_V1], inst_entry[inst_index][`ENTRY_D1], inst_entry[inst_index][`ENTRY_MAT1], inst_entry[inst_index][`ENTRY_PLV1]} :
                                                                {inst_index,inst_addr, inst_entry[inst_index][`ENTRY_PS], inst_entry[inst_index][`ENTRY_PPN0], inst_entry[inst_index][`ENTRY_V0], inst_entry[inst_index][`ENTRY_D0], inst_entry[inst_index][`ENTRY_MAT0], inst_entry[inst_index][`ENTRY_PLV0]};
    assign {s1_index, s1_ps, s1_ppn, s1_v, s1_d, s1_mat, s1_plv} = data_odd_page ? {data_index,data_addr, data_entry[data_index][`ENTRY_PS], data_entry[data_index][`ENTRY_PPN1], data_entry[data_index][`ENTRY_V1], data_entry[data_index][`ENTRY_D1], data_entry[data_index][`ENTRY_MAT1], data_entry[data_index][`ENTRY_PLV1]} :
                                                                {data_index,data_addr, data_entry[data_index][`ENTRY_PS], data_entry[data_index][`ENTRY_PPN0], data_entry[data_index][`ENTRY_V0], data_entry[data_index][`ENTRY_D0], data_entry[data_index][`ENTRY_MAT0], data_entry[data_index][`ENTRY_PLV0]};

    // //read port driven
    // assign read_port = {tlb_e[r_index], read_port_buffer[87:0]};
    //         always @(posedge clk) begin
    //             if (we && (w_index == i)) begin
    //                 tlb_e[i] <= write_port.e;
    //             end else if (inv_i.en) begin
    //                 // invalid search
    //                 if (inv_i.op == 5'd0 || inv_i.op == 5'd1) tlb_e[i] <= 1'b0;
    //                 else if (inv_i.op == 5'd2 && invtlbout[`ENTRY_G]) tlb_e[i] <= 1'b0;
    //                 else if (inv_i.op == 5'd3 && !invtlbout[`ENTRY_G]) tlb_e[i] <= 1'b0;
    //                 else if (inv_i.op == 5'd4 && !invtlbout[`ENTRY_G] && (invtlbout[`ENTRY_ASID] == inv_i.asid))
    //                     tlb_e[i] <= 1'b0;
    //                 else if (inv_i.op == 5'd5 && !invtlbout[`ENTRY_G] && (invtlbout[`ENTRY_ASID] == inv_i.asid) && 
    //                        ((invtlbout[`ENTRY_PS] == 6'd12) ? (invtlbout[`ENTRY_VPPN] == inv_i.vpn) : (invtlbout[`ENTRY_VPPN_H1] == inv_i.vpn[18:10])))
    //                     tlb_e[i] <= 1'b0;
    //                 else if (inv_i.op == 5'd6 && (invtlbout[`ENTRY_G] || (invtlbout[`ENTRY_ASID] == inv_i.asid)) && 
    //                        ((invtlbout[`ENTRY_PS] == 6'd12) ? (invtlbout[`ENTRY_VPPN] == inv_i.vpn) : (invtlbout[`ENTRY_VPPN_H1] == inv_i.vpn[18:10])))
    //                     tlb_e[i] <= 1'b0;
    //             end
    //         end
    //     end
    // endgenerate

endmodule
