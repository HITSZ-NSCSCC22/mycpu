`include "defines.sv"
`include "csr_defines.sv"
module cs_reg
    import csr_defines::*;
(
    input logic clk,
    input logic rst,

    input csr_write_signal write_signal_1,
    input csr_write_signal write_signal_2,

    input logic excp_flush,
    input logic ertn_flush,
    input logic [8:0] interrupt_i,
    input logic [31:0] era_i,
    input logic [8:0] esubcode_i,
    input logic [5:0] ecode_i,
    input logic va_error_i,
    input logic [31:0] bad_va_i,
    input logic tlbsrch_en,
    input logic tlbsrch_found,
    input logic [4:0] tlbsrch_index,
    input logic excp_tlbrefill,
    input logic excp_tlb,
    input logic [18:0] excp_tlb_vppn,

    input logic [13:0] raddr,
    output logic [`RegBus] rdata,

    //timer 64
    output logic [63:0] timer_64_o,
    output logic [31:0] tid_o,

    input logic llbit_i,
    input logic llbit_set_i,

    output logic llbit_o,
    output logic [18:0] vppn_o,

    output logic [1:0] plv_o,

    //to pc_logic
    output logic has_int,
    output logic [31:0] eentry_out,
    output logic [31:0] era_out,
    output logic [31:0] tlbrentry_out,

    //to tlb
    output logic [9:0] asid_out,
    output logic [4:0] rand_index,
    output logic [31:0] tlbehi_out,
    output logic [31:0] tlbelo0_out,
    output logic [31:0] tlbelo1_out,
    output logic [31:0] tlbidx_out,
    output logic pg_out,
    output logic da_out,
    output logic [31:0] dmw0_out,
    output logic [31:0] dmw1_out,
    output logic [1:0] datf_out,
    output logic [1:0] datm_out,
    output logic [5:0] ecode_out,
    //from tlb
    input logic tlbrd_en,
    input logic [31:0] tlbehi_in,
    input logic [31:0] tlbelo0_in,
    input logic [31:0] tlbelo1_in,
    input logic [31:0] tlbidx_in,
    input logic [9:0] asid_in
);

    logic [31:0] csr_crmd;
    logic [31:0] csr_prmd;
    logic [31:0] csr_ectl;
    logic [31:0] csr_estat;
    logic [31:0] csr_era;
    logic [31:0] csr_badv;
    logic [31:0] csr_eentry;
    logic [31:0] csr_tlbidx;
    logic [31:0] csr_tlbehi;
    logic [31:0] csr_tlbelo0;
    logic [31:0] csr_tlbelo1;
    logic [31:0] csr_tlbrentry;
    logic [31:0] csr_tid;
    logic [31:0] csr_tcfg;
    logic [31:0] csr_tval;
    logic [31:0] csr_cntc;
    logic [31:0] csr_ticlr;
    logic [31:0] csr_llbctl;
    logic [31:0] csr_asid;
    logic [31:0] csr_cpuid;
    logic [31:0] csr_pgdl;
    logic [31:0] csr_pgdh;
    logic [31:0] csr_save0;
    logic [31:0] csr_save1;
    logic [31:0] csr_save2;
    logic [31:0] csr_save3;
    logic [31:0] csr_dmw0;
    logic [31:0] csr_dmw1;
    logic [31:0] csr_brk;
    logic [31:0] csr_disable_cache;

    logic [31:0] csr_pgd;
    logic timer_en;
    logic [63:0] timer_64;

    logic llbit;

    logic eret_tlbrefill_excp;
    logic tlbrd_valid_wr_en;
    logic tlbrd_invalid_wr_en;
    logic no_forward;

    //选择有写入信号的进行赋值，同样假设不会有写冲突
    logic we;
    logic [13:0] waddr;
    logic [`RegBus] wdata;

    always @(*) begin
        if (rst) begin
            we = 1'b0;
            waddr = 14'b0;
            wdata = `ZeroWord;
        end else if (write_signal_1.we == 1'b1) begin
            we = write_signal_1.we;
            waddr = write_signal_1.addr;
            wdata = write_signal_1.data;
        end else if (write_signal_2.we == 1'b1) begin
            we = write_signal_2.we;
            waddr = write_signal_2.addr;
            wdata = write_signal_2.data;
        end else begin
            we = 1'b0;
            waddr = 14'b0;
            wdata = `ZeroWord;
        end
    end

    //data to fronted
    assign tlbrentry_out = csr_tlbrentry;
    assign no_forward   = !excp_tlbrefill && !(eret_tlbrefill_excp && ertn_flush) && !(we == 1'b1 && waddr == `CRMD);

    assign pg_out = excp_tlbrefill & 1'b0  |
                (eret_tlbrefill_excp && ertn_flush) & 1'b1 |
                (we == 1'b1 && waddr == `CRMD) & wdata[`PG] |
                no_forward & csr_crmd[`PG];

    assign da_out = excp_tlbrefill & 1'b1                      |
                (eret_tlbrefill_excp && ertn_flush) & 1'b0 |
                (we == 1'b1 && waddr == `CRMD)      & wdata[`DA] |
                no_forward     & csr_crmd[`DA];

    assign eret_tlbrefill_excp = csr_estat[`ECODE] == 6'h3f;

    assign tlbrd_valid_wr_en = tlbrd_en && !tlbidx_in[`NE];
    assign tlbrd_invalid_wr_en = tlbrd_en && tlbidx_in[`NE];

    assign dmw0_out = we == 1'b1 && waddr == `DMW0 ? wdata : csr_dmw0;
    assign dmw1_out = we == 1'b1 && waddr == `DMW1 ? wdata : csr_dmw1;

    assign ecode_out = csr_estat[`ECODE];
    assign datf_out = csr_crmd[`DATF];
    assign datm_out = csr_crmd[`DATM];

    assign has_int = ((csr_ectl[`LIE] & csr_estat[`IS]) != 13'b0) & csr_crmd[`IE];

    assign plv_o  = {2{excp_flush}} & 2'b0            |
                  {2{ertn_flush}} & csr_prmd[`PPLV] |
                  {2{(we == 1'b1 && waddr == `CRMD)  }} & wdata[`PLV]   |
                  {2{!excp_flush && !ertn_flush && !(we == 1'b1 && waddr == `CRMD)}} & csr_crmd[`PLV];

    assign rdata = {32{raddr == `CRMD  }}  & csr_crmd    |
                 {32{raddr == `PRMD  }}  & csr_prmd    |
                 {32{raddr == `ECTL  }}  & csr_ectl    |
                 {32{raddr == `ESTAT }}  & csr_estat   |
                 {32{raddr == `ERA   }}  & csr_era	   |
                 {32{raddr == `BADV  }}  & csr_badv    |
                 {32{raddr == `EENTRY}}  & csr_eentry  |
                 {32{raddr == `TLBIDX}}  & csr_tlbidx  |
                 {32{raddr == `TLBEHI}}  & csr_tlbehi  |
                 {32{raddr == `TLBELO0}} & csr_tlbelo0 |
                 {32{raddr == `TLBELO1}} & csr_tlbelo1 |
                 {32{raddr == `ASID  }}  & csr_asid    |
                 {32{raddr == `PGDL  }}  & csr_pgdl    |
                 {32{raddr == `PGDH  }}  & csr_pgdh    |
                 {32{raddr == `PGD   }}  & csr_pgd     |
                 {32{raddr == `CPUID }}  & csr_cpuid   |
                 {32{raddr == `SAVE0 }}  & csr_save0   |
                 {32{raddr == `SAVE1 }}  & csr_save1   |
                 {32{raddr == `SAVE2 }}  & csr_save2   |
                 {32{raddr == `SAVE3 }}  & csr_save3   |
                 {32{raddr == `TID   }}  & csr_tid     |
                 {32{raddr == `TCFG  }}  & csr_tcfg    |
                 {32{raddr == `CNTC  }}  & csr_cntc    |
                 {32{raddr == `TICLR }}  & csr_ticlr   |
                 {32{raddr == `LLBCTL}}  & {csr_llbctl[31:1], llbit} |
                 {32{raddr == `TVAL  }}  & csr_tval    |
                 {32{raddr == `TLBRENTRY}} & csr_tlbrentry   |
                 {32{raddr == `DMW0}}    & csr_dmw0    |
                 {32{raddr == `DMW1}}    & csr_dmw1    ;

    assign eentry_out = csr_eentry;
    assign era_out = csr_era;
    assign timer_64_o = timer_64 + {{32{csr_cntc[31]}}, csr_cntc};
    assign tid_o = csr_tid;
    assign llbit_o = llbit;
    assign asid_out = csr_asid[`TLB_ASID];
    assign vppn_o = (we && waddr == `TLBEHI) ? wdata[`VPPN] : csr_tlbehi[`VPPN];
    assign tlbehi_out = csr_tlbehi;
    assign tlbelo0_out = csr_tlbelo0;
    assign tlbelo1_out = csr_tlbelo1;
    assign tlbidx_out = csr_tlbidx;
    assign rand_index = timer_64[4:0];
    assign ecode_out = csr_estat[`ECODE];
    assign datf_out = csr_crmd[`DATF];
    assign datm_out = csr_crmd[`DATM];


    //crmd
    always @(posedge clk) begin
        if (rst) begin
            csr_crmd[`PLV]  <= 2'b0;
            csr_crmd[`IE]   <= 1'b0;
            csr_crmd[`DA]   <= 1'b1;
            csr_crmd[`PG]   <= 1'b0;
            csr_crmd[`DATF] <= 2'b0;
            csr_crmd[`DATM] <= 2'b0;
            csr_crmd[31:9]  <= 23'b0;
        end else if (excp_flush) begin
            csr_crmd[`PLV] <= 2'b0;
            csr_crmd[`IE]  <= 1'b0;
            if (excp_tlbrefill) begin
                csr_crmd[`DA] <= 1'b1;
                csr_crmd[`PG] <= 1'b0;
            end
        end else if (ertn_flush) begin
            csr_crmd[`PLV] <= csr_prmd[`PPLV];
            csr_crmd[`IE]  <= csr_prmd[`PIE];
            if (eret_tlbrefill_excp) begin
                csr_crmd[`DA] <= 1'b0;
                csr_crmd[`PG] <= 1'b1;
            end
        end else if (we == 1'b1 && waddr == `CRMD) begin
            csr_crmd[`PLV]  <= wdata[`PLV];
            csr_crmd[`IE]   <= wdata[`IE];
            csr_crmd[`DA]   <= wdata[`DA];
            csr_crmd[`PG]   <= wdata[`PG];
            csr_crmd[`DATF] <= wdata[`DATF];
            csr_crmd[`DATM] <= wdata[`DATM];
        end
    end

    //prmd
    always @(posedge clk) begin
        if (rst) begin
            csr_prmd[31:3] <= 29'b0;
        end else if (excp_flush) begin
            csr_prmd[`PPLV] <= csr_crmd[`PLV];
            csr_prmd[`PIE]  <= csr_crmd[`IE];
        end else if (we == 1'b1 && waddr == `PRMD) begin
            csr_prmd[`PPLV] <= wdata[`PPLV];
            csr_prmd[`PIE]  <= wdata[`PIE];
        end
    end

    //ectl
    always @(posedge clk) begin
        if (rst) csr_ectl <= 32'b0;
        else if (we == 1'b1 && waddr == `ECTL) csr_ectl[`LIE] <= wdata[`LIE];
    end

    //estate
    always @(posedge clk) begin
        if (rst) begin
            csr_estat[1:0] <= 2'b0;
            csr_estat[15:13] <= 3'b0;
            csr_estat[31] <= 1'b0;
            timer_en <= 1'b0;
        end else begin
            if (we == 1'b1 && waddr == `TICLR && wdata[`CLR]) csr_estat[11] <= 1'b0;
            else if (we == 1'b1 && waddr == `TCFG) timer_en <= wdata[`EN];
            else if (timer_en && (csr_tval == 32'b0)) begin
                csr_estat[11] <= 1'b1;
                timer_en      <= csr_tcfg[`PERIODIC];
            end
            csr_estat[10:2] <= interrupt_i;
            if (excp_flush) begin
                csr_estat[`ECODE] <= ecode_i;
                csr_estat[`ESUBCODE] <= esubcode_i;
            end else if (we == 1'b1 && waddr == `ESTAT) begin
                csr_estat[1:0] <= wdata[1:0];
            end
        end
    end

    //era
    always @(posedge clk) begin
        if (excp_flush) begin
            csr_era <= era_i;
        end else if (we == 1'b1 && waddr == `ERA) begin
            csr_era <= wdata;
        end
    end

    //badv
    always @(posedge clk) begin
        if (we == 1'b1 && waddr == `BADV) begin
            csr_badv <= wdata;
        end else if (va_error_i) begin
            csr_badv <= bad_va_i;
        end
    end

    //eentry
    always @(posedge clk) begin
        if (rst) begin
            csr_eentry[5:0] <= 6'b0;
        end else if (we == 1'b1 && waddr == `EENTRY) begin
            csr_eentry[31:6] <= wdata[31:6];
        end
    end

    //cpuid
    always @(posedge clk) begin
        if (rst) begin
            csr_cpuid <= 32'b0;
        end
    end

    //tval
    always @(posedge clk) begin
        if (we && waddr == `TCFG) begin
            csr_tval <= {wdata[`INITVAL], 2'b0};
        end else if (timer_en) begin
            if (csr_tval != 32'b0) begin
                csr_tval <= csr_tval - 32'b1;
            end else if (csr_tval == 32'b0) begin
                csr_tval <= csr_tcfg[`PERIODIC] ? {csr_tcfg[`INITVAL], 2'b0} : 32'hffffffff;
            end
        end
    end

    //save0
    always @(posedge clk) begin
        if (we == 1'b1 && waddr == `SAVE0) csr_save0 <= wdata;
    end

    //save1
    always @(posedge clk) begin
        if (we == 1'b1 && waddr == `SAVE1) csr_save1 <= wdata;
    end

    //save2
    always @(posedge clk) begin
        if (we == 1'b1 && waddr == `SAVE2) csr_save2 <= wdata;
    end

    //save3
    always @(posedge clk) begin
        if (we == 1'b1 && waddr == `SAVE3) csr_save3 <= wdata;
    end

    //pgdl
    always @(posedge clk) begin
        if (we == 1'b1 && waddr == `PGDL) csr_pgdl[`BASE] <= wdata[`BASE];
    end

    //pgdh
    always @(posedge clk) begin
        if (we == 1'b1 && waddr == `PGDH) csr_pgdh[`BASE] <= wdata[`BASE];
    end

    //tlbidx
    always @(posedge clk) begin
        if (rst) begin
            csr_tlbidx[23:5] <= 19'b0;
            csr_tlbidx[30]   <= 1'b0;
        end else if (we == 1'b1 && waddr == `TLBIDX) begin
            csr_tlbidx[`INDEX] <= wdata[`INDEX];
            csr_tlbidx[`PS]    <= wdata[`PS];
            csr_tlbidx[`NE]    <= wdata[`NE];
        end else if (tlbsrch_en) begin
            if (tlbsrch_found) begin
                csr_tlbidx[`INDEX] <= tlbsrch_index;
                csr_tlbidx[`NE]    <= 1'b0;
            end else begin
                csr_tlbidx[`NE] <= 1'b1;
            end
        end else if (tlbrd_valid_wr_en) begin
            csr_tlbidx[`PS] <= tlbidx_in[`PS];
            csr_tlbidx[`NE] <= tlbidx_in[`NE];
        end else if (tlbrd_invalid_wr_en) begin
            csr_tlbidx[`PS] <= 6'b0;
            csr_tlbidx[`NE] <= tlbidx_in[`NE];
        end
    end

    //tlbehi
    always @(posedge clk) begin
        if (rst) csr_tlbehi[12:0] <= 13'b0;
        else if (we == 1'b1 && waddr == `TLBEHI) csr_tlbehi[`VPPN] <= wdata[`VPPN];
        else if (tlbrd_valid_wr_en) csr_tlbehi[`VPPN] <= tlbehi_in[`VPPN];
        else if (tlbrd_invalid_wr_en) csr_tlbehi[`VPPN] <= 19'b0;
        else if (excp_tlb) csr_tlbehi[`VPPN] <= excp_tlb_vppn;
    end

    //tlbelo0
    always @(posedge clk) begin
        if (rst) csr_tlbelo0[7] <= 1'b0;
        else if (we == 1'b1 && waddr == `TLBELO0) begin
            csr_tlbelo0[`TLB_V]   <= wdata[`TLB_V];
            csr_tlbelo0[`TLB_D]   <= wdata[`TLB_D];
            csr_tlbelo0[`TLB_PLV] <= wdata[`TLB_PLV];
            csr_tlbelo0[`TLB_MAT] <= wdata[`TLB_MAT];
            csr_tlbelo0[`TLB_G]   <= wdata[`TLB_G];
            csr_tlbelo0[`TLB_PPN] <= wdata[`TLB_PPN];
        end else if (tlbrd_valid_wr_en) begin
            csr_tlbelo0[`TLB_V]   <= tlbelo0_in[`TLB_V];
            csr_tlbelo0[`TLB_D]   <= tlbelo0_in[`TLB_D];
            csr_tlbelo0[`TLB_PLV] <= tlbelo0_in[`TLB_PLV];
            csr_tlbelo0[`TLB_MAT] <= tlbelo0_in[`TLB_MAT];
            csr_tlbelo0[`TLB_G]   <= tlbelo0_in[`TLB_G];
            csr_tlbelo0[`TLB_PPN] <= tlbelo0_in[`TLB_PPN];
        end else if (tlbrd_invalid_wr_en) begin
            csr_tlbelo0[`TLB_V]   <= 1'b0;
            csr_tlbelo0[`TLB_D]   <= 1'b0;
            csr_tlbelo0[`TLB_PLV] <= 2'b0;
            csr_tlbelo0[`TLB_MAT] <= 2'b0;
            csr_tlbelo0[`TLB_G]   <= 1'b0;
            csr_tlbelo0[`TLB_PPN] <= 24'b0;
        end
    end

    //tlbelo1
    always @(posedge clk) begin
        if (rst) csr_tlbelo1[7] <= 1'b0;
        else if (we == 1'b1 && waddr == `TLBELO1) begin
            csr_tlbelo1[`TLB_V]   <= wdata[`TLB_V];
            csr_tlbelo1[`TLB_D]   <= wdata[`TLB_D];
            csr_tlbelo1[`TLB_PLV] <= wdata[`TLB_PLV];
            csr_tlbelo1[`TLB_MAT] <= wdata[`TLB_MAT];
            csr_tlbelo1[`TLB_G]   <= wdata[`TLB_G];
            csr_tlbelo1[`TLB_PPN] <= wdata[`TLB_PPN];
        end else if (tlbrd_valid_wr_en) begin
            csr_tlbelo1[`TLB_V]   <= tlbelo1_in[`TLB_V];
            csr_tlbelo1[`TLB_D]   <= tlbelo1_in[`TLB_D];
            csr_tlbelo1[`TLB_PLV] <= tlbelo1_in[`TLB_PLV];
            csr_tlbelo1[`TLB_MAT] <= tlbelo1_in[`TLB_MAT];
            csr_tlbelo1[`TLB_G]   <= tlbelo1_in[`TLB_G];
            csr_tlbelo1[`TLB_PPN] <= tlbelo1_in[`TLB_PPN];
        end else if (tlbrd_invalid_wr_en) begin
            csr_tlbelo1[`TLB_V]   <= 1'b0;
            csr_tlbelo1[`TLB_D]   <= 1'b0;
            csr_tlbelo1[`TLB_PLV] <= 2'b0;
            csr_tlbelo1[`TLB_MAT] <= 2'b0;
            csr_tlbelo1[`TLB_G]   <= 1'b0;
            csr_tlbelo1[`TLB_PPN] <= 24'b0;
        end
    end

    //asid
    always @(posedge clk) begin
        if (rst) csr_asid[31:10] <= 22'h280;
        else if (we == 1'b1 && waddr == `ASID) csr_asid[`TLB_ASID] <= wdata[`TLB_ASID];
        else if (tlbrd_valid_wr_en) csr_asid[`TLB_ASID] <= asid_in;
        else if (tlbrd_invalid_wr_en) csr_asid[`TLB_ASID] <= 10'b0;
    end

    //pgdl
    always @(posedge clk) begin
        if (we == 1'b1 && waddr == `PGDL) begin
            csr_pgdl[`BASE] <= wdata[`BASE];
        end
    end

    //pgdh
    always @(posedge clk) begin
        if (we == 1'b1 && waddr == `PGDH) begin
            csr_pgdh[`BASE] <= wdata[`BASE];
        end
    end

    //pgd
    assign csr_pgd = csr_badv[31] ? csr_pgdh : csr_pgdl;

    // llbctl
    always @(posedge clk) begin
        if (rst) begin
            csr_llbctl[`KLO] <= 1'b0;
            csr_llbctl[31:3] <= 29'b0;
            llbit <= 1'b0;
        end else if (ertn_flush) begin
            if (csr_llbctl[`KLO]) begin
                csr_llbctl[`KLO] <= 1'b0;
            end else begin
                llbit <= 1'b0;
            end
        end else if (we == 1'b1 && waddr == `LLBCTL) begin
            csr_llbctl[`KLO] <= wdata[`KLO];
            if (wdata[`WCLLB] == 1'b1) begin
                llbit <= 1'b0;
            end
        end else if (llbit_set_i) begin
            llbit <= llbit_i;
        end
    end

    //tlbrentry
    always @(posedge clk) begin
        if (rst) csr_tlbrentry[5:0] <= 6'b0;
        else if (we == 1'b1 && waddr == `TLBRENTRY)
            csr_tlbrentry[`TLBRENTRY_PA] <= wdata[`TLBRENTRY_PA];
    end


    //dmw0
    always @(posedge clk) begin
        if (rst) begin
            csr_dmw0[2:1]  <= 2'b0;
            csr_dmw0[24:6] <= 19'b0;
            csr_dmw0[28]   <= 1'b0;
        end else if (we == 1'b1 && waddr == `DMW0) begin
            csr_dmw0[`PLV0] <= wdata[`PLV0];
            csr_dmw0[`PLV3] <= wdata[`PLV3];
            csr_dmw0[`DMW_MAT] <= wdata[`DMW_MAT];
            csr_dmw0[`PSEG] <= wdata[`PSEG];
            csr_dmw0[`VSEG] <= wdata[`VSEG];
        end
    end

    //dmw1
    always @(posedge clk) begin
        if (rst) begin
            csr_dmw1[2:1]  <= 2'b0;
            csr_dmw1[24:6] <= 19'b0;
            csr_dmw1[28]   <= 1'b0;
        end else if (we == 1'b1 && waddr == `DMW1) begin
            csr_dmw1[`PLV0] <= wdata[`PLV0];
            csr_dmw1[`PLV3] <= wdata[`PLV3];
            csr_dmw1[`DMW_MAT] <= wdata[`DMW_MAT];
            csr_dmw1[`PSEG] <= wdata[`PSEG];
            csr_dmw1[`VSEG] <= wdata[`VSEG];
        end
    end


    //tid
    always @(posedge clk) begin
        if (rst) csr_tid <= 32'b0;
        else if (we == 1 && waddr == `TID) csr_tid <= wdata;
    end

    //tcfg
    always @(posedge clk) begin
        if (rst) csr_tcfg[`EN] <= 1'b0;
        else if (we == 1'b1 && waddr == `TCFG) begin
            csr_tcfg[`EN] <= wdata[`EN];
            csr_tcfg[`PERIODIC] <= wdata[`PERIODIC];
            csr_tcfg[`INITVAL] <= wdata[`INITVAL];
        end
    end

    //cntc
    always @(posedge clk) begin
        if (rst) begin
            csr_cntc <= 32'b0;
        end else if (we == 1'b1 && waddr == `CNTC) begin
            csr_cntc <= wdata;
        end
    end

    //ticlr
    always @(posedge clk) begin
        if (rst) csr_ticlr <= 32'b0;
    end

    //timer_64
    always @(posedge clk) begin
        if (rst) begin
            timer_64 <= 64'b0;
        end else begin
            timer_64 <= timer_64 + 1'b1;
        end
    end


    always @(posedge clk) begin
        if (rst) begin
            csr_brk <= 32'b0;
        end
        if (we == 1'b1 && waddr == `BRK) begin
            csr_brk <= wdata;
        end
    end

    //use for disable cache or enable cache
    always @(posedge clk) begin
        if (rst) begin
            csr_disable_cache <= 32'b0;
        end
        if (we == 1'b1 && waddr == `DISABLE_CACHE) begin
            csr_disable_cache <= wdata;
        end
    end

endmodule
