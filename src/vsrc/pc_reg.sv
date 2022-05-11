`include "defines.sv"
`include "csr_defines.sv"
module pc_reg (
    input wire clk,
    input wire rst,
    input wire stall1,
    input wire stall2,

    input wire branch_flag_i_1,
    input wire [`RegBus] branch_target_address_1,

    input wire branch_flag_i_2,
    input wire [`RegBus] branch_target_address_2,

    input wire flush,
    input wire excp_flush,
    input wire ertn_flush,
    input wire excp_tlbrefill,
    input wire [`InstAddrBus] new_pc,
    input wire idle_flush,
    input wire [`InstAddrBus] idle_pc,

    output reg [`InstAddrBus] pc_1,
    output reg [`InstAddrBus] pc_2,
    output reg ce,

    output wire excp_o,
    output wire [3:0] excp_num_o,

    //from csr
    input wire csr_pg,
    input wire csr_da,
    input wire [31:0] csr_dmw0,
    input wire [31:0] csr_dmw1,
    input wire [1:0] csr_plv,
    input wire [1:0] csr_datf,
    input wire disable_cache,
    input wire [`RegBus] csr_eentry,
    input wire [`RegBus] csr_era,
    input wire [`RegBus] csr_tlbrentry,

    //from tlb
    input wire inst_tlb_found,
    input wire inst_tlb_v,
    input wire inst_tlb_d,
    input wire [1:0] inst_tlb_mat,
    input wire [1:0] inst_tlb_plv,

    //to tlb
    output wire [31:0] inst_addr,
    output wire inst_addr_trans_en,
    output wire dmw0_en,
    output wire dmw1_en

);

    reg if_valid;
    wire if_ready_go;
    wire if_allowin;
    wire to_if_valid;
    wire pif_ready_go;
    wire [31:0] seq_pc;
    wire [31:0] nextpc;
    wire [31:0] real_nextpc;
    wire pif_excp_adef;
    wire if_excp_tlbr;
    wire if_excp_pif;
    wire if_excp_ppi;
    reg if_excp;
    reg if_excp_num;
    wire excp;
    wire [3:0] excp_num;
    wire pif_excp;
    wire pif_excp_num;
    wire flush_sign;
    reg [31:0] inst_rd_buff;
    reg inst_buff_enable;
    wire da_mode;
    wire flush_inst_delay;
    wire flush_inst_go_dirt;
    wire fetch_btb_target;
    reg idle_lock;
    wire tlb_excp_lock_pc;
    wire if_excp_adef;

    assign inst_addr_trans_en = csr_pg && !csr_da && !dmw0_en && !dmw1_en;

    assign dmw0_en = ((csr_dmw0[`PLV0] && csr_plv == 2'd0) || (csr_dmw0[`PLV3] && csr_plv == 2'd3)) && (pc_1[31:29] == csr_dmw0[`VSEG]);
    assign dmw1_en = ((csr_dmw1[`PLV0] && csr_plv == 2'd0) || (csr_dmw1[`PLV3] && csr_plv == 2'd3)) && (pc_2[31:29] == csr_dmw1[`VSEG]);


    //异常处理

    //未找到tlb
    assign if_excp_tlbr = !inst_tlb_found && inst_addr_trans_en;
    //load操作页无效
    assign if_excp_pif = !inst_tlb_v && inst_addr_trans_en;
    //页特权不合法
    assign if_excp_ppi = (csr_plv > inst_tlb_plv) && inst_addr_trans_en;
    //取指地址错误
    assign if_excp_adef = (pc_1[31] || pc_2[31]) && (csr_plv == 2'd3) && inst_addr_trans_en;


    assign excp_o = if_excp || if_excp_tlbr || if_excp_pif || if_excp_ppi || if_excp_adef;
    assign excp_num_o = {if_excp_ppi, if_excp_pif, if_excp_tlbr, if_excp_num || if_excp_adef};


    always @(posedge clk) begin
        if (ce == `ChipDisable) pc_1 <= 32'h1c000000;
        else if (idle_flush) pc_1 <= idle_pc;
        else if (flush == 1'b1) pc_1 <= new_pc;
        else if(stall1 == `Stop) // Hold output
        begin
            pc_1 <= pc_1;
        end else begin
            if (branch_flag_i_1 == `Branch) pc_1 <= branch_target_address_1;
            else if (branch_flag_i_2 == `Branch) pc_1 <= branch_target_address_2;
            else if (excp_flush && !excp_tlbrefill) pc_1 <= csr_eentry;
            else if (excp_flush && excp_tlbrefill) pc_1 <= csr_tlbrentry;
            else if (ertn_flush) pc_1 <= csr_era;
            else pc_1 <= pc_1 + 32'h8;
        end
    end

    always @(posedge clk) begin
        if (ce == `ChipDisable) pc_2 <= 32'h1c000004;
        else if (idle_flush) pc_2 <= idle_pc + 4'h4;
        else if (flush == 1'b1) pc_2 <= new_pc + 4'h4;
        else if(stall2 == `Stop) // Hold output
        begin
            pc_2 <= pc_2;
        end else begin
            if (branch_flag_i_1 == `Branch) pc_2 <= branch_target_address_1 + 4'h4;
            else if (branch_flag_i_2 == `Branch) pc_2 <= branch_target_address_2 + 4'h4;
            else if (excp_flush && !excp_tlbrefill) pc_2 <= csr_eentry + 4'h4;
            else if (excp_flush && excp_tlbrefill) pc_2 <= csr_tlbrentry + 4'h4;
            else if (ertn_flush) pc_2 <= csr_era + 4'h4;
            else pc_2 <= pc_2 + 32'h8;
        end
    end

    always @(posedge clk) begin
        if (rst == `RstEnable) ce <= `ChipDisable;
        else ce <= `ChipEnable;
    end

endmodule
