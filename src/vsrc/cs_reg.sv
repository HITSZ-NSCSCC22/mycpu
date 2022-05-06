`timescale 1ns/1ns

`include "defines.sv"
`include "csr_defines.sv"
module cs_reg (
    input wire clk,
    input wire rst,

    input csr_write_signal write_signal_1,
    input csr_write_signal write_signal_2,


    input wire excp_flush,
    input wire ertn_flush,
    input wire [8:0] interrupt_i,
    input wire [31:0]era_i,
    input wire [8:0] esubcode_i,
    input wire [5:0] ecode_i,
    input wire va_error_i,
    input wire [31:0] bad_va_i,
    input wire tlbsrch_en,
    input wire tlbsrch_found,
    input wire [4:0] tlbsrch_index,
    input wire excp_tlbrefill,
    input wire excp_tlb,
    input wire [18:0] excp_tlb_vppn,

    input wire[13:0] raddr_1,
    output wire[`RegBus] rdata_1,
    input wire[13:0] raddr_2,
    output wire[`RegBus] rdata_2,

    input wire llbit_i,
    input wire llbit_set_i,

    output wire llbit_o,
    output wire[18:0]vppn_o,

    //to pc_reg
    output wire has_int,
    output wire[31:0] eentry_out,
    output wire[31:0] era_out,
    output wire[31:0] tlbrentry_out,

    //to tlb
    output wire[ 9:0] asid_out,
    output wire[ 4:0] rand_index,
    output wire[31:0] tlbehi_out,
    output wire[31:0] tlbelo0_out,
    output wire[31:0] tlbelo1_out,
    output wire[31:0] tlbidx_out,
    output wire pg_out,
    output wire da_out,
    output wire[31:0] dmw0_out,
    output wire[31:0] dmw1_out,
    output wire[1:0] datf_out,
    output wire[1:0] datm_out,
    output wire[5:0] ecode_out,
    //from tlb
    input wire tlbrd_en,
    input wire[31:0] tlbehi_in,
    input wire[31:0] tlbelo0_in,
    input wire[31:0] tlbelo1_in,
    input wire[31:0] tlbidx_in,
    input wire[ 9:0] asid_in,

    //csr output for difftest
    output [831:0] csr_diff
);

reg [31:0] csr_crmd;
reg [31:0] csr_prmd;
reg [31:0] csr_ectl;
reg [31:0] csr_estat;
reg [31:0] csr_era;
reg [31:0] csr_badv;
reg [31:0] csr_eentry;
reg [31:0] csr_tlbidx;
reg [31:0] csr_tlbehi;
reg [31:0] csr_tlbelo0;
reg [31:0] csr_tlbelo1;
reg [31:0] csr_tlbrentry;
reg [31:0] csr_tid;
reg [31:0] csr_tcfg;
reg [31:0] csr_tval;
reg [31:0] csr_cntc;
reg [31:0] csr_ticlr;
reg [31:0] csr_llbctl;
reg [31:0] csr_asid;
reg [31:0] csr_cpuid;
reg [31:0] csr_pgdl;
reg [31:0] csr_pgdh;
reg [31:0] csr_save0;
reg [31:0] csr_save1;
reg [31:0] csr_save2;
reg [31:0] csr_save3;
reg [31:0] csr_dmw0;
reg [31:0] csr_dmw1;

wire [31:0] csr_pgd;
reg timer_en;
reg [63:0] timer_64;

reg llbit;

wire eret_tlbrefill_excp;
wire tlbrd_valid_wr_en;
wire tlbrd_invalid_wr_en;
wire no_forward;

//选择有写入信号的进行赋值，同样假设不会有写冲突
reg we;
reg [13:0]waddr;
reg [`RegBus] wdata;

always @(*) begin
    if(rst)begin
        we = 1'b0;
        waddr = 14'b0;
        wdata = `ZeroWord;
    end
    else if(write_signal_1.we == 1'b1)begin
        we = write_signal_1.we;
        waddr = write_signal_1.addr;
        wdata = write_signal_1.data;
    end
    else if(write_signal_2.we == 1'b1)begin
        we = write_signal_2.we;
        waddr = write_signal_2.addr;
        wdata = write_signal_2.data;
    end
    else begin
        we = 1'b0;
        waddr = 14'b0;
        wdata = `ZeroWord;
    end
end


//csr_difftest output
assign csr_diff = {csr_crmd,csr_prmd,csr_ectl,csr_estat,csr_era,csr_badv,csr_eentry,csr_tlbidx,
                   csr_tlbehi,csr_tlbelo0,csr_tlbelo1,csr_asid,csr_save0,csr_save1,csr_save2,
                   csr_save3,csr_tid,csr_tcfg,csr_tval,csr_ticlr,{csr_llbctl[31:1], llbit},
                   csr_tlbrentry,csr_dmw0,csr_dmw1,csr_pgdl,csr_pgdh };
//data to pc_reg
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

assign tlbrd_valid_wr_en  = tlbrd_en && !tlbidx_in[`NE];
assign tlbrd_invalid_wr_en = tlbrd_en &&  tlbidx_in[`NE];


assign dmw0_out = we == 1'b1 && waddr == `DMW0 ? wdata : csr_dmw0;
assign dmw1_out = we == 1'b1 && waddr == `DMW1 ? wdata : csr_dmw1;

assign has_int = ((csr_ectl[`LIE] & csr_estat[`IS]) != 13'b0) & csr_crmd[`IE];

assign plv_out  = {2{excp_flush}} & 2'b0            |
                  {2{ertn_flush}} & csr_prmd[`PPLV] |
                  {2{(we == 1'b1 && waddr == `CRMD)  }} & wdata[`PLV]   |
                  {2{!excp_flush && !ertn_flush && !(we == 1'b1 && waddr == `CRMD)}} & csr_crmd[`PLV];

  assign rdata_1 = {32{raddr_1 == `CRMD  }}  & csr_crmd    |
                 {32{raddr_1 == `PRMD  }}  & csr_prmd    |
                 {32{raddr_1 == `ECTL  }}  & csr_ectl    |
                 {32{raddr_1 == `ESTAT }}  & csr_estat   |
                 {32{raddr_1 == `ERA   }}  & csr_era	   |
                 {32{raddr_1 == `BADV  }}  & csr_badv    |
                 {32{raddr_1 == `EENTRY}}  & csr_eentry  |
                 {32{raddr_1 == `TLBIDX}}  & csr_tlbidx  |
                 {32{raddr_1 == `TLBEHI}}  & csr_tlbehi  |
                 {32{raddr_1 == `TLBELO0}} & csr_tlbelo0 |
                 {32{raddr_1 == `TLBELO1}} & csr_tlbelo1 |
                 {32{raddr_1 == `ASID  }}  & csr_asid    |
                 {32{raddr_1 == `PGDL  }}  & csr_pgdl    |
                 {32{raddr_1 == `PGDH  }}  & csr_pgdh    |
                 {32{raddr_1 == `PGD   }}  & csr_pgd     |
                 {32{raddr_1 == `CPUID }}  & csr_cpuid   |
                 {32{raddr_1 == `SAVE0 }}  & csr_save0   |
                 {32{raddr_1 == `SAVE1 }}  & csr_save1   |
                 {32{raddr_1 == `SAVE2 }}  & csr_save2   |
                 {32{raddr_1 == `SAVE3 }}  & csr_save3   |
                 {32{raddr_1 == `TID   }}  & csr_tid     |
                 {32{raddr_1 == `TCFG  }}  & csr_tcfg    |
                 {32{raddr_1 == `CNTC  }}  & csr_cntc    |
                 {32{raddr_1 == `TICLR }}  & csr_ticlr   |
                 {32{raddr_1 == `LLBCTL}}  & {csr_llbctl[31:1], llbit} |
                 {32{raddr_1 == `TVAL  }}  & csr_tval    |
                 {32{raddr_1 == `TLBRENTRY}} & csr_tlbrentry   |
                 {32{raddr_1 == `DMW0}}    & csr_dmw0    |
                 {32{raddr_1 == `DMW1}}    & csr_dmw1    ;

    assign rdata_2 = {32{raddr_2 == `CRMD  }}  & csr_crmd    |
                 {32{raddr_2 == `PRMD  }}  & csr_prmd    |
                 {32{raddr_2 == `ECTL  }}  & csr_ectl    |
                 {32{raddr_2 == `ESTAT }}  & csr_estat   |
                 {32{raddr_2 == `ERA   }}  & csr_era	   |
                 {32{raddr_2 == `BADV  }}  & csr_badv    |
                 {32{raddr_2 == `EENTRY}}  & csr_eentry  |
                 {32{raddr_2 == `TLBIDX}}  & csr_tlbidx  |
                 {32{raddr_2 == `TLBEHI}}  & csr_tlbehi  |
                 {32{raddr_2 == `TLBELO0}} & csr_tlbelo0 |
                 {32{raddr_2 == `TLBELO1}} & csr_tlbelo1 |
                 {32{raddr_2 == `ASID  }}  & csr_asid    |
                 {32{raddr_2 == `PGDL  }}  & csr_pgdl    |
                 {32{raddr_2 == `PGDH  }}  & csr_pgdh    |
                 {32{raddr_2 == `PGD   }}  & csr_pgd     |
                 {32{raddr_2 == `CPUID }}  & csr_cpuid   |
                 {32{raddr_2 == `SAVE0 }}  & csr_save0   |
                 {32{raddr_2 == `SAVE1 }}  & csr_save1   |
                 {32{raddr_2 == `SAVE2 }}  & csr_save2   |
                 {32{raddr_2 == `SAVE3 }}  & csr_save3   |
                 {32{raddr_2 == `TID   }}  & csr_tid     |
                 {32{raddr_2 == `TCFG  }}  & csr_tcfg    |
                 {32{raddr_2 == `CNTC  }}  & csr_cntc    |
                 {32{raddr_2 == `TICLR }}  & csr_ticlr   |
                 {32{raddr_2 == `LLBCTL}}  & {csr_llbctl[31:1], llbit} |
                 {32{raddr_2 == `TVAL  }}  & csr_tval    |
                 {32{raddr_2 == `TLBRENTRY}} & csr_tlbrentry   |
                 {32{raddr_2 == `DMW0}}    & csr_dmw0    |
                 {32{raddr_2 == `DMW1}}    & csr_dmw1    ;


//crmd
always @(posedge clk) begin
    if (rst) begin
        csr_crmd[`PLV] <= 2'b0;
        csr_crmd[`IE] <= 1'b0;
        csr_crmd[`DA] <= 1'b1;
        csr_crmd[`PG] <= 1'b0;
        csr_crmd[`DATF] <= 2'b0;
        csr_crmd[`DATM] <= 2'b0;
        csr_crmd[31:9] <= 23'b0;
    end
    else if (ertn_flush) begin
        csr_crmd[`PLV] <= 2'b0;
        csr_crmd[`IE] <= 1'b0;
        if (excp_tlbrefill) begin
            csr_crmd [`DA] <= 1'b1;
            csr_crmd [`PG] <= 1'b0;
        end
    end
    else if(excp_flush)begin
        csr_crmd[`PLV] <= csr_prmd[`PPLV];
        csr_crmd[`IE] <= csr_prmd[`PIE];
        if(eret_tlbrefill_excp)begin
            csr_crmd[`DA] <= 1'b0;
            csr_crmd[`PG] <= 1'b1;
        end
    end 
    else if (we == 1'b1 && waddr == `CRMD) begin
        csr_crmd[`PLV] <= wdata[`PLV];
        csr_crmd[`IE] <= wdata[`IE];
        csr_crmd[`DA] <= wdata[`DA];
        csr_crmd[`PG] <= wdata[`PG];
        csr_crmd[`DATF] <= wdata[`DATF];
        csr_crmd[`DATM] <= wdata[`DATM];
    end
end

//prmd
always @(posedge clk) begin
    if (rst) begin
        csr_prmd[31:3] <= 29'b0;
    end
    else if (excp_flush) begin
        csr_prmd[`PPLV] <= csr_crmd[`PLV];
        csr_prmd[`PIE] <= csr_crmd[`IE];
    end
    else if (we == 1'b1 && waddr == `PRMD) begin
        csr_prmd[`PPLV] <= wdata[`PPLV];
        csr_prmd[`PIE] <= wdata[`PIE];
    end
end

//ectl
always @(posedge clk) begin
    if (rst) 
        csr_ectl <= 32'b0;
    else if(we == 1'b1 && waddr == `ECTL)
        csr_ectl[`LIE] <= wdata[`LIE];
end

always @(posedge clk) begin
    
end

//estate
always @(posedge clk) begin
    if(rst)begin
        csr_estat[1:0] <= 2'b0; 
        csr_estat[15:13] <= 3'b0;
        csr_estat[31] <= 1'b0;
        timer_en <= 1'b0;
    end
    else begin
        if (we == 1'b1 && waddr == `TICLR && wdata[`CLR]) 
            csr_estat[11] <= 1'b0;
        else if (we == 1'b1 && waddr == `TCFG) 
            timer_en <= wdata[`EN];
        else if (timer_en && (csr_tval == 32'b0)) begin
            csr_estat[11] <= 1'b1;
            timer_en      <= csr_tcfg[`PERIODIC];
        end
        csr_estat[10:2] <= interrupt_i;
        if (excp_flush) begin
            csr_estat[`ECODE] <= ecode_i;
            csr_estat[`ESUBCODE] <= esubcode_i;
        end
        else if (we == 1'b1 && waddr == `ESTAT) begin
            csr_estat[      1:0] <= wdata[      1:0];
        end
    end
end

//era
always @(posedge clk) begin
    if (excp_flush) begin
        csr_era <= era_i;
    end
    else if (we == 1'b1 && waddr == `ERA) begin
        csr_era <= wdata;
    end
end

//badv
always @(posedge clk) begin
    if (we == 1'b1 && waddr == `BADV) begin
        csr_badv <= wdata;
    end
    else if (va_error_i) begin
        csr_badv <= bad_va_i;
    end
end

//eentry
always @(posedge clk) begin
    if (rst) begin
        csr_eentry[5:0] <= 6'b0;
    end
    else if (we == 1'b1 && waddr == `EENTRY) begin
        csr_eentry[31:6] <= wdata[31:6];
    end
end

//cpuid
always @(posedge clk) begin
    if (rst) begin
        csr_cpuid <= 32'b0;
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
    if(rst)begin
        csr_tlbidx[23:5] <= 19'b0;
        csr_tlbidx[30] <= 1'b0;
    end
    else if (we == 1'b1 && waddr == `TLBIDX) begin
        csr_tlbidx[`INDEX] <= wdata[`INDEX];
        csr_tlbidx[`PS]    <= wdata[`PS];
        csr_tlbidx[`NE]    <= wdata[`NE];
    end
    else if (tlbsrch_en) begin
        if (tlbsrch_found) begin
            csr_tlbidx[`INDEX] <= tlbsrch_index;
            csr_tlbidx[`NE]    <= 1'b0;
        end
        else begin
            csr_tlbidx[`NE] <= 1'b1;
        end
    end
    else if (tlbrd_en && !tlbidx_in[`NE]) begin
        csr_tlbidx[`PS] <= tlbidx_in[`PS];
        csr_tlbidx[`NE] <= tlbidx_in[`NE];
    end
    else if (tlbrd_en &&  tlbidx_in[`NE]) begin
        csr_tlbidx[`NE] <= tlbidx_in[`NE];
    end
end

//tlbehi
always @(posedge clk) begin
    if(rst)
        csr_tlbehi[12:0] <= 13'b0;
    else if(we == 1'b1 && waddr == `TLBEHI)
        csr_tlbehi[`VPPN] <= wdata[`VPPN];
    else if(excp_tlb)
        csr_tlbehi[`VPPN] <= excp_tlb_vppn;
end

//tlbelo0
always @(posedge clk) begin
    if(rst)
        csr_tlbelo0[7] <= 1'b0;
    else if(we == 1'b1 && waddr == `TLBELO0)begin
        csr_tlbelo0[`TLB_V] <= wdata[`TLB_V];
        csr_tlbelo0[`TLB_D] <= wdata[`TLB_D];
        csr_tlbelo0[`TLB_PLV] <= wdata[`TLB_PLV];
        csr_tlbelo0[`TLB_MAT] <= wdata[`TLB_MAT];
        csr_tlbelo0[`TLB_G] <= wdata[`TLB_G];
        csr_tlbelo0[`TLB_PPN] <= wdata[`TLB_PPN];
    end 
    else if (tlbrd_valid_wr_en) begin
        csr_tlbelo0[`TLB_V] <= tlbelo0_in[`TLB_V];
        csr_tlbelo0[`TLB_D] <= tlbelo0_in[`TLB_D];
        csr_tlbelo0[`TLB_PLV] <= tlbelo0_in[`TLB_PLV];
        csr_tlbelo0[`TLB_MAT] <= tlbelo0_in[`TLB_MAT];
        csr_tlbelo0[`TLB_G] <= tlbelo0_in[`TLB_G];
        csr_tlbelo0[`TLB_PPN] <= tlbelo0_in[`TLB_PPN];
    end
end

//tlbelo1
always @(posedge clk) begin
    if(rst)
        csr_tlbelo1[7] <= 1'b0;
    else if(we == 1'b1 && waddr == `TLBELO1)begin
        csr_tlbelo1[`TLB_V] <= wdata[`TLB_V];
        csr_tlbelo1[`TLB_D] <= wdata[`TLB_D];
        csr_tlbelo1[`TLB_PLV] <= wdata[`TLB_PLV];
        csr_tlbelo1[`TLB_MAT] <= wdata[`TLB_MAT];
        csr_tlbelo1[`TLB_G] <= wdata[`TLB_G];
        csr_tlbelo1[`TLB_PPN] <= wdata[`TLB_PPN];
    end 
    else if (tlbrd_valid_wr_en) begin
        csr_tlbelo1[`TLB_V] <= tlbelo1_in[`TLB_V];
        csr_tlbelo1[`TLB_D] <= tlbelo1_in[`TLB_D];
        csr_tlbelo1[`TLB_PLV] <= tlbelo1_in[`TLB_PLV];
        csr_tlbelo1[`TLB_MAT] <= tlbelo1_in[`TLB_MAT];
        csr_tlbelo1[`TLB_G] <= tlbelo1_in[`TLB_G];
        csr_tlbelo1[`TLB_PPN] <= tlbelo1_in[`TLB_PPN];
    end
end

//asid
always @(posedge clk) begin
    if(rst)
        csr_asid[31:10] <= 22'h280;
    else if(we == 1'b1 && waddr == `ASID)
        csr_asid[`TLB_ASID] <= wdata[`TLB_ASID];
    else if(tlbrd_valid_wr_en)
        csr_asid[`TLB_ASID] <= asid_in;
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

//llbctl
always @(posedge clk) begin
    if (rst) begin
        csr_llbctl[`KLO] <= 1'b0;
        csr_llbctl[31:3] <= 29'b0;
        llbit <= 1'b0;
    end 
    else if (ertn_flush) begin
        if (csr_llbctl[`KLO]) begin
            csr_llbctl[`KLO] <= 1'b0;
        end
        else begin
            llbit <= 1'b0;
        end
    end
    else if (we == 1'b1 && waddr == `LLBCTL) begin 
        csr_llbctl[  `KLO] <= wdata[  `KLO];
        if (wdata[`WCLLB] == 1'b1) begin
            llbit <= 1'b0;
        end
    end
    else if (llbit_set_i) begin
        llbit <= llbit_i;
    end
end

//tlbrentry
always @(posedge clk) begin
    if(rst)
        csr_tlbrentry[5:0] <= 6'b0;
    else if(we == 1'b1 && waddr == `TLBRENTRY)
        csr_tlbrentry[`TLBRENTRY] <= wdata[`TLBRENTRY_PA];
end


//dmw0
always @(posedge clk) begin
    if(rst)begin
        csr_dmw0[2:1] <= 2'b0;
        csr_dmw0[24:6] <= 19'b0;
        csr_dmw0[28] <= 1'b0;
    end
    else if(we == 1'b1 && waddr == `DMW0)begin
        csr_dmw0[`PLV0] <= wdata[`PLV0];
        csr_dmw0[`PLV3] <= wdata[`PLV3];
        csr_dmw0[`DMW_MAT] <= wdata[`DMW_MAT];
        csr_dmw0[`PSEG] <= wdata[`PSEG];
        csr_dmw0[`VSEG] <= wdata[`VSEG];
    end
end

//dmw1
always @(posedge clk) begin
    if(rst)begin
        csr_dmw1[2:1] <= 2'b0;
        csr_dmw1[24:6] <= 19'b0;
        csr_dmw1[28] <= 1'b0;
    end
    else if(we == 1'b1 && waddr == `DMW0)begin
        csr_dmw1[`PLV0] <= wdata[`PLV0];
        csr_dmw1[`PLV3] <= wdata[`PLV3];
        csr_dmw1[`DMW_MAT] <= wdata[`DMW_MAT];
        csr_dmw1[`PSEG] <= wdata[`PSEG];
        csr_dmw1[`VSEG] <= wdata[`VSEG];
    end
end


//tid
always @(posedge clk) begin
    if(rst)
        csr_tid <= 32'b0;
    else if(we == 1 && waddr == `TID)
        csr_tid <= wdata;
end

//tcfg
always @(posedge clk) begin
    if(rst)
        csr_tcfg[`EN] <= 1'b0;
    else if(we == 1'b1 && waddr == `TCFG)begin
        csr_tcfg[`EN] <= wdata[`EN];
        csr_tcfg[`PERIODIC] <= wdata[`PERIODIC];
        csr_tcfg[ `INITVAL] <= wdata[ `INITVAL];
    end
end

//cntc
always @(posedge clk) begin
    if (rst) begin
        csr_cntc <= 32'b0;
    end
    else if (we == 1'b1 && waddr == `CNTC) begin
        csr_cntc <= wdata;
    end
end

//tval
always @(posedge clk) begin
    if(rst)
        csr_ticlr <= 32'b0;
end

//llbitc
always @(posedge clk) begin
    if(rst)begin
        csr_llbctl[`KLO] <= 1'b0;
        csr_llbctl[31:3] <= 29'b0;
        llbit <= 1'b0;
    end
    else if (ertn_flush) begin
        if (csr_llbctl[`KLO]) csr_llbctl[`KLO] <= 1'b0;
        else llbit <= 1'b0;
    end
    else if (we == 1'b1 && waddr == `LLBCTL) begin 
        csr_llbctl[`KLO] <= wdata[`KLO];
        if (wdata[`WCLLB] == 1'b1)llbit <= 1'b0;
    end
    else if (llbit_set_i) llbit <= llbit_i;

end


    
endmodule