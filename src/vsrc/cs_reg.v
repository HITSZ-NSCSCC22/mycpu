`include "defines.v"
`include "csr_defines.v"
module cs_reg (
    input wire clk,
    input wire rst，

    input wire[`AluOpBus] aluop_i,
    input wire[13:0] csr_num,
    input wire[1:0]exception_i,

    input wire we,
    input wire[`RegBus] wdata,

    output reg[`RegBus] rdata
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
reg [31:0] csr_asid;
reg [31:0] csr_cpuid;
reg [31:0] csr_pgdl;
reg [31:0] csr_pgdh;
reg [31:0] csr_save0;
reg [31:0] csr_save1;
reg [31:0] csr_save2;
reg [31:0] csr_save3;


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
    else if (excp_flush) begin
        csr_crmd[`PLV] <= 2'b0;
        csr_crmd[`IE] <= 1'b0;
        if (excp_tlbrefill) begin
            csr_crmd [`DA] <= 1'b1;
            csr_crmd [`PG] <= 1'b0;
        end
    end
    else if(exception_i)begin
        csr_crmd[`PLV] <= csr_prmd[`PPLV];
        csr_crmd[`IE] <= csr_prmd[`PIE];
        if(eret_tlbrefill_excp)begin
            csr_crmd[`DA] <= 1'b0;
            csr_crmd[`PG] <= 1'b1;
        end
    end 
    else if (we == 1'b1 && csr_num == `CRMD) begin
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
    else if (exception_i) begin
        csr_prmd[`PPLV] <= csr_crmd[`PLV];
        csr_prmd[`PIE] <= csr_crmd[`IE];
    end
    else if (we == 1'b1 && csr_num == `PRMD) begin
        csr_prmd[`PPLV] <= wdata[`PPLV];
        csr_prmd[`PIE] <= wdata[`PIE];
    end
end

//ectl
always @(posedge clk) begin
    if (rst) 
        csr_ectl <= 32'b0;
    else if(we == 1'b1 && csr_num == `ECTL)
        csr_ectl[`LIE] <= wdata[`LIE];
end

always @(posedge clk) begin
    
end

//era
always @(posedge clk) begin
    if (excp_flush) begin
        
    end
    else if (we == 1'b1 && csr_num == `ERA) begin
        csr_era <= wdata;
    end
end

//badv
always @(posedge clk) begin
    if (we == 1'b1 && csr_num == `BADV) begin
        csr_badv <= wdata;
    end
    else if (va_error_in) begin
        csr_badv <= bad_va_in;
    end
end

//eentry
always @(posedge clk) begin
    if (rst) begin
        csr_eentry[5:0] <= 6'b0;
    end
    else if (we == 1'b1 && csr_num == `EENTRY) begin
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
    if (we == 1'b1 && csr_num == `SAVE0) csr_save0 <= wdata;
end

//save1
always @(posedge clk) begin
    if (we == 1'b1 && csr_num == `SAVE1) csr_save1 <= wdata;
end

//save2
always @(posedge clk) begin
    if (we == 1'b1 && csr_num == `SAVE2) csr_save2 <= wdata;
end

//save3
always @(posedge clk) begin
    if (we == 1'b1 && csr_num == `SAVE3) csr_save3 <= wdata;
end

//pgdl
always @(posedge clk) begin
    if (we == 1'b1 && csr_num == `PGDL) csr_pgdl[`BASE] <= wr_data[`BASE];
end

//pgdh
always @(posedge clk) begin
    if (we == 1'b1 && csr_num == `PGDH) csr_pgdh[`BASE] <= wr_data[`BASE];
end
    
endmodule