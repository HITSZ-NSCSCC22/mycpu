`include "defines.v"
`include "pc_reg.v"
`include "regfile.v"
`include "csr_defines.v"
`include "cs_reg.v"
`include "tlb.v"
`include "tlb_entry.v"
`include "AXI/axi_master.v"
`include "pipeline/1_fetch/if_buffer.v"
`include "pipeline/1_fetch/if_id.v"
`include "pipeline/2_decode/id.v"
`include "pipeline/2_decode/id_ex.v"
`include "pipeline/3_execution/ex.v"
`include "pipeline/3_execution/ex_mem.v"
`include "pipeline/4_mem/mem.v"
`include "pipeline/4_mem/mem_wb.v"

module cpu_top (
    input wire aclk,
    input wire aresetn,

    input wire [7:0] intrpt,  // External interrupt

    // AXI interface 
    // read reqest
    output [ 3:0] arid,
    output [31:0] araddr,
    output [ 7:0] arlen,
    output [ 2:0] arsize,
    output [ 1:0] arburst,
    output [ 1:0] arlock,
    output [ 3:0] arcache,
    output [ 2:0] arprot,
    output        arvalid,
    input         arready,
    // read back
    input  [ 3:0] rid,
    input  [31:0] rdata,
    input  [ 1:0] rresp,
    input         rlast,
    input         rvalid,
    output        rready,
    // write request
    output [ 3:0] awid,
    output [31:0] awaddr,
    output [ 7:0] awlen,
    output [ 2:0] awsize,
    output [ 1:0] awburst,
    output [ 1:0] awlock,
    output [ 3:0] awcache,
    output [ 2:0] awprot,
    output        awvalid,
    input         awready,
    // write data
    output [ 3:0] wid,
    output [31:0] wdata,
    output [ 3:0] wstrb,
    output        wlast,
    output        wvalid,
    input         wready,
    //write back
    input  [ 3:0] bid,
    input  [ 1:0] bresp,
    input         bvalid,
    output        bready,
    //debug info
    output [31:0] debug0_wb_pc,
    output [ 3:0] debug0_wb_rf_wen,
    output [ 4:0] debug0_wb_rf_wnum,
    output [31:0] debug0_wb_rf_wdata
);

    // Clock signal
    wire clk;
    assign clk = aclk;
    // Reset signal
    wire rst_n;
    wire rst;
    assign rst_n = aresetn;
    assign rst   = ~rst_n;

    // Global enable signal
    wire chip_enable;

    wire branch_flag_1;
    wire branch_flag_2;
    wire Instram_branch_flag;
    assign Instram_branch_flag = branch_flag_1 | branch_flag_2;

    wire axi_busy;
    wire [`RegBus] axi_data;
    wire [`RegBus] axi_addr;

    dummy_icache #(
        .ADDR_WIDTH(`RegWidth),
        .DATA_WIDTH(`RegWidth)
    ) u_dummy_icache (
        .clk       (clk),
        .rst       (rst),
        .raddr_1_i (pc_buffer_1),
        .raddr_2_i (pc_buffer_2),
        .stallreq_o(stallreq_from_id_1),
        .rvalid_1_o(),
        .rvalid_2_o(),
        .raddr_1_o (),
        .raddr_2_o (),
        .rdata_1_o (),
        .rdata_2_o (),
        .axi_addr_o(axi_addr),
        .axi_data_i(axi_data),
        .axi_busy_i(axi_busy)
    );


    axi_master u_axi_master (
        .aclk   (aclk),
        .aresetn(aresetn),

        .cpu_addr_i(axi_addr),
        .cpu_ce_i(axi_addr != 0),
        .cpu_data_i(0),
        .cpu_we_i(1'b0),
        .cpu_sel_i(4'b1111),
        .stall_i(Instram_branch_flag),
        .flush_i(Instram_branch_flag),
        .cpu_data_o(axi_data),
        .stallreq(axi_busy),
        .id(4'b0000),  // Read Instruction only, TODO: move this from AXI to cache
        .s_arid(arid),
        .s_araddr(araddr),
        .s_arlen(arlen),
        .s_arsize(arsize),
        .s_arburst(arburst),
        .s_arlock(arlock),
        .s_arcache(arcache),
        .s_arprot(arprot),
        .s_arvalid(arvalid),
        .s_arready(arready),
        .s_rid(rid),
        .s_rdata(rdata),
        .s_rresp(rresp),
        .s_rlast(rlast),
        .s_rvalid(rvalid),
        .s_rready(rready),
        .s_awid(awid),
        .s_awaddr(awaddr),
        .s_awlen(awlen),
        .s_awsize(awsize),
        .s_awburst(awburst),
        .s_awlock(awlock),
        .s_awcache(awcache),
        .s_awprot(awprot),
        .s_awvalid(awvalid),
        .s_awready(awready),
        .s_wid(wid),
        .s_wdata(wdata),
        .s_wstrb(wstrb),
        .s_wlast(wlast),
        .s_wvalid(wvalid),
        .s_wready(wready),
        .s_bid(bid),
        .s_bresp(bresp),
        .s_bvalid(bvalid),
        .s_bready(bready)
    );


    wire [`InstAddrBus] pc_1;
    wire [`InstAddrBus] pc_2;

    wire [`InstAddrBus] pc_buffer_1;
    wire [`InstAddrBus] pc_buffer_2;


    wire [`RegBus] branch_target_address_1;
    wire [`RegBus] branch_target_address_2;
    wire [`RegBus] link_addr;
    wire flush;
    wire [`RegBus] new_pc;
    wire [6:0] stall1;  // [pc_reg,if_buffer_1, if_id, id_ex, ex_mem, mem_wb, ctrl]
    wire [6:0] stall2;


    //tlb
    wire inst_addr_trans_en;
    wire data_addr_trans_en;
    wire fetch_en;
    wire [31:0] inst_vaddr;
    wire inst_dmw0_en;
    wire inst_dmw1_en;
    wire [7:0] inst_index;
    wire [19:0] inst_tag;
    wire [3:0] inst_offset;
    wire inst_tlb_found;
    wire inst_tlb_v;
    wire inst_tlb_d;
    wire [1:0] inst_tlb_mat;
    wire [1:0] inst_tlb_plv;
    wire data_fetch;
    wire [31:0] data_vaddr;
    wire data_dmw0_en;
    wire data_dmw1_en;
    wire cacop_op_mode_di;
    wire [7:0] data_index;
    wire [19:0] data_tag;
    wire [3:0] data_offset;
    wire data_tlb_found;
    wire [4:0] data_tlb_index;
    wire data_tlb_v;
    wire data_tlb_d;
    wire [1:0] data_tlb_mat;
    wire [1:0] data_tlb_plv;
    wire tlbfill_en;
    wire tlbwr_en;
    wire [4:0] rand_index;
    wire [31:0] tlbw_tlbehi;
    wire [31:0] tlbw_tlbelo0;
    wire [31:0] tlbw_tlbelo1;
    wire [31:0] tlbw_r_tlbidx;
    wire [5:0] tlbw_ecode;
    wire [31:0] tlbr_tlbehi;
    wire [31:0] tlbr_tlbelo0;
    wire [31:0] tlbr_tlbelo1;
    wire [31:0] tlbr_tlbidx;
    wire [9:0] tlbr_asid;
    wire invtlb_en;
    wire [9:0] invtlb_asid;
    wire [18:0] invtlb_vpn;
    wire [4:0] invtlb_op;

    //csr
    wire has_int;
    wire excp_flush;
    wire ertn_flush;
    wire wb_csr_en;
    wire [13:0] wb_csr_addr;
    wire [31:0] wb_csr_data;
    wire [31:0] wb_csr_era;
    wire [8:0] wb_csr_esubcode;
    wire [5:0] wb_csr_ecode;
    wire wb_va_error;
    wire [31:0] wb_bad_va;
    wire tlbsrch_en;
    wire tlbsrch_found;
    wire [4:0] tlbsrch_index;
    wire excp_tlbrefill;
    wire excp_tlb;
    wire [18:0] excp_tlb_vppn;
    wire csr_llbit_i;
    wire csr_llbit_set_i;
    wire csr_llbit_o;
    wire csr_llbit_set_o;
    wire [`RegBus] csr_eentry;
    wire [31:0] csr_tlbrentry;
    wire [`RegBus] csr_era;

    wire [9:0] csr_asid;
    wire csr_pg;
    wire csr_da;
    wire [31:0] csr_dmw0;
    wire [31:0] csr_dmw1;
    wire [1:0] csr_datf;
    wire [1:0] csr_datm;
    wire [1:0] csr_plv;

    wire [13:0] id_csr_addr_1;
    wire [31:0] id_csr_data_1;
    wire [13:0] id_csr_addr_2;
    wire [31:0] id_csr_data_2;
    wire [`RegBus] id_csr_data_o_1;
    wire [`RegBus] id_csr_data_o_2;
    wire id_csr_we_1;
    wire id_csr_we_2;
    wire [13:0] id_csr_addr_o_1;
    wire [13:0] id_csr_addr_o_2;
    wire [13:0] id_csr_read_addr_o_1;
    wire [13:0] id_csr_read_addr_o_2;

    wire pc_excp_o;
    wire [3:0] pc_excp_num_o;

    wire idle_flush;
    wire [`InstAddrBus] idle_pc;
    wire excp_flush_1;
    wire ertn_flush_1;
    wire excp_flush_2;
    wire ertn_flush_2;

    assign excp_flush = excp_flush_1 | excp_flush_2;
    assign ertn_flush = ertn_flush_1 | ertn_flush_2;

    wire [`RegBus] id_csr_data_i_1;
    wire [`RegBus] id_csr_data_i_2;

    wire disable_cache;

    pc_reg u_pc_reg (
        .clk(clk),
        .rst(rst),
        .pc_1(pc_1),
        .pc_2(pc_2),
        .ce(chip_enable),
        .branch_flag_i_1(branch_flag_1),
        .branch_target_address_1(branch_target_address_1),
        .branch_flag_i_2(branch_flag_2),
        .branch_target_address_2(branch_target_address_2),
        .flush(flush),
        .new_pc(new_pc),
        .stall1(stall1[0]),
        .stall2(stall2[0]),
        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush),
        .excp_tlbrefill(excp_tlbrefill),
        .idle_flush(idle_flush),
        .idle_pc(idle_pc),

        .excp_o(pc_excp_o),
        .excp_num_o(pc_excp_num_o),

        .csr_pg(csr_pg),
        .csr_da(csr_da),
        .csr_dmw0(csr_dmw0),
        .csr_dmw1(csr_dmw1),
        .csr_plv(csr_plv),
        .csr_datf(csr_datf),
        .disable_cache(disable_cache),
        .csr_eentry(csr_eentry),
        .csr_era(csr_era),
        .csr_tlbrentry(csr_tlbrentry),

        .inst_tlb_found(inst_tlb_found),
        .inst_tlb_v(inst_tlb_v),
        .inst_tlb_d(inst_tlb_d),
        .inst_tlb_mat(inst_tlb_mat),
        .inst_tlb_plv(inst_tlb_plv),

        .inst_addr(inst_vaddr),
        .inst_addr_trans_en(inst_addr_trans_en),
        .dmw0_en(inst_dmw0_en),
        .dmw1_en(inst_dmw1_en)
    );

    wire if_inst_valid_1;
    wire if_inst_valid_2;
    wire if_excp_i_1;
    wire [3:0] if_excp_num_i_1;
    wire if_excp_i_2;
    wire [3:0] if_excp_num_i_2;

    if_buffer if_buffer_1 (
        .clk(clk),
        .rst(rst),
        .pc_i(pc_1),
        .branch_flag_i(branch_flag_1 | branch_flag_2),
        .pc_valid(if_inst_valid_1),
        .pc_o(pc_buffer_1),
        .flush(flush),
        .stall(stall1[1]),
        .excp_i(pc_excp_o),
        .excp_num_i(pc_excp_num_o),
        .excp_o(if_excp_i_1),
        .excp_num_o(if_excp_num_i_1),
        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush)
    );

    if_buffer if_buffer_2 (
        .clk(clk),
        .rst(rst),
        .pc_i(pc_2),
        .branch_flag_i(branch_flag),
        .pc_valid(if_inst_valid_2),
        .pc_o(pc_buffer_2),
        .flush(flush),
        .stall(stall2[1]),
        .excp_i(pc_excp_o),
        .excp_num_i(pc_excp_num_o),
        .excp_o(if_excp_i_2),
        .excp_num_o(if_excp_num_i_2),
        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush)
    );


    wire [`InstAddrBus] id_pc_1;
    wire [`InstBus] id_inst_1;
    wire [`InstAddrBus] id_pc_2;
    wire [`InstBus] id_inst_2;

    wire if_excp_o_1;
    wire [3:0] if_excp_num_o_1;
    wire if_excp_o_2;
    wire [3:0] if_excp_num_o_2;

    //  wire if_id_instr_invalid;
    if_id u_if_id_1 (
        .clk(clk),
        .rst(rst),
        .if_pc_i(pc_buffer_1),
        .if_inst_i(ram_rdata_i_1),
        .id_pc_o(id_pc_1),
        .id_inst_o(id_inst_1),
        .if_inst_valid(if_inst_valid_1),
        .branch_flag_i(branch_flag),
        .flush(flush),
        .stall(stall1[2]),
        .excp_i(if_excp_i_1),
        .excp_num_i(if_excp_num_i_1),
        .excp_o(if_excp_o_1),
        .excp_num_o(if_excp_num_o_1)
    );

    if_id u_if_id_2 (
        .clk(clk),
        .rst(rst),
        .if_pc_i(pc_buffer_2),
        .if_inst_i(ram_rdata_i_2),
        .id_pc_o(id_pc_2),
        .id_inst_o(id_inst_2),
        .if_inst_valid(if_inst_valid_2),
        .branch_flag_i(branch_flag),
        .flush(flush),
        .stall(stall2[2]),
        .excp_i(if_excp_i_2),
        .excp_num_i(if_excp_num_i_2),
        .excp_o(if_excp_o_2),
        .excp_num_o(if_excp_num_o_2)
    );

    wire [`AluOpBus] id_aluop_1;
    wire [`AluSelBus] id_alusel_1;
    wire [`RegBus] id_reg1_1;
    wire [`RegBus] id_reg2_1;
    wire [`RegAddrBus] id_reg_waddr_1;
    wire id_wreg_1;
    wire id_inst_valid_1;
    wire [`InstAddrBus] id_inst_pc_1;
    wire [`RegBus] id_inst_o_1;

    wire reg1_read_1;
    wire reg2_read_1;
    wire [`RegAddrBus] reg1_addr_1;
    wire [`RegAddrBus] reg2_addr_1;
    wire [`RegBus] reg1_data_1;
    wire [`RegBus] reg2_data_1;

    wire ex_wreg_o_1;
    wire [`RegAddrBus] ex_reg_waddr_o_1;
    wire [`RegBus] ex_reg_wdata_1;
    wire [`AluOpBus] ex_aluop_o_1;

    wire mem_wreg_o_1;
    wire [`RegAddrBus] mem_reg_waddr_o_1;
    wire [`RegBus] mem_reg_wdata_o_1;

    wire stallreq_from_id_1;
    wire stallreq_from_ex_1;

    wire [1:0] id_excepttype_o_1;
    wire [`RegBus] id_current_inst_address_o_1;

    wire ex_wreg_o_2;
    wire [`RegAddrBus] ex_reg_waddr_o_2;
    wire [`RegBus] ex_reg_wdata_2;
    wire [`AluOpBus] ex_aluop_o_2;

    wire mem_wreg_o_2;
    wire [`RegAddrBus] mem_reg_waddr_o_2;
    wire [`RegBus] mem_reg_wdata_o_2;

    wire [`RegAddrBus] reg1_addr_2;
    wire [`RegAddrBus] reg2_addr_2;

    wire [`RegBus] link_addr_1;
    wire [`RegBus] link_addr_2;

    wire [`RegAddrBus] id_reg_waddr_2;

    wire stallreq_to_next_1;
    wire stallreq_to_next_2;

    wire id_excp_o_1;
    wire [8:0] id_excp_num_o_1;
    wire id_excp_o_2;
    wire [8:0] id_excp_num_o_2;


    id u_id_1 (
        .rst(rst),
        .pc_i(id_pc_1),
        .inst_i(id_inst_1),

        .pc_i_other(pc_buffer_2),

        .reg1_data_i(reg1_data_1),
        .reg2_data_i(reg2_data_1),

        .ex_wreg_i_1 (ex_wreg_o_1),
        .ex_waddr_i_1(ex_reg_waddr_o_1),
        .ex_wdata_i_1(ex_reg_wdata_1),
        .ex_aluop_i_1(ex_aluop_o_1),

        .ex_wreg_i_2 (ex_wreg_o_2),
        .ex_waddr_i_2(ex_reg_waddr_o_2),
        .ex_wdata_i_2(ex_reg_wdata_2),
        .ex_aluop_i_2(ex_aluop_o_2),

        .mem_wreg_i_1 (mem_wreg_o_1),
        .mem_waddr_i_1(mem_reg_waddr_o_1),
        .mem_wdata_i_1(mem_reg_wdata_o_1),

        .mem_wreg_i_2 (mem_wreg_o_2),
        .mem_waddr_i_2(mem_reg_waddr_o_2),
        .mem_wdata_i_2(mem_reg_wdata_o_2),

        .reg1_read_o(reg1_read_1),
        .reg2_read_o(reg2_read_1),

        .reg1_addr_o(reg1_addr_1),
        .reg2_addr_o(reg2_addr_1),

        .aluop_o    (id_aluop_1),
        .alusel_o   (id_alusel_1),
        .reg1_o     (id_reg1_1),
        .reg2_o     (id_reg2_1),
        .reg_waddr_o(id_reg_waddr_1),
        .wreg_o     (id_wreg_1),
        .inst_valid (id_inst_valid_1),
        .inst_pc    (id_inst_pc_1),
        .inst_o     (id_inst_o_1),
        .csr_we     (id_csr_we_1),
        .csr_addr_o (id_csr_addr_o_1),
        .csr_data_o (id_csr_data_o_1),

        .csr_read_addr_o(id_csr_read_addr_o_1),
        .csr_data_i(id_csr_data_1),
        .has_int(has_int),
        .csr_plv(csr_plv),

        .excp_i(if_excp_o_1),
        .excp_num_i(if_excp_num_o_1),
        .excp_o(id_excp_o_1),
        .excp_num_o(id_excp_num_o_1),

        .branch_flag_o(branch_flag_1),
        .branch_target_address_o(branch_target_address_1),
        .link_addr_o(link_addr_1),

        .stallreq(stallreq_to_next_1),
        .idle_stallreq(),

        .excepttype_o(id_excepttype_o_1),
        .current_inst_address_o(id_current_inst_address_o_1)
    );

    wire [`AluOpBus] id_aluop_2;
    wire [`AluSelBus] id_alusel_2;
    wire [`RegBus] id_reg1_2;
    wire [`RegBus] id_reg2_2;

    wire id_wreg_2;
    wire id_inst_valid_2;
    wire [`InstAddrBus] id_inst_pc_2;
    wire [`RegBus] id_inst_o_2;

    wire reg1_read_2;
    wire reg2_read_2;
    wire [`RegBus] reg1_data_2;
    wire [`RegBus] reg2_data_2;



    wire stallreq_from_id_2;
    wire stallreq_from_ex_2;

    wire [1:0] id_excepttype_o_2;
    wire [`RegBus] id_current_inst_address_o_2;



    id u_id_2 (
        .rst(rst),
        .pc_i(id_pc_2),
        .inst_i(id_inst_2),

        .pc_i_other(pc_buffer_1),

        .reg1_data_i(reg1_data_2),
        .reg2_data_i(reg2_data_2),

        .ex_wreg_i_1 (ex_wreg_o_2),
        .ex_waddr_i_1(ex_reg_waddr_o_2),
        .ex_wdata_i_1(ex_reg_wdata_2),
        .ex_aluop_i_1(ex_aluop_o_2),

        .ex_wreg_i_2 (ex_wreg_o_1),
        .ex_waddr_i_2(ex_reg_waddr_o_1),
        .ex_wdata_i_2(ex_reg_wdata_1),
        .ex_aluop_i_2(ex_aluop_o_1),

        .mem_wreg_i_1 (mem_wreg_o_2),
        .mem_waddr_i_1(mem_reg_waddr_o_2),
        .mem_wdata_i_1(mem_reg_wdata_o_2),

        .mem_wreg_i_2 (mem_wreg_o_1),
        .mem_waddr_i_2(mem_reg_waddr_o_1),
        .mem_wdata_i_2(mem_reg_wdata_o_1),

        .reg1_read_o(reg1_read_2),
        .reg2_read_o(reg2_read_2),

        .reg1_addr_o(reg1_addr_2),
        .reg2_addr_o(reg2_addr_2),

        .aluop_o    (id_aluop_2),
        .alusel_o   (id_alusel_2),
        .reg1_o     (id_reg1_2),
        .reg2_o     (id_reg2_2),
        .reg_waddr_o(id_reg_waddr_2),
        .wreg_o     (id_wreg_2),
        .inst_valid (id_inst_valid_2),
        .inst_pc    (id_inst_pc_2),
        .inst_o     (id_inst_o_2),

        .csr_we(id_csr_we_2),
        .csr_addr_o(id_csr_addr_o_2),
        .csr_data_i(id_csr_data_2),

        .csr_read_addr_o(id_csr_read_addr_o_2),
        .csr_data_o(id_csr_data_o_2),
        .has_int(has_int),
        .csr_plv(csr_plv),

        .excp_i(if_excp_o_2),
        .excp_num_i(if_excp_num_o_2),
        .excp_o(id_excp_o_2),
        .excp_num_o(id_excp_num_o_2),

        .branch_flag_o(branch_flag_2),
        .branch_target_address_o(branch_target_address_2),
        .link_addr_o(link_addr_2),

        .stallreq(stallreq_to_next_2),
        .idle_stallreq(),

        .excepttype_o(id_excepttype_o_2),
        .current_inst_address_o(id_current_inst_address_o_2)

    );

    wire [`AluOpBus] ex_aluop_1;
    wire [`AluSelBus] ex_alusel_1;
    wire [`RegBus] ex_reg1_1;
    wire [`RegBus] ex_reg2_1;
    wire [`RegAddrBus] ex_reg_waddr_i_1;
    wire ex_wreg_i_1;
    wire ex_inst_valid_i_1;
    wire [`InstAddrBus] ex_inst_pc_i_1;
    wire [`RegBus] ex_link_address_1;
    wire [`RegBus] ex_inst_i_1;
    wire [1:0] ex_excepttype_i_1;
    wire [`RegBus] ex_current_inst_address_i_1;
    wire ex_csr_we_i_1;
    wire [13:0] ex_csr_addr_i_1;
    wire [31:0] ex_csr_data_i_1;

    wire ex_excp_i_1;
    wire [8:0] ex_excp_num_i_1;
    wire ex_excp_o_1;
    wire [8:0] ex_excp_num_i_2;

    id_ex id_ex_1 (
        .clk  (clk),
        .rst  (rst),
        .stall(stall1[3]),

        .id_aluop(id_aluop_1),
        .id_alusel(id_alusel_1),
        .id_reg1(id_reg1_1),
        .id_reg2(id_reg2_1),
        .id_wd(id_reg_waddr_1),
        .id_wreg(id_wreg_1),
        .id_inst_pc(id_inst_pc_1),
        .id_inst_valid(id_inst_valid_1),
        .id_link_address(link_addr_1),
        .id_inst(id_inst_o_1),
        .flush(flush),
        .id_excepttype(id_excepttype_o_1),
        .id_current_inst_address(id_current_inst_address_o_1),
        .id_csr_we(id_csr_we_1),
        .id_csr_addr(id_csr_addr_o_1),
        .id_csr_data(id_csr_data_o_1),

        .ex_aluop(ex_aluop_1),
        .ex_alusel(ex_alusel_1),
        .ex_reg1(ex_reg1_1),
        .ex_reg2(ex_reg2_1),
        .ex_wd(ex_reg_waddr_i_1),
        .ex_wreg(ex_wreg_i_1),
        .ex_inst_pc(ex_inst_pc_i_1),
        .ex_inst_valid(ex_inst_valid_i_1),
        .ex_link_address(ex_link_address_1),
        .ex_inst(ex_inst_i_1),
        .ex_excepttype(ex_excepttype_i_1),
        .ex_current_inst_address(ex_current_inst_address_i_1),
        .ex_csr_we(ex_csr_we_i_1),
        .ex_csr_addr(ex_csr_addr_i_1),
        .ex_csr_data(ex_csr_data_i_1),

        .reg1_addr_i(reg1_addr_1),
        .reg2_addr_i(reg2_addr_1),
        .pc_i_other(id_inst_pc_2),
        .reg1_addr_i_other(reg1_addr_2),
        .reg2_addr_i_other(reg2_addr_2),
        .waddr_i_other(id_reg_waddr_2),

        .stallreq_from_id(stallreq_to_next_1),
        .stallreq(stallreq_from_id_1),

        .excp_i(id_excp_o_1),
        .excp_num_i(id_excp_num_o_1),
        .excp_o(ex_excp_i_1),
        .excp_num_o(ex_excp_num_i_1),

        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush)
    );

    wire [`AluOpBus] ex_aluop_2;
    wire [`AluSelBus] ex_alusel_2;
    wire [`RegBus] ex_reg1_2;
    wire [`RegBus] ex_reg2_2;
    wire [`RegAddrBus] ex_reg_waddr_i_2;
    wire ex_wreg_i_2;
    wire ex_inst_valid_i_2;
    wire [`InstAddrBus] ex_inst_pc_i_2;
    wire [`RegBus] ex_link_address_2;
    wire [`RegBus] ex_inst_i_2;
    wire [1:0] ex_excepttype_i_2;
    wire [`RegBus] ex_current_inst_address_i_2;
    wire ex_csr_we_i_2;
    wire [13:0] ex_csr_addr_i_2;
    wire [31:0] ex_csr_data_i_2;

    wire ex_excp_i_2;
    wire [9:0] ex_excp_num_o_1;
    wire ex_excp_o_2;
    wire [9:0] ex_excp_num_o_2;

    id_ex id_ex_2 (
        .clk  (clk),
        .rst  (rst),
        .stall(stall2[3]),

        .id_aluop(id_aluop_2),
        .id_alusel(id_alusel_2),
        .id_reg1(id_reg1_2),
        .id_reg2(id_reg2_2),
        .id_wd(id_reg_waddr_2),
        .id_wreg(id_wreg_2),
        .id_inst_pc(id_inst_pc_2),
        .id_inst_valid(id_inst_valid_2),
        .id_link_address(link_addr_2),
        .id_inst(id_inst_o_2),
        .flush(flush),
        .id_excepttype(id_excepttype_o_2),
        .id_current_inst_address(id_current_inst_address_o_2),
        .id_csr_we(id_csr_we_2),
        .id_csr_addr(id_csr_addr_o_2),
        .id_csr_data(id_csr_data_o_2),

        .ex_aluop(ex_aluop_2),
        .ex_alusel(ex_alusel_2),
        .ex_reg1(ex_reg1_2),
        .ex_reg2(ex_reg2_2),
        .ex_wd(ex_reg_waddr_i_2),
        .ex_wreg(ex_wreg_i_2),
        .ex_inst_pc(ex_inst_pc_i_2),
        .ex_inst_valid(ex_inst_valid_i_2),
        .ex_link_address(ex_link_address_2),
        .ex_inst(ex_inst_i_2),
        .ex_excepttype(ex_excepttype_i_2),
        .ex_current_inst_address(ex_current_inst_address_i_2),
        .ex_csr_we(ex_csr_we_i_2),
        .ex_csr_addr(ex_csr_addr_i_2),
        .ex_csr_data(ex_csr_data_i_2),

        .reg1_addr_i(reg1_addr_2),
        .reg2_addr_i(reg2_addr_2),
        .pc_i_other(id_inst_pc_1),
        .reg1_addr_i_other(reg1_addr_1),
        .reg2_addr_i_other(reg2_addr_2),
        .waddr_i_other(id_reg_waddr_1),

        .stallreq_from_id(stallreq_to_next_2),
        .stallreq(stallreq_from_id_2),

        .excp_i(id_excp_o_2),
        .excp_num_i(id_excp_num_o_2),
        .excp_o(ex_excp_i_2),
        .excp_num_o(ex_excp_num_i_2),

        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush)
    );


    wire ex_inst_valid_o_1;
    wire [`InstAddrBus] ex_inst_pc_o_1;
    wire [`RegBus] ex_addr_o_1;
    wire [`RegBus] ex_reg2_o_1;
    wire [1:0] ex_excepttype_o_1;
    wire [`RegBus] ex_current_inst_address_o_1;
    wire ex_csr_we_o_1;
    wire [13:0] ex_csr_addr_o_1;
    wire [31:0] ex_csr_data_o_1;



    ex u_ex_1 (
        .rst(rst),

        .aluop_i(ex_aluop_1),
        .alusel_i(ex_alusel_1),
        .reg1_i(ex_reg1_1),
        .reg2_i(ex_reg2_1),
        .wd_i(ex_reg_waddr_i_1),
        .wreg_i(ex_wreg_i_1),
        .inst_valid_i(ex_inst_valid_i_1),
        .inst_pc_i(ex_inst_pc_i_1),
        .inst_i(ex_inst_i_1),
        .link_addr_i(ex_link_address_1),
        .excepttype_i(ex_excepttype_i_1),
        .current_inst_address_i(ex_current_inst_address_i_1),
        .ex_csr_we_i(ex_csr_we_i_1),
        .ex_csr_addr_i(ex_csr_addr_i_1),
        .ex_csr_data_i(ex_csr_data_i_1),

        .wd_o(ex_reg_waddr_o_1),
        .wreg_o(ex_wreg_o_1),
        .wdata_o(ex_reg_wdata_1),
        .inst_valid_o(ex_inst_valid_o_1),
        .inst_pc_o(ex_inst_pc_o_1),
        .aluop_o(ex_aluop_o_1),
        .mem_addr_o(ex_addr_o_1),
        .reg2_o(ex_reg2_o_1),
        .excepttype_o(ex_excepttype_o_1),
        .current_inst_address_o(ex_current_inst_address_o_1),
        .ex_csr_we_o(ex_csr_we_o_1),
        .ex_csr_addr_o(ex_csr_addr_o_1),
        .ex_csr_data_o(ex_csr_data_o_1),

        .stallreq(stallreq_from_ex_1),

        .excp_i(ex_excp_i_1),
        .excp_num_i(ex_excp_num_i_1),
        .excp_o(ex_excp_o_1),
        .excp_num_o(ex_excp_num_o_1)
    );

    wire ex_inst_valid_o_2;
    wire [`InstAddrBus] ex_inst_pc_o_2;
    wire [`RegBus] ex_addr_o_2;
    wire [`RegBus] ex_reg2_o_2;
    wire [1:0] ex_excepttype_o_2;
    wire [`RegBus] ex_current_inst_address_o_2;
    wire ex_csr_we_o_2;
    wire [13:0] ex_csr_addr_o_2;
    wire [31:0] ex_csr_data_o_2;


    ex u_ex_2 (
        .rst(rst),

        .aluop_i(ex_aluop_2),
        .alusel_i(ex_alusel_2),
        .reg1_i(ex_reg1_2),
        .reg2_i(ex_reg2_2),
        .wd_i(ex_reg_waddr_i_2),
        .wreg_i(ex_wreg_i_2),
        .inst_valid_i(ex_inst_valid_i_2),
        .inst_pc_i(ex_inst_pc_i_2),
        .inst_i(ex_inst_i_2),
        .link_addr_i(ex_link_address_2),
        .excepttype_i(ex_excepttype_i_2),
        .current_inst_address_i(ex_current_inst_address_i_2),
        .ex_csr_we_i(ex_csr_we_i_2),
        .ex_csr_addr_i(ex_csr_addr_i_2),
        .ex_csr_data_i(ex_csr_data_i_2),

        .wd_o(ex_reg_waddr_o_2),
        .wreg_o(ex_wreg_o_2),
        .wdata_o(ex_reg_wdata_2),
        .inst_valid_o(ex_inst_valid_o_2),
        .inst_pc_o(ex_inst_pc_o_2),
        .aluop_o(ex_aluop_o_2),
        .mem_addr_o(ex_addr_o_2),
        .reg2_o(ex_reg2_o_2),
        .excepttype_o(ex_excepttype_o_2),
        .current_inst_address_o(ex_current_inst_address_o_2),
        .ex_csr_we_o(ex_csr_we_o_2),
        .ex_csr_addr_o(ex_csr_addr_o_2),
        .ex_csr_data_o(ex_csr_data_o_2),

        .stallreq(stallreq_from_ex_2),

        .excp_i(ex_excp_i_2),
        .excp_num_i(ex_excp_num_i_2),
        .excp_o(ex_excp_o_2),
        .excp_num_o(ex_excp_num_o_2)
    );


    wire mem_wreg_i_1;
    wire [`RegAddrBus] mem_reg_waddr_i_1;
    wire [`RegBus] mem_reg_wdata_i_1;

    wire mem_inst_valid_1;
    wire [`InstAddrBus] mem_inst_pc_1;

    wire [`AluOpBus] mem_aluop_i_1;
    wire [`RegBus] mem_addr_i_1;
    wire [`RegBus] mem_reg2_i_1;
    wire [1:0] mem_excepttype_i_1;
    wire [`RegBus] mem_current_inst_address_i_1;

    wire mem_csr_we_i_1;
    wire [13:0] mem_csr_addr_i_1;
    wire [31:0] mem_csr_data_i_1;

    wire mem_excp_i_1;
    wire [9:0] mem_excp_num_i_1;
    wire mem_excp_i_2;
    wire [9:0] mem_excp_num_i_2;

    ex_mem u_ex_mem_1 (
        .clk  (clk),
        .rst  (rst),
        .stall(stall1[4]),

        .ex_wd                  (ex_reg_waddr_o_1),
        .ex_wreg                (ex_wreg_o_1),
        .ex_wdata               (ex_reg_wdata_1),
        .ex_inst_pc             (ex_inst_pc_o_1),
        .ex_inst_valid          (ex_inst_valid_o_1),
        .ex_aluop               (ex_aluop_o_1),
        .ex_mem_addr            (ex_addr_o_1),
        .ex_reg2                (ex_reg2_o_1),
        .flush                  (flush),
        .ex_excepttype          (ex_excepttype_o_1),
        .ex_current_inst_address(ex_current_inst_address_o_1),
        .ex_csr_we              (ex_csr_we_o_1),
        .ex_csr_addr            (ex_csr_addr_o_1),
        .ex_csr_data            (ex_csr_data_o_1),

        .mem_wd                  (mem_reg_waddr_i_1),
        .mem_wreg                (mem_wreg_i_1),
        .mem_wdata               (mem_reg_wdata_i_1),
        .mem_inst_valid          (mem_inst_valid_1),
        .mem_inst_pc             (mem_inst_pc_1),
        .mem_aluop               (mem_aluop_i_1),
        .mem_mem_addr            (mem_addr_i_1),
        .mem_reg2                (mem_reg2_i_1),
        .mem_excepttype          (mem_excepttype_i_1),
        .mem_current_inst_address(mem_current_inst_address_i_1),
        .mem_csr_we              (mem_csr_we_i_1),
        .mem_csr_addr            (mem_csr_addr_i_1),
        .mem_csr_data            (mem_csr_data_i_1),

        .excp_i(ex_excp_o_1),
        .excp_num_i(ex_excp_num_o_1),
        .excp_o(mem_excp_i_1),
        .excp_num_o(mem_excp_num_i_1),

        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush)

    );


    wire mem_wreg_i_2;
    wire [`RegAddrBus] mem_reg_waddr_i_2;
    wire [`RegBus] mem_reg_wdata_i_2;

    wire mem_inst_valid_2;
    wire [`InstAddrBus] mem_inst_pc_2;

    wire [`AluOpBus] mem_aluop_i_2;
    wire [`RegBus] mem_addr_i_2;
    wire [`RegBus] mem_reg2_i_2;
    wire [1:0] mem_excepttype_i_2;
    wire [`RegBus] mem_current_inst_address_i_2;
    wire mem_csr_we_i_2;
    wire [13:0] mem_csr_addr_i_2;
    wire [31:0] mem_csr_data_i_2;


    ex_mem u_ex_mem_2 (
        .clk  (clk),
        .rst  (rst),
        .stall(stall2[4]),

        .ex_wd                  (ex_reg_waddr_o_2),
        .ex_wreg                (ex_wreg_o_2),
        .ex_wdata               (ex_reg_wdata_2),
        .ex_inst_pc             (ex_inst_pc_o_2),
        .ex_inst_valid          (ex_inst_valid_o_2),
        .ex_aluop               (ex_aluop_o_2),
        .ex_mem_addr            (ex_addr_o_2),
        .ex_reg2                (ex_reg2_o_2),
        .flush                  (flush),
        .ex_excepttype          (ex_excepttype_o_2),
        .ex_current_inst_address(ex_current_inst_address_o_2),
        .ex_csr_we              (ex_csr_we_o_1),
        .ex_csr_addr            (ex_csr_addr_o_1),
        .ex_csr_data            (ex_csr_data_o_1),

        .mem_wd                  (mem_reg_waddr_i_2),
        .mem_wreg                (mem_wreg_i_2),
        .mem_wdata               (mem_reg_wdata_i_2),
        .mem_inst_valid          (mem_inst_valid_2),
        .mem_inst_pc             (mem_inst_pc_2),
        .mem_aluop               (mem_aluop_i_2),
        .mem_mem_addr            (mem_addr_i_2),
        .mem_reg2                (mem_reg2_i_2),
        .mem_excepttype          (mem_excepttype_i_2),
        .mem_current_inst_address(mem_current_inst_address_i_2),
        .mem_csr_we              (mem_csr_we_i_2),
        .mem_csr_addr            (mem_csr_addr_i_2),
        .mem_csr_data            (mem_csr_data_i_2),

        .excp_i(ex_excp_o_2),
        .excp_num_i(ex_excp_num_o_2),
        .excp_o(mem_excp_i_2),
        .excp_num_o(mem_excp_num_i_2),

        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush)

    );

    wire LLbit_o_1;
    wire wb_LLbit_we_i_1;
    wire wb_LLbit_value_i_1;
    wire mem_LLbit_we_o_1;
    wire mem_LLbit_value_o_1;
    wire [1:0] mem_excepttype_o_1;
    wire [1:0] mem_excepttype_o_2;
    wire [`RegBus] mem_current_inst_address_o_1;
    wire [`InstAddrBus] wb_inst_pc_1;
    wire mem_csr_we_o_1;
    wire [13:0] mem_csr_addr_o_1;
    wire [31:0] mem_csr_data_o_1;

    wire mem_excp_o_1;
    wire [15:0] mem_excp_num_o_1;
    wire mem_excp_o_2;
    wire [15:0] mem_excp_num_o_2;

    wire [`AluOpBus] mem_aluop_o_1;
    wire [`AluOpBus] mem_aluop_o_2;

    wire data_addr_trans_en_1;
    wire data_dmw0_en_1;
    wire data_dmw1_en_1;

    wire data_addr_trans_en_2;
    wire data_dmw0_en_2;
    wire data_dmw1_en_2;



    mem u_mem_1 (
        .rst(rst),

        .inst_pc_i (mem_inst_pc_1),
        .wd_i      (mem_reg_waddr_i_1),
        .wreg_i    (mem_wreg_i_1),
        .wdata_i   (mem_reg_wdata_i_1),
        .aluop_i   (mem_aluop_i_1),
        .mem_addr_i(mem_addr_i_1),
        .reg2_i    (mem_reg2_i_1),

        .mem_data_i(dram_data_i_1),

        .LLbit_i(LLbit_o_1),
        .wb_LLbit_we_i(wb_LLbit_we_i_1),
        .wb_LLbit_value_i(wb_LLbit_value_i_1),

        .excepttype_i(mem_excepttype_i_1),
        .current_inst_address_i(mem_current_inst_address_i_1),

        .mem_csr_we_i  (mem_csr_we_i_1),
        .mem_csr_addr_i(mem_csr_addr_i_1),
        .mem_csr_data_i(mem_csr_data_i_1),

        .inst_pc_o(wb_inst_pc_1),
        .wd_o     (mem_reg_waddr_o_1),
        .wreg_o   (mem_wreg_o_1),
        .wdata_o  (mem_reg_wdata_o_1),
        .aluop_o  (mem_aluop_i_1),

        .mem_addr_o(dram_addr_o_1),
        .mem_we_o  (dram_we_o_1),
        .mem_sel_o (dram_sel_o_1),
        .mem_data_o(dram_data_o_1),
        .mem_ce_o  (dram_ce_o_1),

        .LLbit_we_o(mem_LLbit_we_o_1),
        .LLbit_value_o(mem_LLbit_value_o_1),

        .excepttype_o(mem_excepttype_o_1),
        .current_inst_address_o(mem_current_inst_address_o_1),

        .mem_csr_we_o  (mem_csr_we_o_1),
        .mem_csr_addr_o(mem_csr_addr_o_1),
        .mem_csr_data_o(mem_csr_data_o_1),

        .excp_i(mem_excp_i_1),
        .excp_num_i(mem_excp_num_i_1),
        .excp_o(mem_excp_o_1),
        .excp_num_o(mem_excp_num_o_1),

        .csr_pg(csr_pg),
        .csr_da(csr_da),
        .csr_dmw0(csr_dmw0),
        .csr_dmw1(csr_dmw1),
        .csr_plv(csr_plv),
        .csr_datf(csr_datf),
        .disable_cache(1'b0),

        .data_addr_trans_en(data_addr_trans_en_1),
        .dmw0_en(data_dmw0_en_1),
        .dmw1_en(data_dmw1_en_1),
        .cacop_op_mode_di(cacop_op_mode_di),

        .data_tlb_found(data_tlb_found),
        .data_tlb_index(data_tlb_index),
        .data_tlb_v(data_tlb_v),
        .data_tlb_d(data_tlb_d),
        .data_tlb_mat(data_tlb_mat),
        .data_tlb_plv(data_tlb_plv)

    );

    wire LLbit_o_2;
    wire wb_LLbit_we_i_2;
    wire wb_LLbit_value_i_2;
    wire mem_LLbit_we_o_2;
    wire mem_LLbit_value_o_2;
    wire [`RegBus] mem_current_inst_address_o_2;
    wire [`InstAddrBus] wb_inst_pc_2;
    wire mem_csr_we_o_2;
    wire [13:0] mem_csr_addr_o_2;
    wire [31:0] mem_csr_data_o_2;



    mem u_mem_2 (
        .rst(rst),

        .inst_pc_i (mem_inst_pc_2),
        .wd_i      (mem_reg_waddr_i_2),
        .wreg_i    (mem_wreg_i_2),
        .wdata_i   (mem_reg_wdata_i_2),
        .aluop_i   (mem_aluop_i_2),
        .mem_addr_i(mem_addr_i_2),
        .reg2_i    (mem_reg2_i_2),

        .mem_data_i(dram_data_i_2),

        .LLbit_i(LLbit_o_2),
        .wb_LLbit_we_i(wb_LLbit_we_i_2),
        .wb_LLbit_value_i(wb_LLbit_value_i_2),

        .excepttype_i(mem_excepttype_i_2),
        .current_inst_address_i(mem_current_inst_address_i_2),

        .mem_csr_we_i  (mem_csr_we_i_2),
        .mem_csr_addr_i(mem_csr_addr_i_2),
        .mem_csr_data_i(mem_csr_data_i_2),

        .inst_pc_o(wb_inst_pc_2),
        .wd_o     (mem_reg_waddr_o_2),
        .wreg_o   (mem_wreg_o_2),
        .wdata_o  (mem_reg_wdata_o_2),
        .aluop_o  (mem_aluop_o_2),

        .mem_addr_o(dram_addr_o_2),
        .mem_we_o  (dram_we_o_2),
        .mem_sel_o (dram_sel_o_2),
        .mem_data_o(dram_data_o_2),
        .mem_ce_o  (dram_ce_o_2),

        .LLbit_we_o(mem_LLbit_we_o_2),
        .LLbit_value_o(mem_LLbit_value_o_2),

        .excepttype_o(mem_excepttype_o_2),
        .current_inst_address_o(mem_current_inst_address_o_2),

        .mem_csr_we_o  (mem_csr_we_o_2),
        .mem_csr_addr_o(mem_csr_addr_o_2),
        .mem_csr_data_o(mem_csr_data_o_2),

        .excp_i(mem_excp_i_2),
        .excp_num_i(mem_excp_num_i_2),
        .excp_o(mem_excp_o_2),
        .excp_num_o(mem_excp_num_o_2),

        .csr_pg(csr_pg),
        .csr_da(csr_da),
        .csr_dmw0(csr_dmw0),
        .csr_dmw1(csr_dmw1),
        .csr_plv(csr_plv),
        .csr_datf(csr_datf),
        .disable_cache(1'b0),

        .data_addr_trans_en(data_addr_trans_en_2),
        .dmw0_en(data_dmw0_en_2),
        .dmw1_en(data_dmw1_en_2),
        .cacop_op_mode_di(cacop_op_mode_di),

        .data_tlb_found(data_tlb_found),
        .data_tlb_index(data_tlb_index),
        .data_tlb_v(data_tlb_v),
        .data_tlb_d(data_tlb_d),
        .data_tlb_mat(data_tlb_mat),
        .data_tlb_plv(data_tlb_plv)

    );

    assign dram_pc_o_1 = wb_inst_pc_1;
    assign dram_pc_o_2 = wb_inst_pc_2;

    wire wb_wreg_1;
    wire [`RegAddrBus] wb_reg_waddr_1;
    wire [`RegBus] wb_reg_wdata_1;

    wire wb_csr_we_1;
    wire [13:0] wb_csr_addr_1;
    wire [`RegBus] wb_csr_data_1;

    assign debug0_wb_rf_wen   = wb_wreg_1;
    assign debug0_wb_rf_wnum  = wb_reg_waddr_1;
    assign debug0_wb_rf_wdata = wb_reg_wdata_1;


    wire wb_excp_o_1;
    wire [15:0] wb_excp_num_o_1;
    wire wb_excp_o_2;
    wire [15:0] wb_excp_num_o_2;

    wire [`RegBus] wb_csr_era_1;
    wire [8:0] wb_csr_esubcode_1;
    wire [5:0] wb_csr_ecode_1;

    wire wb_va_error_1;
    wire [`RegBus] wb_bad_va_1;
    wire excp_tlbrefill_1;
    wire [18:0] excp_tlb_vppn_1;

    mem_wb mem_wb_1 (
        .clk  (clk),
        .rst  (rst),
        .stall(stall1[5]),

        .mem_wd        (mem_reg_waddr_o_1),
        .mem_wreg      (mem_wreg_o_1),
        .mem_wdata     (mem_reg_wdata_o_1),
        .mem_inst_pc   (mem_inst_pc_1),
        .mem_instr     (),
        .mem_aluop     (mem_aluop_o_1),
        .mem_inst_valid(mem_inst_valid_1),

        .mem_LLbit_we(mem_LLbit_we_o_1),
        .mem_LLbit_value(mem_LLbit_value_o_1),

        .flush(flush),

        .mem_csr_we  (mem_csr_we_o_1),
        .mem_csr_addr(mem_csr_addr_o_1),
        .mem_csr_data(mem_csr_data_o_1),

        .wb_wd(wb_reg_waddr_1),
        .wb_wreg(wb_wreg_1),
        .wb_wdata(wb_reg_wdata_1),

        .wb_LLbit_we(wb_LLbit_we_i_1),
        .wb_LLbit_value(wb_LLbit_value_i_1),

        .wb_csr_we  (wb_csr_we_1),
        .wb_csr_addr(wb_csr_addr_1),
        .wb_csr_data(wb_csr_data_1),

        .debug_commit_pc   (debug_commit_pc_1),
        .debug_commit_valid(debug_commit_valid_1),
        .debug_commit_instr(debug_commit_instr_1),

        .excp_i(mem_excp_o_1),
        .excp_num_i(mem_excp_num_o_1),
        .excp_o(wb_excp_o_1),
        .excp_num_o(wb_excp_num_o_1),

        .csr_era(wb_csr_era_1),
        .csr_esubcode(wb_csr_esubcode_1),
        .csr_ecode(wb_csr_ecode_1),
        .excp_flush(excp_flush_1),
        .ertn_flush(ertn_flush_1),
        .va_error(wb_va_error_1),
        .bad_va(wb_bad_va_1),
        .excp_tlbrefill(excp_tlbrefill_1),
        .excp_tlb_vppn(excp_tlb_vppn_1)
    );

    wire wb_wreg_2;
    wire [`RegAddrBus] wb_reg_waddr_2;
    wire [`RegBus] wb_reg_wdata_2;

    wire wb_csr_we_2;
    wire [13:0] wb_csr_addr_2;
    wire [`RegBus] wb_csr_data_2;

    assign debug_commit_wreg_2 = wb_wreg_2;
    assign debug_commit_reg_waddr_2 = wb_reg_waddr_2;
    assign debug_commit_reg_wdata_2 = wb_reg_wdata_2;

    wire [`RegBus] wb_csr_era_2;
    wire [8:0] wb_csr_esubcode_2;
    wire [5:0] wb_csr_ecode_2;

    wire wb_va_error_2;
    wire [`RegBus] wb_bad_va_2;
    wire excp_tlbrefill_2;
    wire [18:0] excp_tlb_vppn_2;

    mem_wb mem_wb_2 (
        .clk  (clk),
        .rst  (rst),
        .stall(stall2[5]),

        .mem_wd        (mem_reg_waddr_o_2),
        .mem_wreg      (mem_wreg_o_2),
        .mem_wdata     (mem_reg_wdata_o_2),
        .mem_inst_pc   (mem_inst_pc_2),
        .mem_instr     (),
        .mem_aluop     (mem_aluop_o_2),
        .mem_inst_valid(mem_inst_valid_2),

        .mem_LLbit_we(mem_LLbit_we_o_2),
        .mem_LLbit_value(mem_LLbit_value_o_2),

        .flush(flush),

        .mem_csr_we  (mem_csr_we_o_2),
        .mem_csr_addr(mem_csr_addr_o_2),
        .mem_csr_data(mem_csr_data_o_2),

        .wb_wd(wb_reg_waddr_2),
        .wb_wreg(wb_wreg_2),
        .wb_wdata(wb_reg_wdata_2),

        .wb_LLbit_we(wb_LLbit_we_i),
        .wb_LLbit_value(wb_LLbit_value_2),

        .wb_csr_we  (wb_csr_we_2),
        .wb_csr_addr(wb_csr_addr_2),
        .wb_csr_data(wb_csr_data_2),

        .debug_commit_pc   (debug_commit_pc_2),
        .debug_commit_valid(debug_commit_valid_2),
        .debug_commit_instr(debug_commit_instr_2),

        .excp_i(mem_excp_o_2),
        .excp_num_i(mem_excp_num_o_2),
        .excp_o(wb_excp_o_2),
        .excp_num_o(wb_excp_num_o_2),

        .csr_era(wb_csr_era_2),
        .csr_esubcode(wb_csr_esubcode_2),
        .csr_ecode(wb_csr_ecode_2),
        .excp_flush(excp_flush_2),
        .ertn_flush(ertn_flush_2),
        .va_error(wb_va_error_2),
        .bad_va(wb_bad_va_2),
        .excp_tlbrefill(excp_tlbrefill_2),
        .excp_tlb_vppn(excp_tlb_vppn_2)
    );

    regfile u_regfile (
        .clk(clk),
        .rst(rst),

        .we_1   (wb_wreg_1),
        .pc_i_1 (),
        .waddr_1(wb_reg_waddr_1),
        .wdata_1(wb_reg_wdata_1),
        .we_2   (wb_wreg_2),
        .pc_i_2 (),
        .waddr_2(wb_reg_waddr_2),
        .wdata_2(wb_reg_wdata_2),

        .re1_1   (reg1_read_1),
        .raddr1_1(reg1_addr_1),
        .rdata1_1(reg1_data_1),
        .re2_1   (reg2_read_1),
        .raddr2_1(reg2_addr_1),
        .rdata2_1(reg2_data_1),
        .re1_2   (reg1_read_2),
        .raddr1_2(reg1_addr_2),
        .rdata1_2(reg1_data_2),
        .re2_2   (reg2_read_2),
        .raddr2_2(reg2_addr_2),
        .rdata2_2(reg2_data_2)
    );

    ctrl u_ctrl (
        .clk(clk),
        .rst(rst),
        .stall1(stall1),
        .stallreq_from_id_1(stallreq_from_id_1),
        .stallreq_from_ex_1(stallreq_from_ex_1),
        .stall2(stall2),
        .stallreq_from_id_2(stallreq_from_id_2),
        .stallreq_from_ex_2(stallreq_from_ex_2),
        .idle_stallreq(),
        .excepttype_i_1(mem_excepttype_o_1),
        .excepttype_i_2(mem_excepttype_o_2),
        .new_pc(new_pc),
        .flush(flush)
    );

    LLbit_reg u_LLbit_reg (
        .clk(clk),
        .rst(rst),
        .flush(1'b0),
        .LLbit_i_1(wb_LLbit_value_i_1),
        .LLbit_i_2(wb_LLbit_value_i_2),
        .we(wb_LLbit_we_i),
        .LLbit_o(LLbit_o)
    );


    //目前没有进行冲突处理，是假设不会同时出现两条异常同时发生
    assign wb_csr_era = wb_csr_era_1 | wb_csr_era_2;
    assign wb_csr_ecode = wb_csr_ecode_1 | wb_csr_ecode_2;
    assign wb_csr_esubcode = wb_csr_esubcode_1 | wb_csr_esubcode_2;
    assign excp_flush = excp_flush_1 | excp_flush_2;
    assign ertn_flush = ertn_flush_1 | ertn_flush_2;
    assign wb_va_error = wb_va_error_1 | wb_va_error_2;
    assign wb_bad_va = wb_bad_va_1 | wb_bad_va_2;
    assign excp_tlbrefill = excp_tlbrefill_1 | excp_tlbrefill_2;
    assign excp_tlb_vppn = excp_tlb_vppn_1 | excp_tlb_vppn_2;

    cs_reg u_cs_reg (
        .clk(clk),
        .rst(rst),
        .waddr_1(wb_csr_addr_1),
        .waddr_2(wb_csr_addr_2),
        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush),
        .we_1(wb_csr_we_1),
        .we_2(wb_csr_we_2),
        .wdata_1(wb_csr_data_1),
        .wdata_2(wb_csr_data_2),
        .raddr_1(id_csr_read_addr_o_1),
        .raddr_2(id_csr_read_addr_o_2),
        .rdata_1(id_csr_data_1),
        .rdata_2(id_csr_data_2),
        .era_i(wb_csr_era),
        .esubcode_i(wb_csr_esubcode),
        .va_error_i(wb_va_error),
        .bad_va_i(wb_bad_va),
        .tlbsrch_en(tlbsrch_en),
        .tlbsrch_found(tlbsrch_found),
        .tlbsrch_index(tlbsrch_index),
        .excp_tlbrefill(excp_tlbrefill),
        .excp_tlb(excp_tlb),
        .excp_tlb_vppn(excp_tlb_vppn),
        .has_int(has_int),
        .eentry_out(csr_eentry),
        .era_out(csr_era),
        .tlbrentry_out(csr_tlbrentry),
        .asid_out(csr_asid),
        .rand_index(rand_index),
        .tlbehi_out(tlbw_tlbehi),
        .tlbelo0_out(tlbw_tlbelo0),
        .tlbelo1_out(tlbw_tlbelo1),
        .tlbidx_out(tlbw_r_tlbidx),
        .pg_out(csr_pg),
        .da_out(csr_da),
        .dmw0_out(csr_dmw0),
        .dmw1_out(csr_dmw1),
        .datf_out(csr_datf),
        .datm_out(csr_datm),
        .ecode_out(tlbw_ecode),
        .tlbrd_en(tlbrd_en),
        .tlbehi_in(tlbr_tlbehi),
        .tlbelo0_in(tlbr_tlbelo0),
        .tlbelo1_in(tlbr_tlbelo1),
        .tlbidx_in(tlbr_tlbidx),
        .asid_in(tlbr_asid),
        .csr_diff(csr_diff)
    );


    assign data_addr_trans_en = data_addr_trans_en_1 | data_addr_trans_en_2;
    assign data_dmw0_en = data_dmw0_en_1 | data_dmw0_en_2;
    assign data_dmw1_en = data_dmw1_en_1 | data_dmw1_en_2;

    tlb u_tlb (
        .clk               (clk),
        .asid              (csr_asid),
        //trans mode 
        .inst_addr_trans_en(inst_addr_trans_en),
        .data_addr_trans_en(data_addr_trans_en),
        //inst addr trans
        .inst_fetch        (fetch_en),
        .inst_vaddr        (inst_vaddr),
        .inst_dmw0_en      (inst_dmw0_en),
        .inst_dmw1_en      (inst_dmw1_en),
        .inst_index        (inst_index),
        .inst_tag          (inst_tag),
        .inst_offset       (inst_offset),
        .inst_tlb_found    (inst_tlb_found),
        .inst_tlb_v        (inst_tlb_v),
        .inst_tlb_d        (inst_tlb_d),
        .inst_tlb_mat      (inst_tlb_mat),
        .inst_tlb_plv      (inst_tlb_plv),
        //data addr trans 
        .data_fetch        (data_fetch),
        .data_vaddr        (data_vaddr),
        .data_dmw0_en      (data_dmw0_en),
        .data_dmw1_en      (data_dmw1_en),
        .cacop_op_mode_di  (cacop_op_mode_di),
        .data_index        (data_index),
        .data_tag          (data_tag),
        .data_offset       (data_offset),
        .data_tlb_found    (data_tlb_found),
        .data_tlb_index    (data_tlb_index),
        .data_tlb_v        (data_tlb_v),
        .data_tlb_d        (data_tlb_d),
        .data_tlb_mat      (data_tlb_mat),
        .data_tlb_plv      (data_tlb_plv),
        //tlbwr tlbfill tlb write 
        .tlbfill_en        (tlbfill_en),
        .tlbwr_en          (tlbwr_en),
        .rand_index        (rand_index),
        .tlbehi_in         (tlbw_tlbehi),
        .tlbelo0_in        (tlbw_tlbelo0),
        .tlbelo1_in        (tlbw_tlbelo1),
        .tlbidx_in         (tlbw_r_tlbidx),
        .ecode_in          (tlbw_ecode),
        //tlbp tlb read
        .tlbehi_out        (tlbr_tlbehi),
        .tlbelo0_out       (tlbr_tlbelo0),
        .tlbelo1_out       (tlbr_tlbelo1),
        .tlbidx_out        (tlbr_tlbidx),
        .asid_out          (tlbr_asid),
        //invtlb 
        .invtlb_en         (invtlb_en),
        .invtlb_asid       (invtlb_asid),
        .invtlb_vpn        (invtlb_vpn),
        .invtlb_op         (invtlb_op),
        //from csr
        .csr_dmw0          (csr_dmw0),
        .csr_dmw1          (csr_dmw1),
        .csr_da            (csr_da),
        .csr_pg            (csr_pg)
    );

    // Difftest DPI-C
`ifdef SIMU  // SIMU is defined in chiplab run_func/Makefile
    DifftestInstrCommit difftest_instr_commit_0 (  // TODO: not finished yet, blank signal is needed
        .clock         (aclk),
        .coreid        (0),                          // Only one core, so always 0
        .index         (0),                          // Commit channel index
        .valid         (~debug_commit_valid_1),      // TODO: flip valid definition in CPU
        .pc            (debug_commit_pc_1),
        .instr         (debug_commit_instr_1),
        .skip          (0),                          // Not sure meaning, but keep 0 for now
        .is_TLBFILL    (),
        .TLBFILL_index (),
        .is_CNTinst    (),
        .timer_64_value(),
        .wen           (debug0_wb_rf_wen),
        .wdest         ({3'b0, debug0_wb_rf_wnum}),
        .wdata         (debug0_wb_rf_wdata),
        .csr_rstat     (),
        .csr_data      ()
    );

    DifftestCSRRegState difftest_csr_state (
        .clock    (aclk),
        .coreid   (0),                       // Only one core, so always 0
        .crmd     (u_cs_reg.csr_crmd),
        .prmd     (u_cs_reg.csr_prmd),
        .euen     (0),                       // TODO: Not sure meaning
        .ecfg     (u_cs_reg.csr_ectl),       // ectl
        .estat    (u_cs_reg.csr_estat),
        .era      (u_cs_reg.csr_era),
        .badv     (u_cs_reg.csr_badv),
        .eentry   (u_cs_reg.csr_eentry),
        .tlbrentry(u_cs_reg.csr_tlbrentry),
        .tlbidx   (u_cs_reg.csr_tlbidx),
        .tlbehi   (u_cs_reg.csr_tlbehi),
        .tlbelo0  (u_cs_reg.csr_tlbelo0),
        .tlbelo1  (u_cs_reg.csr_tlbelo1),
        .asid     (u_cs_reg.csr_asid),
        .pgdl     (u_cs_reg.csr_pgdl),
        .pgdh     (u_cs_reg.csr_pgdh),
        .save0    (u_cs_reg.csr_save0),
        .save1    (u_cs_reg.csr_save1),
        .save2    (u_cs_reg.csr_save2),
        .save3    (u_cs_reg.csr_save3),
        .tid      (u_cs_reg.csr_tid),
        .tcfg     (u_cs_reg.csr_tcfg),
        .tval     (u_cs_reg.csr_tval),
        .ticlr    (u_cs_reg.csr_ticlr),
        .llbctl   (u_cs_reg.csr_llbctl),
        .dmw0     (u_cs_reg.csr_dmw0),
        .dmw1     (u_cs_reg.csr_dmw1)
    );


    DifftestGRegState difftest_gpr_state (
        .clock (aclk),
        .coreid(0),
        .gpr_0 (0),
        .gpr_1 (u_regfile.regs[1]),
        .gpr_2 (u_regfile.regs[2]),
        .gpr_3 (u_regfile.regs[3]),
        .gpr_4 (u_regfile.regs[4]),
        .gpr_5 (u_regfile.regs[5]),
        .gpr_6 (u_regfile.regs[6]),
        .gpr_7 (u_regfile.regs[7]),
        .gpr_8 (u_regfile.regs[8]),
        .gpr_9 (u_regfile.regs[9]),
        .gpr_10(u_regfile.regs[10]),
        .gpr_11(u_regfile.regs[11]),
        .gpr_12(u_regfile.regs[12]),
        .gpr_13(u_regfile.regs[13]),
        .gpr_14(u_regfile.regs[14]),
        .gpr_15(u_regfile.regs[15]),
        .gpr_16(u_regfile.regs[16]),
        .gpr_17(u_regfile.regs[17]),
        .gpr_18(u_regfile.regs[18]),
        .gpr_19(u_regfile.regs[19]),
        .gpr_20(u_regfile.regs[20]),
        .gpr_21(u_regfile.regs[21]),
        .gpr_22(u_regfile.regs[22]),
        .gpr_23(u_regfile.regs[23]),
        .gpr_24(u_regfile.regs[24]),
        .gpr_25(u_regfile.regs[25]),
        .gpr_26(u_regfile.regs[26]),
        .gpr_27(u_regfile.regs[27]),
        .gpr_28(u_regfile.regs[28]),
        .gpr_29(u_regfile.regs[29]),
        .gpr_30(u_regfile.regs[30]),
        .gpr_31(u_regfile.regs[31])
    );
`endif


endmodule
