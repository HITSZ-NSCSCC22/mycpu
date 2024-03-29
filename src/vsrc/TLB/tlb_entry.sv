`include "TLB/tlb_types.sv"
`include "TLB/tlb_lutram.sv"
`include "core_config.sv"

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

    // invalid port
    input tlb_inv_t inv_i,
    // ack is pulled up when invalid done
    output logic inv_ack_o
);

    localparam NWAY = TLB_NWAY;
    localparam NSET = TLB_NSET;

    // Data structure
    logic [TLB_NUM-1:0] tlb_e;

    // Match index
    // next cycle after query request
    logic [NWAY-1:0] match0;
    logic [NWAY-1:0] match1;

    //inst search port 
    // same cycle
    logic inst_odd_page;
    logic [$clog2(NSET)-1:0] inst_addr;
    logic [`ENTRY_LEN-1:0] inst_entry[NWAY-1:0];
    // next cycle
    logic [$clog2(NWAY)-1:0] inst_index;
    logic [`ENTRY_LEN-1:0] inst_entry_buffer[NWAY-1:0];

    //data search port
    // same cycle
    logic data_odd_page;
    logic [$clog2(NSET)-1:0] data_addr;
    logic [`ENTRY_LEN-1:0] data_entry[NWAY-1:0];
    // next cycle
    logic [$clog2(NWAY)-1:0] data_index;
    logic [`ENTRY_LEN-1:0] data_entry_buffer[NWAY-1:0];

    //write port
    logic [NWAY-1:0] wen;
    logic [$clog2(NSET)-1:0] waddr[NWAY-1:0];
    logic [`ENTRY_LEN-1:0] wdata[NWAY-1:0];

    //read port
    logic [$clog2(NSET)-1:0] raddr;
    logic [`ENTRY_LEN-1:0] rdata[NWAY-1:0];

    // Invalid counter
    logic [$clog2(NSET)-1:0] inv_cnt;


    logic [NWAY-1:0] s0_odd_page_buffer;
    logic [NWAY-1:0] s1_odd_page_buffer;

    always_ff @(posedge clk) begin
        if (s0_fetch) inst_entry_buffer <= inst_entry;
        if (s1_fetch) data_entry_buffer <= data_entry;
    end


    for (genvar i = 0; i < NWAY; i = i + 1) begin
        tlb_lutram u_tlb_lutram (
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

    // Rand test require 4MB page support
    // for 4MB page, real vppn is vppn[18:8], vppn[8] is used as odd_page, so [11:9] is used as way index
    assign inst_addr = s0_vppn[11:9];
    assign data_addr = s1_vppn[11:9];

    always_comb begin
        if (inv_i.en == 1'b1) raddr = inv_cnt;
        else raddr = r_index[2:0];
    end

    generate
        for (genvar i = 0; i < NWAY; i = i + 1) begin : inst_data_search
            always @(posedge clk) begin
                if (s0_fetch) begin
                    s0_odd_page_buffer[i] <= (inst_entry[i][`ENTRY_PS] == 6'd12) ? s0_odd_page : s0_vppn[8];
                    match0[i] <= (tlb_e[(i * NSET) + inst_addr] == 1'b1) && ((inst_entry[i][`ENTRY_PS] == 6'd12) ? s0_vppn == inst_entry[i][`ENTRY_VPPN] : s0_vppn[18:9] == inst_entry[i][`ENTRY_VPPN_H0]) && ((s0_asid == inst_entry[i][`ENTRY_ASID]) || inst_entry[i][`ENTRY_G]);
                end
                if (s1_fetch) begin
                    s1_odd_page_buffer[i] <= (data_entry[i][`ENTRY_PS] == 6'd12) ? s1_odd_page : s1_vppn[8];
                    match1[i] <= (tlb_e[(i * NSET) + data_addr] == 1'b1) && ((data_entry[i][`ENTRY_PS] == 6'd12) ? s1_vppn == data_entry[i][`ENTRY_VPPN] : s1_vppn[18:9] == data_entry[i][`ENTRY_VPPN_H0]) && ((s1_asid == data_entry[i][`ENTRY_ASID]) || data_entry[i][`ENTRY_G]);
                end
            end
        end
    endgenerate

    // Way selection
    assign s0_found = match0 != 4'b0;  //!(!match0);
    assign s1_found = match1 != 4'b0;  //!(!match1);
    always_comb begin
        inst_index = 0;
        inst_odd_page = 0;
        data_index = 0;
        data_odd_page = 0;
        for (integer i = 0; i < NWAY; i = i + 1) begin
            if (match0[i] == 1'b1) begin
                inst_index = i[1:0];
                inst_odd_page = s0_odd_page_buffer[i];
            end
            if (match1[i] == 1'b1) begin
                data_index = i[1:0];
                data_odd_page = s1_odd_page_buffer[i];
            end
        end
    end

    // Write signal
    always_comb begin
        for (integer i = 0; i < NWAY; i = i + 1) begin
            if (w_index[4:3] == i[1:0]) begin
                wen[i] = we;
                waddr[i] = w_index[2:0];
                wdata[i] = {
                    write_port.ppn1,
                    write_port.plv1,
                    write_port.mat1,
                    write_port.d1,
                    write_port.v1,
                    write_port.ppn0,
                    write_port.plv0,
                    write_port.mat0,
                    write_port.d0,
                    write_port.v0,
                    write_port.vppn,
                    write_port.ps,
                    write_port.g,
                    write_port.asid,
                    1'b0  // TLB_E
                };
            end else begin
                wen[i]   = 0;
                waddr[i] = 0;
                wdata[i] = 0;
            end
        end
    end

    // Read signal, same cycle as input
    assign {read_port.ppn1,
                    read_port.plv1,
                    read_port.mat1,
                    read_port.d1,
                    read_port.v1,
                    read_port.ppn0,
                    read_port.plv0,
                    read_port.mat0,
                    read_port.d0,
                    read_port.v0,
                    read_port.vppn,
                    read_port.ps,
                    read_port.g,
                    read_port.asid,
                    read_port.e} = {
        rdata[r_index[4:3]][88:1], tlb_e[r_index]
    };

    // Inst & Data search output
    assign {s0_index, s0_ps, s0_ppn, s0_v, s0_d, s0_mat, s0_plv} = inst_odd_page ? {inst_index,inst_addr, 
                                                                inst_entry_buffer[inst_index][`ENTRY_PS], 
                                                                inst_entry_buffer[inst_index][`ENTRY_PPN1], 
                                                                inst_entry_buffer[inst_index][`ENTRY_V1], 
                                                                inst_entry_buffer[inst_index][`ENTRY_D1], 
                                                                inst_entry_buffer[inst_index][`ENTRY_MAT1],
                                                                inst_entry_buffer[inst_index][`ENTRY_PLV1]} :
                                                                {inst_index,inst_addr, 
                                                                inst_entry_buffer[inst_index][`ENTRY_PS], 
                                                                inst_entry_buffer[inst_index][`ENTRY_PPN0],
                                                                inst_entry_buffer[inst_index][`ENTRY_V0], 
                                                                inst_entry_buffer[inst_index][`ENTRY_D0], 
                                                                inst_entry_buffer[inst_index][`ENTRY_MAT0], 
                                                                inst_entry_buffer[inst_index][`ENTRY_PLV0]};
    assign {s1_index, s1_ps, s1_ppn, s1_v, s1_d, s1_mat, s1_plv} = data_odd_page ? {data_index,data_addr, 
                                                                data_entry_buffer[data_index][`ENTRY_PS], 
                                                                data_entry_buffer[data_index][`ENTRY_PPN1], 
                                                                data_entry_buffer[data_index][`ENTRY_V1],
                                                                data_entry_buffer[data_index][`ENTRY_D1], 
                                                                data_entry_buffer[data_index][`ENTRY_MAT1], 
                                                                data_entry_buffer[data_index][`ENTRY_PLV1]} :
                                                                {data_index,data_addr, 
                                                                data_entry_buffer[data_index][`ENTRY_PS], 
                                                                data_entry_buffer[data_index][`ENTRY_PPN0], 
                                                                data_entry_buffer[data_index][`ENTRY_V0], 
                                                                data_entry_buffer[data_index][`ENTRY_D0], 
                                                                data_entry_buffer[data_index][`ENTRY_MAT0], 
                                                                data_entry_buffer[data_index][`ENTRY_PLV0]};

    // Invalid counter
    always @(posedge clk) begin
        if (inv_i.en) begin
            inv_cnt <= inv_cnt + 1'b1;
        end else begin
            inv_cnt <= 0;
        end
    end
    assign inv_ack_o = inv_cnt == {$clog2(NSET) {1'b1}};


    always @(posedge clk) begin
        if (we) begin
            tlb_e[w_index] <= write_port.e;
        end else if (inv_i.en) begin
            // invalid search
            for (integer i = 0; i < NWAY; i = i + 1) begin
                if (inv_i.op == 5'd0 || inv_i.op == 5'd1) tlb_e[i*NSET+{29'b0, raddr}] <= 1'b0;
                else if (inv_i.op == 5'd2 && rdata[i][`ENTRY_G])
                    tlb_e[i*NSET+{29'b0, raddr}] <= 1'b0;
                else if (inv_i.op == 5'd3 && !rdata[i][`ENTRY_G])
                    tlb_e[i*NSET+{29'b0, raddr}] <= 1'b0;
                else if (inv_i.op == 5'd4 && !rdata[i][`ENTRY_G] && (rdata[i][`ENTRY_ASID] == inv_i.asid))
                    tlb_e[i*NSET+{29'b0, raddr}] <= 1'b0;
                else if (inv_i.op == 5'd5 && !rdata[i][`ENTRY_G] && (rdata[i][`ENTRY_ASID] == inv_i.asid) && 
                           ((rdata[i][`ENTRY_PS] == 6'd12) ? (rdata[i][`ENTRY_VPPN] == inv_i.vpn) : (rdata[i][`ENTRY_VPPN_H1] == inv_i.vpn[18:10])))
                    tlb_e[i*NSET+{29'b0, raddr}] <= 1'b0;
                else if (inv_i.op == 5'd6 && (rdata[i][`ENTRY_G] || (rdata[i][`ENTRY_ASID] == inv_i.asid)) && 
                           ((rdata[i][`ENTRY_PS] == 6'd12) ? (rdata[i][`ENTRY_VPPN] == inv_i.vpn) : (rdata[i][`ENTRY_VPPN_H1] == inv_i.vpn[18:10])))
                    tlb_e[i*NSET+{29'b0, raddr}] <= 1'b0;
            end
        end
    end


    //debug用的信号
`ifdef SIMULATION
    logic [18:0] inst_tlb_vppn  [NWAY-1:0];
    logic [ 9:0] inst_tlb_asid  [NWAY-1:0];
    logic        inst_tlb_g     [NWAY-1:0];
    logic [ 5:0] inst_tlb_ps    [NWAY-1:0];
    logic [19:0] inst_tlb_ppn0  [NWAY-1:0];
    logic [ 1:0] inst_tlb_plv0  [NWAY-1:0];
    logic [ 1:0] inst_tlb_mat0  [NWAY-1:0];
    logic        inst_tlb_d0    [NWAY-1:0];
    logic        inst_tlb_v0    [NWAY-1:0];
    logic [19:0] inst_tlb_ppn1  [NWAY-1:0];
    logic [ 1:0] inst_tlb_plv1  [NWAY-1:0];
    logic [ 1:0] inst_tlb_mat1  [NWAY-1:0];
    logic        inst_tlb_d1    [NWAY-1:0];
    logic        inst_tlb_v1    [NWAY-1:0];
    logic [18:0] data_tlb_vppn  [NWAY-1:0];
    logic [ 9:0] data_tlb_asid  [NWAY-1:0];
    logic        data_tlb_g     [NWAY-1:0];
    logic [ 5:0] data_tlb_ps    [NWAY-1:0];
    logic [19:0] data_tlb_ppn0  [NWAY-1:0];
    logic [ 1:0] data_tlb_plv0  [NWAY-1:0];
    logic [ 1:0] data_tlb_mat0  [NWAY-1:0];
    logic        data_tlb_d0    [NWAY-1:0];
    logic        data_tlb_v0    [NWAY-1:0];
    logic [19:0] data_tlb_ppn1  [NWAY-1:0];
    logic [ 1:0] data_tlb_plv1  [NWAY-1:0];
    logic [ 1:0] data_tlb_mat1  [NWAY-1:0];
    logic        data_tlb_d1    [NWAY-1:0];
    logic        data_tlb_v1    [NWAY-1:0];
    logic [18:0] write_tlb_vppn;
    logic [ 9:0] write_tlb_asid;
    logic        write_tlb_g;
    logic [ 5:0] write_tlb_ps;
    logic [19:0] write_tlb_ppn0;
    logic [ 1:0] write_tlb_plv0;
    logic [ 1:0] write_tlb_mat0;
    logic        write_tlb_d0;
    logic        write_tlb_v0;
    logic [19:0] write_tlb_ppn1;
    logic [ 1:0] write_tlb_plv1;
    logic [ 1:0] write_tlb_mat1;
    logic        write_tlb_d1;
    logic        write_tlb_v1;

    generate
        for (genvar i = 0; i < NWAY; i = i + 1) begin
            assign inst_tlb_vppn[i] = inst_entry[i][36:18];
            assign inst_tlb_asid[i] = inst_entry[i][10:1];
            assign inst_tlb_g[i] = inst_entry[i][11];
            assign inst_tlb_ps[i] = inst_entry[i][17:12];
            assign inst_tlb_ppn0[i] = inst_entry[i][62:43];
            assign inst_tlb_plv0[i] = inst_entry[i][42:41];
            assign inst_tlb_mat0[i] = inst_entry[i][40:39];
            assign inst_tlb_v0[i] = inst_entry[i][37];
            assign inst_tlb_d0[i] = inst_entry[i][38];
            assign inst_tlb_ppn1[i] = inst_entry[i][88:69];
            assign inst_tlb_plv1[i] = inst_entry[i][68:67];
            assign inst_tlb_mat1[i] = inst_entry[i][66:65];
            assign inst_tlb_v1[i] = inst_entry[i][63];
            assign inst_tlb_d1[i] = inst_entry[i][64];
            assign data_tlb_vppn[i] = data_entry[i][36:18];
            assign data_tlb_asid[i] = data_entry[i][10:1];
            assign data_tlb_g[i] = data_entry[i][11];
            assign data_tlb_ps[i] = data_entry[i][17:12];
            assign data_tlb_ppn0[i] = data_entry[i][62:43];
            assign data_tlb_plv0[i] = data_entry[i][42:41];
            assign data_tlb_mat0[i] = data_entry[i][40:39];
            assign data_tlb_v0[i] = data_entry[i][37];
            assign data_tlb_d0[i] = data_entry[i][38];
            assign data_tlb_ppn1[i] = data_entry[i][88:69];
            assign data_tlb_plv1[i] = data_entry[i][68:67];
            assign data_tlb_mat1[i] = data_entry[i][66:65];
            assign data_tlb_v1[i] = data_entry[i][63];
            assign data_tlb_d1[i] = data_entry[i][64];
        end
    endgenerate

    assign write_tlb_vppn = write_port.vppn;
    assign write_tlb_asid = write_port.asid;
    assign write_tlb_g = write_port.g;
    assign write_tlb_ps = write_port.ps;
    assign write_tlb_ppn0 = write_port.ppn0;
    assign write_tlb_plv0 = write_port.plv0;
    assign write_tlb_mat0 = write_port.mat0;
    assign write_tlb_v0 = write_port.v0;
    assign write_tlb_d0 = write_port.d0;
    assign write_tlb_ppn1 = write_port.ppn1;
    assign write_tlb_plv1 = write_port.plv1;
    assign write_tlb_mat1 = write_port.mat1;
    assign write_tlb_v1 = write_port.v1;
    assign write_tlb_d1 = write_port.d1;
`endif

endmodule
