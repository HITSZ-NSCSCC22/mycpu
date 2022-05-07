`include "defines.sv"
`include "instr_info.sv"
`include "regfile.sv"
`include "csr_defines.sv"
`include "cs_reg.sv"
`include "tlb.sv"
`include "tlb_entry.sv"
`include "AXI/axi_master.sv"
`include "frontend/frontend.sv"
`include "instr_buffer.sv"
`include "dummy_icache.sv"
`include "LLbit_reg.sv"
`include "ctrl.sv"
`include "pipeline_defines.sv"
`include "pipeline/1_decode/id.sv"
`include "pipeline/1_decode/id_dispatch.sv"
`include "pipeline/3_execution/ex.sv"
`include "pipeline/3_execution/ex_mem.sv"
`include "pipeline/4_mem/mem.sv"
`include "pipeline/4_mem/mem_wb.sv"

module cpu_top (
    input logic aclk,
    input logic aresetn,

    input logic [7:0] intrpt,  // External interrupt

    // AXI interface 
    // read request
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
    // write back
    input  [ 3:0] bid,
    input  [ 1:0] bresp,
    input         bvalid,
    output        bready,
    // debug info
    output [31:0] debug0_wb_pc,
    output [ 3:0] debug0_wb_rf_wen,
    output [ 4:0] debug0_wb_rf_wnum,
    output [31:0] debug0_wb_rf_wdata
);

    // Clock signal
    logic clk;
    assign clk = aclk;

    // Reset signal
    logic rst_n;
    logic rst;
    assign rst_n = aresetn;
    assign rst   = ~rst_n;

    // Global enable signal
    logic chip_enable;

    logic branch_flag_1;
    logic branch_flag_2;
    logic Instram_branch_flag;
    assign Instram_branch_flag = branch_flag_1 | branch_flag_2;

    logic axi_busy;
    logic [`RegBus] axi_data;
    logic [`RegBus] axi_addr;

    logic data_axi_we;
    logic data_axi_ce;
    logic [3:0] data_axi_sel;
    logic [`RegAddrBus] data_axi_addr;
    logic [`RegBus] data_axi_data;
    logic data_axi_busy;

    logic data_axi_we_1;
    logic data_axi_ce_1;
    logic [3:0] data_axi_sel_1;
    logic [`RegAddrBus] data_axi_addr_1;
    logic [`RegBus] data_axi_data_1;

    logic data_axi_we_2;
    logic data_axi_ce_2;
    logic [3:0] data_axi_sel_2;
    logic [`RegAddrBus] data_axi_addr_2;
    logic [`RegBus] data_axi_data_2;

    assign data_axi_we = data_axi_we_1 | data_axi_we_2;
    assign data_axi_ce = data_axi_ce_1 | data_axi_ce_2;
    assign data_axi_sel = data_axi_we_1 ? data_axi_sel_1 : data_axi_we_2 ? data_axi_sel_2 : 4'b0;
    assign data_axi_addr = data_axi_we_1 ? data_axi_addr_1 : data_axi_we_2 ? data_axi_addr_2 : 5'b0;
    assign data_axi_data = data_axi_we_1 ? data_axi_data_1 : data_axi_we_2 ? data_axi_data_2 : 32'b0;

    axi_master u_axi_master (
        .aclk   (aclk),
        .aresetn(aresetn),

        .inst_cpu_addr_i(axi_addr),
        .inst_cpu_ce_i(axi_addr != 0),  // FIXME: ce should not be used as valid?
        .inst_cpu_data_i(0),
        .inst_cpu_we_i(1'b0),
        .inst_cpu_sel_i(4'b1111),
        .inst_stall_i(Instram_branch_flag),
        .inst_flush_i(Instram_branch_flag),
        .inst_cpu_data_o(axi_data),
        .inst_stallreq(axi_busy),
        .inst_id(4'b0000),  // Read Instruction only, TODO: move this from AXI to cache

        .data_cpu_addr_i(data_axi_addr),
        .data_cpu_ce_i(data_axi_addr != 0),  // FIXME: ce should not be used as valid?
        .data_cpu_data_i(0),
        .data_cpu_we_i(1'b0),
        .data_cpu_sel_i(4'b1111),
        .data_stall_i(),
        .data_flush_i(),
        .data_cpu_data_o(data_axi_data),
        .data_stallreq(data_axi_busy),
        .data_id(4'b0000),

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

    // FETCH_WIDTH is 2
    localparam FETCH_WIDTH = 2;
    // Frontend -> ICache
    logic [`InstAddrBus] frontend_icache_addr[FETCH_WIDTH];

    // ICache -> Frontend
    logic icache_frontend_stallreq;
    logic icache_frontend_valid[FETCH_WIDTH];
    logic [`InstAddrBus] icache_frontend_addr[FETCH_WIDTH];
    logic [`RegBus] icache_frontend_data[FETCH_WIDTH];


    dummy_icache #(
        .ADDR_WIDTH(`RegWidth),
        .DATA_WIDTH(`RegWidth)
    ) u_dummy_icache (
        .clk(clk),
        .rst(rst),

        // <-> Frontend
        .raddr_1_i (frontend_icache_addr[0]),
        .raddr_2_i (frontend_icache_addr[1]),
        .stallreq_o(icache_frontend_stallreq),
        .rvalid_1_o(icache_frontend_valid[0]),
        .rvalid_2_o(icache_frontend_valid[1]),
        .raddr_1_o (icache_frontend_addr[0]),
        .raddr_2_o (icache_frontend_addr[1]),
        .rdata_1_o (icache_frontend_data[0]),
        .rdata_2_o (icache_frontend_data[1]),

        // <-> AXI Controller
        .axi_addr_o(axi_addr),
        .axi_data_i(axi_data),
        .axi_busy_i(axi_busy)
    );

    // Frontend <-> Instruction Buffer
    logic ib_frontend_stallreq;
    instr_buffer_info_t frontend_ib_instr_info[FETCH_WIDTH];
    logic [`RegBus] next_pc;

    // All frontend structures
    frontend u_frontend (
        .clk(clk),
        .rst(rst),

        // <-> ICache
        .icache_read_addr_o (frontend_icache_addr),
        .icache_stallreq_i  (icache_frontend_stallreq),
        .icache_read_valid_i(icache_frontend_valid),
        .icache_read_addr_i (icache_frontend_addr),
        .icache_read_data_i (icache_frontend_data),

        // <-> Backend
        .branch_update_info_i(),
        .backend_next_pc_i   (next_pc),
        .backend_flush_i     (backend_flush),

        // <-> Instruction Buffer
        .instr_buffer_stallreq_i(ib_frontend_stallreq),
        .instr_buffer_o         (frontend_ib_instr_info)
    );

    logic backend_flush;
    instr_buffer_info_t ib_backend_instr_info[2];  // IB -> ID

    // Instruction Buffer
    // FIFO buffer
    instr_buffer #(
        .IF_WIDTH(FETCH_WIDTH),
        .ID_WIDTH(2)             // TODO: remove magic number
    ) u_instr_buffer (
        .clk(clk),
        .rst(rst),

        // <-> Frontend
        .frontend_instr_i   (frontend_ib_instr_info),
        .frontend_stallreq_o(ib_frontend_stallreq),

        // <-> Backend
        .backend_accept_i(2'b11),  // 1 means valid 
        .backend_flush_i(backend_flush),
        .backend_instr_o(ib_backend_instr_info)
    );

    // ID <-> Regfile
    logic [1:0] id_regfile_reg_read_valid[2];
    logic [`RegNumLog2*2-1:0] id_regfile_reg_read_addr[2];
    logic [1:0][1:0][`RegBus] regfile_id_reg_read_data;

    // ID -> ID_DISPATCH
    id_dispatch_struct [1:0] id_id_dispatch;

    // ID Stage
    generate
        genvar i;
        for (i = 0; i < 2; i++) begin : id
            id #(
                .EXE_STAGE_WIDTH(2),  // Obviously 2 for now
                .MEM_STAGE_WIDTH(2)
            ) u_id (
                .instr_buffer_i(ib_backend_instr_info[i]),
                // FIXME: excp info, currently unused
                .excp_i        (),
                .excp_num_i    (),

                // <-> Regfile
                .regfile_reg_read_valid_o(id_regfile_reg_read_valid[i]),
                .regfile_reg_read_addr_o (id_regfile_reg_read_addr[i]),
                .regfile_reg_read_data_i (regfile_id_reg_read_data[i]),

                // Data forwarding network, unused for now
                // TODO: add data forwarding network
                .ex_write_reg_valid_i (),
                .ex_write_reg_addr_i  (),
                .ex_write_reg_data_i  (),
                .ex_aluop_i           (),
                .mem_write_reg_valid_i(),
                .mem_write_reg_addr_i (),
                .mem_write_reg_data_i (),

                // -> Dispatch
                .dispatch_o(id_id_dispatch[i]),

                // Exception broadcast
                .broadcast_excp_o    (),
                .broadcast_excp_num_o(),

                // <-> CSR Registers
                .has_int        (),
                .csr_data_i     (),
                .csr_plv        (),
                .csr_read_addr_o()
            );
        end
    endgenerate

    // ID_DISPATCH -> EXE
    id_dispatch_struct [1:0] id_dispatch_exe;


    // ID_DISPATCH
    id_dispatch u_id_dispatch (
        .clk       (clk),
        .rst       (rst),
        .stall     (),
        .flush     (),
        .id_i      (id_id_dispatch),
        .dispatch_o(id_dispatch_exe)
    );




    logic [`RegBus] branch_target_address_1;
    logic [`RegBus] branch_target_address_2;
    logic [`RegBus] link_addr;
    logic flush;
    logic [`RegBus] new_pc;
    logic [6:0] stall1;  // [pc_reg,if_buffer_1, if_id, id_ex, ex_mem, mem_wb, ctrl]
    logic [6:0] stall2;


    //tlb
    logic inst_addr_trans_en;
    logic data_addr_trans_en;
    logic fetch_en;
    logic [31:0] inst_vaddr;
    logic inst_dmw0_en;
    logic inst_dmw1_en;
    logic [7:0] inst_index;
    logic [19:0] inst_tag;
    logic [3:0] inst_offset;
    logic inst_tlb_found;
    logic inst_tlb_v;
    logic inst_tlb_d;
    logic [1:0] inst_tlb_mat;
    logic [1:0] inst_tlb_plv;
    logic data_fetch;
    logic [31:0] data_vaddr;
    logic data_dmw0_en;
    logic data_dmw1_en;
    logic cacop_op_mode_di;
    logic [7:0] data_index;
    logic [19:0] data_tag;
    logic [3:0] data_offset;
    logic data_tlb_found;
    logic [4:0] data_tlb_index;
    logic data_tlb_v;
    logic data_tlb_d;
    logic [1:0] data_tlb_mat;
    logic [1:0] data_tlb_plv;
    logic tlbfill_en;
    logic tlbwr_en;
    logic [4:0] rand_index;
    logic [31:0] tlbw_tlbehi;
    logic [31:0] tlbw_tlbelo0;
    logic [31:0] tlbw_tlbelo1;
    logic [31:0] tlbw_r_tlbidx;
    logic [5:0] tlbw_ecode;
    logic [31:0] tlbr_tlbehi;
    logic [31:0] tlbr_tlbelo0;
    logic [31:0] tlbr_tlbelo1;
    logic [31:0] tlbr_tlbidx;
    logic [9:0] tlbr_asid;
    logic invtlb_en;
    logic [9:0] invtlb_asid;
    logic [18:0] invtlb_vpn;
    logic [4:0] invtlb_op;

    //csr
    logic has_int;
    logic excp_flush;
    logic ertn_flush;
    logic [31:0] wb_csr_era;
    logic [8:0] wb_csr_esubcode;
    logic [5:0] wb_csr_ecode;
    logic wb_va_error;
    logic [31:0] wb_bad_va;
    logic tlbsrch_en;
    logic tlbsrch_found;
    logic [4:0] tlbsrch_index;
    logic excp_tlbrefill;
    logic excp_tlb;
    logic [18:0] excp_tlb_vppn;
    logic csr_llbit_i;
    logic csr_llbit_set_i;
    logic csr_llbit_o;
    logic csr_llbit_set_o;
    logic [`RegBus] csr_eentry;
    logic [31:0] csr_tlbrentry;
    logic [`RegBus] csr_era;

    logic [9:0] csr_asid;
    logic csr_pg;
    logic csr_da;
    logic [31:0] csr_dmw0;
    logic [31:0] csr_dmw1;
    logic [1:0] csr_datf;
    logic [1:0] csr_datm;
    logic [1:0] csr_plv;

    logic [13:0] id_csr_addr_1;
    logic [31:0] id_csr_data_1;
    logic [13:0] id_csr_addr_2;
    logic [31:0] id_csr_data_2;
    logic [13:0] id_csr_read_addr_o_1;
    logic [13:0] id_csr_read_addr_o_2;

    logic pc_excp_o;
    logic [3:0] pc_excp_num_o;

    logic idle_flush;
    logic [`InstAddrBus] idle_pc;
    logic excp_flush_1;
    logic ertn_flush_1;
    logic excp_flush_2;
    logic ertn_flush_2;

    assign excp_flush = excp_flush_1 | excp_flush_2;
    assign ertn_flush = ertn_flush_1 | ertn_flush_2;

    logic [`RegBus] id_csr_data_i_1;
    logic [`RegBus] id_csr_data_i_2;

    logic disable_cache;

    assign backend_flush = excp_flush | ertn_flush | branch_flag_1 | branch_flag_2;

    assign next_pc = branch_flag_1 ? branch_target_address_1 : 
                     branch_flag_2 ? branch_target_address_2 :
                     (excp_flush && !excp_tlbrefill) ? csr_eentry :
                     (excp_flush && excp_tlbrefill) ? csr_tlbrentry :
                     ertn_flush ? csr_era : `ZeroWord;

    logic if_inst_valid_1;
    logic if_inst_valid_2;
    logic if_excp_i_1;
    logic [3:0] if_excp_num_i_1;
    logic if_excp_i_2;
    logic [3:0] if_excp_num_i_2;



    logic [`InstAddrBus] id_pc_1;
    logic [`InstBus] id_inst_1;
    logic [`InstAddrBus] id_pc_2;
    logic [`InstBus] id_inst_2;

    logic if_excp_o_1;
    logic [3:0] if_excp_num_o_1;
    logic if_excp_o_2;
    logic [3:0] if_excp_num_o_2;


    logic [`AluOpBus] id_aluop_1;
    logic [`AluSelBus] id_alusel_1;
    logic [`RegBus] id_reg1_1;
    logic [`RegBus] id_reg2_1;
    logic [`RegAddrBus] id_reg_waddr_1;
    logic id_wreg_1;
    logic id_inst_valid_1;
    logic [`InstAddrBus] id_inst_pc_1;
    logic [`RegBus] id_inst_o_1;

    logic reg1_read_1;
    logic reg2_read_1;
    logic [`RegAddrBus] reg1_addr_1;
    logic [`RegAddrBus] reg2_addr_1;
    logic [`RegBus] reg1_data_1;
    logic [`RegBus] reg2_data_1;

    logic ex_wreg_o_1;
    logic [`RegAddrBus] ex_reg_waddr_o_1;
    logic [`RegBus] ex_reg_wdata_1;
    logic [`AluOpBus] ex_aluop_o_1;

    logic mem_wreg_o_1;
    logic [`RegAddrBus] mem_reg_waddr_o_1;
    logic [`RegBus] mem_reg_wdata_o_1;

    logic stallreq_from_id_1;
    logic stallreq_from_ex_1;

    logic [1:0] id_excepttype_o_1;
    logic [`RegBus] id_current_inst_address_o_1;

    logic ex_wreg_o_2;
    logic [`RegAddrBus] ex_reg_waddr_o_2;
    logic [`RegBus] ex_reg_wdata_2;
    logic [`AluOpBus] ex_aluop_o_2;

    logic mem_wreg_o_2;
    logic [`RegAddrBus] mem_reg_waddr_o_2;
    logic [`RegBus] mem_reg_wdata_o_2;

    logic [`RegAddrBus] reg1_addr_2;
    logic [`RegAddrBus] reg2_addr_2;

    logic [`RegBus] link_addr_1;
    logic [`RegBus] link_addr_2;

    logic [`RegAddrBus] id_reg_waddr_2;

    logic stallreq_to_next_1;
    logic stallreq_to_next_2;

    logic id_excp_o_1;
    logic [8:0] id_excp_num_o_1;
    logic id_excp_o_2;
    logic [8:0] id_excp_num_o_2;

    csr_write_signal id_csr_signal_o_1;
    csr_write_signal id_csr_signal_o_2;



    logic ex_inst_valid_o_1;
    logic [`InstAddrBus] ex_inst_pc_o_1;
    logic [`RegBus] ex_addr_o_1;
    logic [`RegBus] ex_reg2_o_1;
    logic [1:0] ex_excepttype_o_1;
    logic [`RegBus] ex_current_inst_address_o_1;
    csr_write_signal ex_csr_signal_o_1;
    csr_write_signal ex_csr_signal_o_2;



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
        .csr_signal_i(ex_csr_signal_i_1),

        .wreg_o(ex_wreg_o_1),
        .wd_o(ex_reg_waddr_o_1),
        .wdata_o(ex_reg_wdata_1),
        .inst_valid_o(ex_inst_valid_o_1),
        .inst_pc_o(ex_inst_pc_o_1),
        .aluop_o(ex_aluop_o_1),
        .mem_addr_o(ex_addr_o_1),
        .reg2_o(ex_reg2_o_1),
        .excepttype_o(ex_excepttype_o_1),
        .current_inst_address_o(ex_current_inst_address_o_1),
        .csr_signal_o(ex_csr_signal_o_1),

        .stallreq(stallreq_from_ex_1),

        .excp_i(ex_excp_i_1),
        .excp_num_i(ex_excp_num_i_1),
        .excp_o(ex_excp_o_1),
        .excp_num_o(ex_excp_num_o_1)
    );

    logic ex_inst_valid_o_2;
    logic [`InstAddrBus] ex_inst_pc_o_2;
    logic [`RegBus] ex_addr_o_2;
    logic [`RegBus] ex_reg2_o_2;
    logic [1:0] ex_excepttype_o_2;
    logic [`RegBus] ex_current_inst_address_o_2;
    logic ex_csr_we_o_2;
    logic [13:0] ex_csr_addr_o_2;
    logic [31:0] ex_csr_data_o_2;


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
        .csr_signal_i(ex_csr_signal_i_2),

        .wreg_o(ex_wreg_o_2),
        .wd_o(ex_reg_waddr_o_2),
        .wdata_o(ex_reg_wdata_2),
        .inst_valid_o(ex_inst_valid_o_2),
        .inst_pc_o(ex_inst_pc_o_2),
        .aluop_o(ex_aluop_o_2),
        .mem_addr_o(ex_addr_o_2),
        .reg2_o(ex_reg2_o_2),
        .excepttype_o(ex_excepttype_o_2),
        .current_inst_address_o(ex_current_inst_address_o_2),
        .csr_signal_o(ex_csr_signal_o_2),

        .stallreq(stallreq_from_ex_2),

        .excp_i(ex_excp_i_2),
        .excp_num_i(ex_excp_num_i_2),
        .excp_o(ex_excp_o_2),
        .excp_num_o(ex_excp_num_o_2)
    );


    logic mem_wreg_i_1;
    logic [`RegAddrBus] mem_reg_waddr_i_1;
    logic [`RegBus] mem_reg_wdata_i_1;

    logic mem_inst_valid_1;
    logic [`InstAddrBus] mem_inst_pc_1;

    logic [`AluOpBus] mem_aluop_i_1;
    logic [`RegBus] mem_addr_i_1;
    logic [`RegBus] mem_reg2_i_1;
    logic [1:0] mem_excepttype_i_1;
    logic [`RegBus] mem_current_inst_address_i_1;

    csr_write_signal mem_csr_signal_i_1;
    csr_write_signal mem_csr_signal_i_2;

    logic mem_excp_i_1;
    logic [9:0] mem_excp_num_i_1;
    logic mem_excp_i_2;
    logic [9:0] mem_excp_num_i_2;

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
        .ex_csr_signal_o        (ex_csr_signal_o_1),

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
        .mem_csr_signal_i        (mem_csr_signal_i_1),

        .excp_i(ex_excp_o_1),
        .excp_num_i(ex_excp_num_o_1),
        .excp_o(mem_excp_i_1),
        .excp_num_o(mem_excp_num_i_1),

        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush)

    );


    logic mem_wreg_i_2;
    logic [`RegAddrBus] mem_reg_waddr_i_2;
    logic [`RegBus] mem_reg_wdata_i_2;

    logic mem_inst_valid_2;
    logic [`InstAddrBus] mem_inst_pc_2;

    logic [`AluOpBus] mem_aluop_i_2;
    logic [`RegBus] mem_addr_i_2;
    logic [`RegBus] mem_reg2_i_2;
    logic [1:0] mem_excepttype_i_2;
    logic [`RegBus] mem_current_inst_address_i_2;
    logic mem_csr_we_i_2;
    logic [13:0] mem_csr_addr_i_2;
    logic [31:0] mem_csr_data_i_2;


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
        .ex_csr_signal_o        (ex_csr_signal_o_2),

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
        .mem_csr_signal_i        (mem_csr_signal_i_2),

        .excp_i(ex_excp_o_2),
        .excp_num_i(ex_excp_num_o_2),
        .excp_o(mem_excp_i_2),
        .excp_num_o(mem_excp_num_i_2),

        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush)

    );

    logic LLbit_o_1;
    logic wb_LLbit_we_i_1;
    logic wb_LLbit_value_i_1;
    logic mem_LLbit_we_o_1;
    logic mem_LLbit_value_o_1;
    logic [1:0] mem_excepttype_o_1;
    logic [1:0] mem_excepttype_o_2;
    logic [`RegBus] mem_current_inst_address_o_1;
    logic [`InstAddrBus] wb_inst_pc_1;
    csr_write_signal mem_csr_signal_o_1;
    csr_write_signal mem_csr_signal_o_2;

    logic mem_excp_o_1;
    logic [15:0] mem_excp_num_o_1;
    logic mem_excp_o_2;
    logic [15:0] mem_excp_num_o_2;

    logic [`AluOpBus] mem_aluop_o_1;
    logic [`AluOpBus] mem_aluop_o_2;

    logic data_addr_trans_en_1;
    logic data_dmw0_en_1;
    logic data_dmw1_en_1;

    logic data_addr_trans_en_2;
    logic data_dmw0_en_2;
    logic data_dmw1_en_2;



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

        .csr_signal_i(mem_csr_signal_i_1),

        .inst_pc_o(wb_inst_pc_1),
        .wd_o     (mem_reg_waddr_o_1),
        .wreg_o   (mem_wreg_o_1),
        .wdata_o  (mem_reg_wdata_o_1),
        .aluop_o  (mem_aluop_i_1),

        .mem_addr_o(data_axi_addr_1),
        .mem_we_o  (data_axi_we_1),
        .mem_sel_o (data_axi_sel_1),
        .mem_data_o(data_axi_data_1),
        .mem_ce_o  (data_axi_ce_1),

        .LLbit_we_o(mem_LLbit_we_o_1),
        .LLbit_value_o(mem_LLbit_value_o_1),

        .excepttype_o(mem_excepttype_o_1),
        .current_inst_address_o(mem_current_inst_address_o_1),

        .csr_signal_o(mem_csr_signal_o_1),

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

    logic LLbit_o_2;
    logic wb_LLbit_we_i_2;
    logic wb_LLbit_value_i_2;
    logic mem_LLbit_we_o_2;
    logic mem_LLbit_value_o_2;
    logic [`RegBus] mem_current_inst_address_o_2;
    logic [`InstAddrBus] wb_inst_pc_2;
    logic mem_csr_we_o_2;
    logic [13:0] mem_csr_addr_o_2;
    logic [31:0] mem_csr_data_o_2;



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

        .csr_signal_i(mem_csr_signal_i_2),

        .inst_pc_o(wb_inst_pc_2),
        .wd_o     (mem_reg_waddr_o_2),
        .wreg_o   (mem_wreg_o_2),
        .wdata_o  (mem_reg_wdata_o_2),
        .aluop_o  (mem_aluop_o_2),

        .mem_addr_o(data_axi_addr_2),
        .mem_we_o  (data_axi_we_2),
        .mem_sel_o (data_axi_sel_2),
        .mem_data_o(data_axi_data_2),
        .mem_ce_o  (data_axi_ce_2),

        .LLbit_we_o(mem_LLbit_we_o_2),
        .LLbit_value_o(mem_LLbit_value_o_2),

        .excepttype_o(mem_excepttype_o_2),
        .current_inst_address_o(mem_current_inst_address_o_2),

        .csr_signal_o(mem_csr_signal_o_2),

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

    logic wb_wreg_1;
    logic [`RegAddrBus] wb_reg_waddr_1;
    logic [`RegBus] wb_reg_wdata_1;

    logic wb_csr_we_1;
    logic [13:0] wb_csr_addr_1;
    logic [`RegBus] wb_csr_data_1;

    logic [8:0] wb_csr_esubcode_1;
    logic [5:0] wb_csr_ecode_1;

    assign debug0_wb_rf_wen   = wb_wreg_1;
    assign debug0_wb_rf_wnum  = wb_reg_waddr_1;
    assign debug0_wb_rf_wdata = wb_reg_wdata_1;


    logic wb_excp_o_1;
    logic [15:0] wb_excp_num_o_1;
    logic wb_excp_o_2;
    logic [15:0] wb_excp_num_o_2;

    csr_write_signal wb_csr_signal_o_1;
    csr_write_signal wb_csr_signal_o_2;

    logic wb_va_error_1;
    logic [`RegBus] wb_bad_va_1;
    logic excp_tlbrefill_1;
    logic [18:0] excp_tlb_vppn_1;

    logic [`InstAddrBus] debug_commit_pc_1;

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

        .mem_csr_signal_o(mem_csr_signal_o_1),

        .wb_wd(wb_reg_waddr_1),
        .wb_wreg(wb_wreg_1),
        .wb_wdata(wb_reg_wdata_1),

        .wb_LLbit_we(wb_LLbit_we_i_1),
        .wb_LLbit_value(wb_LLbit_value_i_1),


        .debug_commit_pc   (debug_commit_pc_1),
        .debug_commit_valid(debug_commit_valid_1),
        .debug_commit_instr(debug_commit_instr_1),

        .excp_i(mem_excp_o_1),
        .excp_num_i(mem_excp_num_o_1),
        .excp_o(wb_excp_o_1),
        .excp_num_o(wb_excp_num_o_1),

        .wb_csr_signal_o(wb_csr_signal_o_1),
        .excp_flush(excp_flush_1),
        .ertn_flush(ertn_flush_1),
        .va_error(wb_va_error_1),
        .bad_va(wb_bad_va_1),
        .excp_tlbrefill(excp_tlbrefill_1),
        .excp_tlb_vppn(excp_tlb_vppn_1)
    );

    logic wb_wreg_2;
    logic [`RegAddrBus] wb_reg_waddr_2;
    logic [`RegBus] wb_reg_wdata_2;

    logic wb_csr_we_2;
    logic [13:0] wb_csr_addr_2;
    logic [`RegBus] wb_csr_data_2;

    assign debug_commit_wreg_2 = wb_wreg_2;
    assign debug_commit_reg_waddr_2 = wb_reg_waddr_2;
    assign debug_commit_reg_wdata_2 = wb_reg_wdata_2;

    logic [`RegBus] wb_csr_era_2;
    logic [8:0] wb_csr_esubcode_2;
    logic [5:0] wb_csr_ecode_2;

    logic wb_va_error_2;
    logic [`RegBus] wb_bad_va_2;
    logic excp_tlbrefill_2;
    logic [18:0] excp_tlb_vppn_2;
    logic wb_csr_era_1;

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

        .mem_csr_signal_o(mem_csr_signal_o_2),

        .wb_wd(wb_reg_waddr_2),
        .wb_wreg(wb_wreg_2),
        .wb_wdata(wb_reg_wdata_2),

        .wb_LLbit_we(wb_LLbit_we_i),
        .wb_LLbit_value(wb_LLbit_value_2),

        .wb_csr_signal_o(wb_csr_signal_o_2),

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

    regfile #(
        .READ_PORTS(4)  // 2 for each ID, 2 ID in total, TODO: remove magic number
    ) u_regfile (
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

        // Read signals
        .read_valid_i({id_regfile_reg_read_valid[1], id_regfile_reg_read_valid[0]}),
        .read_addr_i ({id_regfile_reg_read_addr[1], id_regfile_reg_read_addr[0]}),
        .read_data_o (regfile_id_reg_read_data)
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
        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush),
        .write_signal_1(wb_csr_signal_o_1),
        .write_signal_2(wb_csr_signal_o_2),
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
        .clk               (),
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
    logic [`RegBus] debug_commit_pc_1_delay_1;
    logic debug_commit_valid_1_delay_1;
    always_ff @(posedge clk) begin
        debug_commit_valid_1_delay_1 <= debug_commit_valid_1;
        debug_commit_pc_1_delay_1 <= debug_commit_pc_1;
    end
    DifftestInstrCommit difftest_instr_commit_0 (  // TODO: not finished yet, blank signal is needed
        .clock         (aclk),
        .coreid        (0),                             // Only one core, so always 0
        .index         (0),                             // Commit channel index
        .valid         (debug_commit_valid_1_delay_1),  // 1 means valid
        .pc            (debug_commit_pc_1_delay_1),
        .instr         (debug_commit_instr_1),
        .skip          (0),                             // Not sure meaning, but keep 0 for now
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

    // Assume regilfe instance name is u_regfile
    // and architectural register are under regs[] array
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
