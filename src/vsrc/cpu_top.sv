`include "defines.sv"
`include "core_types.sv"
`include "core_config.sv"
`include "csr_defines.sv"
`include "frontend/frontend_defines.sv"

`include "cs_reg.sv"
`include "tlb.sv"
`include "tlb_entry.sv"
`include "AXI/axi_master.sv"
`include "frontend/frontend.sv"
`include "instr_buffer.sv"
`include "icache.sv"
`include "dummy_dcache.sv"
`include "ctrl.sv"
`include "Reg/regs_file.sv"
`include "pipeline/1_decode/id.sv"
`include "pipeline/1_decode/id_dispatch.sv"
`include "pipeline/2_dispatch/dispatch.sv"
`include "pipeline/3_execution/ex.sv"
`include "pipeline/3_execution/alu.sv"
`include "pipeline/4_mem/mem1.sv"
`include "pipeline/4_mem/mem2.sv"
`include "pipeline/5_wb/wb.sv"

module cpu_top 
    import core_types::*;
    import core_config::*;
    import csr_defines::*;
    import tlb_types::*;
(
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
    input  [127:0] rdata,
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
    output [127:0] wdata,
    output [ 15:0] wstrb,
    output        wlast,
    output        wvalid,
    input         wready,
    // write back
    input  [ 3:0] bid,
    input  [ 1:0] bresp,
    input         bvalid,
    output        bready,
    // debug info
    output logic [31:0] debug0_wb_pc,
    output logic [ 3:0] debug0_wb_rf_wen,
    output logic [ 4:0] debug0_wb_rf_wnum,
    output logic [31:0] debug0_wb_rf_wdata
    `ifdef CPU_2CMT
    ,
    output logic [31:0] debug1_wb_pc,
    output logic [ 3:0] debug1_wb_rf_wen,
    output logic [ 4:0] debug1_wb_rf_wnum,
    output logic [31:0] debug1_wb_rf_wdata
    `endif
);

    // Clock signal
    logic clk;
    assign clk = aclk;

    // Reset signal
    logic rst_n;
    logic rst;
    assign rst_n = aresetn;
    assign rst   = ~aresetn;

    // Pipeline control signal
    logic [6:0] pipeline_advance, pipeline_flush;
    logic [ISSUE_WIDTH-1:0] ex_advance_ready, mem1_advance_ready, mem2_advance_ready;

    // EX
    logic [ISSUE_WIDTH-1:0] ex_redirect;
    logic [ISSUE_WIDTH-1:0][$clog2(FRONTEND_FTQ_SIZE)-1:0] ex_redirect_ftq_id;
    logic [ISSUE_WIDTH-1:0][ADDR_WIDTH-1:0] ex_redirect_target;

    // ICache <-> AXI Controller
    logic icache_axi_rreq;
    logic axi_icache_rdy, axi_icache_rvalid;
    logic [127:0] axi_icache_data; // 128b
    logic [`RegBus] icache_axi_addr;

    // DCache <-> AXI Controller
    logic dcache_axi_rreq; // Read handshake
    logic axi_dcache_rd_rdy;
    logic axi_dcache_rvalid;
    logic dcache_axi_wreq; // Write handshake
    logic axi_dcache_wr_rdy;
    logic [`DataAddrBus] dcache_axi_raddr;
    logic [`DataAddrBus] dcache_axi_waddr;
    logic [`DataAddrBus] dcache_axi_addr;
    assign dcache_axi_addr = dcache_axi_rreq ? dcache_axi_raddr : dcache_axi_wreq ? dcache_axi_waddr : 0;
    logic [127:0] dcache_axi_data;
    logic [15:0] dcache_axi_wstrb; // Byte selection
    logic [127:0] axi_dcache_data; // AXI Read result
    logic [2:0] dcache_rd_type;
    logic [2:0] dcache_wr_type;

    logic [`RegBus] cache_mem_data;
    logic mem_data_ok,mem_addr_ok;

    // MEM1 <-> DCache
    mem_dcache_rreq_t mem_cache_signal[2];
    logic mem_cache_we,mem_cache_ce;
    logic [2:0] mem_cache_rd_type;
    logic [3:0] mem_cache_sel;
    logic [31:0] mem_cache_addr,mem_cache_data;
    logic [`RegBus] mem_cache_pc;
    logic [1:0] wb_dcache_flush; // flush dcache if excp
    logic [1:0][`RegBus] wb_dcache_flush_pc;
    logic [2:0]mem_cache_wr_type;
    logic dcache_ack, dcache_ready;
    
    assign mem_cache_ce = flush ? 0 : mem_cache_signal[0].ce | mem_cache_signal[1].ce;
    assign mem_cache_we = flush ? 0 : mem_cache_signal[0].we | mem_cache_signal[1].we;
    assign mem_cache_sel = flush ? 0 : mem_cache_signal[0].we ? mem_cache_signal[0].sel : mem_cache_signal[1].we ? mem_cache_signal[1].sel : 0;
    assign mem_cache_rd_type = flush ? 0 : mem_cache_signal[0].ce ? mem_cache_signal[0].rd_type : mem_cache_signal[1].ce ? mem_cache_signal[1].rd_type : 0;
    assign mem_cache_wr_type = flush ? 0 : mem_cache_signal[0].ce ? mem_cache_signal[0].wr_type : mem_cache_signal[1].ce ? mem_cache_signal[1].wr_type : 0;
    assign mem_cache_addr = flush ? 0 : mem_cache_signal[0].addr | mem_cache_signal[1].addr;
    assign mem_cache_data = flush ? 0 : mem_cache_signal[0].we ? mem_cache_signal[0].data : mem_cache_signal[1].we ? mem_cache_signal[1].data : 0;

    // Ctrl -> Regfile
    wb_reg_t [COMMIT_WIDTH-1:0] regfile_write;
    // Ctrl -> CSR
    csr_write_signal [COMMIT_WIDTH-1:0] csr_write;
    // Ctrl Backend redirect
    logic [ADDR_WIDTH-1:0] backend_redirect_pc;

    // Difftest related
    // Ctrl -> DifftestEvents
    diff_commit [COMMIT_WIDTH-1:0] difftest_commit_info;

    // TLB
    data_tlb_rreq_t [1:0] tlb_data_rreq;
    tlb_data_t tlb_data_result;
    tlb_write_in_struct tlb_write_signal_i;
    tlb_read_out_struct tlb_read_signal_o;

    // WB -> DCache
    logic [COMMIT_WIDTH-1:0] dcache_store_commit;

    logic [4:0] rand_index_diff;
    axi_master u_axi_master (
        .aclk   (aclk),
        .aresetn(aresetn),

        // <-> ICache
        .inst_cpu_addr_i(icache_axi_addr),
        .inst_cpu_data_o(axi_icache_data),
        .inst_id(4'b0000),  // Read Instruction only
        .icache_rd_type_i(3'b100), // Read 128b for 1 time
        .icache_rd_req_i(icache_axi_rreq),
        .icache_rd_rdy_o(axi_icache_rdy),
        .icache_ret_valid_o(axi_icache_rvalid),
        .icache_ret_last_o(), // Used in burst transfer, currently unused

        // <-> DCache
        .data_cpu_addr_i(dcache_axi_addr),
        .data_cpu_sel_i(dcache_axi_wstrb),
        .data_cpu_data_o(axi_dcache_data),
        .data_id(4'b0001),
        .dcache_rd_req_i(dcache_axi_rreq),
        .dcache_rd_type_i(dcache_rd_type), // For [31:0]
        .dcache_rd_rdy_o(axi_dcache_rd_rdy),
        .dcache_ret_valid_o(axi_dcache_rvalid),
        .dcache_ret_last_o(), // same as ICache
        .dcache_wr_req_i(dcache_axi_wreq),
        .dcache_wr_type_i(dcache_wr_type), 
        .dcache_wr_data(dcache_axi_data),
        .dcache_wr_rdy(axi_dcache_wr_rdy),
        .write_ok(), // Used in conherent instructions, unused for now


        // External AXI signals
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

   
    dummy_dcache u_dcache(
    	.clk       (clk       ),
        .rst       (rst       ),

        .valid     (mem_cache_ce),
        .op        (mem_cache_we),
        .pc        (mem_cache_pc),
        .uncache   (1'b0),
        .index     (mem_cache_addr[11:4]),
        .tag       (mem_cache_addr[31:12]),
        .offset    (mem_cache_addr[3:0]),
        .wstrb     (mem_cache_sel),
        .wdata     (mem_cache_data),
        .rd_type_i (mem_cache_rd_type),
        .wr_type_i (mem_cache_wr_type),
        .flush_pc(wb_dcache_flush[0] ? wb_dcache_flush_pc[0] : wb_dcache_flush[1] ? wb_dcache_flush_pc[1] :0),
        .store_commit_i(dcache_store_commit[0]),
        .flush_i    (wb_dcache_flush!=2'b0), // If excp occurs, flush DCache
        .cache_ready(dcache_ready),
        .cache_ack  (dcache_ack),
        .addr_ok   (mem_addr_ok),
        .data_ok   (mem_data_ok),
        .rdata     (cache_mem_data),

        // <-> AXI Controller
        .rd_req    (dcache_axi_rreq),
        .rd_type   (dcache_rd_type),
        .rd_addr   (dcache_axi_raddr),
        .rd_rdy    (axi_dcache_rd_rdy),
        .ret_valid (axi_dcache_rvalid),
        .ret_last  (),
        .ret_data  (axi_dcache_data),
        .wr_req    (dcache_axi_wreq),
        .wr_type   (dcache_wr_type),
        .wr_addr   (dcache_axi_waddr),
        .wr_wstrb  (dcache_axi_wstrb),
        .wr_data   (dcache_axi_data),
        .wr_rdy    (axi_dcache_wr_rdy)
    );

    // CSR signals
    logic has_int;
    logic excp_flush;
    logic ertn_flush;
    logic [31:0] csr_era_i;
    logic [8:0] csr_esubcode_i;
    logic [5:0] csr_ecode_i;
    logic va_error_i;
    logic [31:0] bad_va_i;
    logic tlbsrch_en;
    logic tlbsrch_found;
    logic [4:0] tlbsrch_index;
    logic excp_tlbrefill;
    logic excp_tlb;
    logic [18:0] excp_tlb_vppn;
    logic [18:0] csr_vppn_o;
    logic [`RegBus] csr_eentry;
    logic [31:0] csr_tlbrentry;
    logic [`RegBus] csr_era;
    logic LLbit_o;

    logic [9:0] csr_asid;
    logic csr_pg;
    logic csr_da;
    logic [31:0] csr_dmw0;
    logic [31:0] csr_dmw1;
    logic [1:0] csr_datf;
    logic [1:0] csr_datm;
    logic [1:0] csr_plv;
    

    // Frontend -> ICache
    logic [1:0] frontend_icache_rreq;
    logic [1:0] frontend_icache_rreq_uncached;
    logic [1:0][`InstAddrBus] frontend_icache_addr;

    // ICache -> Frontend
    logic [1:0]icache_frontend_rreq_ack;
    logic [1:0]icache_frontend_valid;
    logic [1:0][ICACHELINE_WIDTH-1:0] icache_frontend_data;

    // ICache <- TLB
    // Frontend <-> TLB
    inst_tlb_t frontend_tlb;
    tlb_inst_t tlb_inst;

    logic [`InstBus] excp_instr;
    logic [13:0] dispatch_csr_read_addr;
    logic [`RegBus] dispatch_csr_data;

    logic icacop_op_en[2];
    logic icacop_ack;
    logic [1:0] cacop_op_mode[2];

    icache u_icache(
        .clk          (clk          ),
        .rst          (rst          ),
       
        // Port A
        .rreq_1_i     (frontend_icache_rreq[0]),
        .rreq_1_uncached_i (frontend_icache_rreq_uncached[0]),
        .raddr_1_i    (frontend_icache_addr[0]),
        .rreq_1_ack_o (icache_frontend_rreq_ack[0]),
        .rvalid_1_o   (icache_frontend_valid[0]),
        .rdata_1_o    (icache_frontend_data[0]),
        // Port B
        .rreq_2_i     (frontend_icache_rreq[1]),
        .rreq_2_uncached_i (frontend_icache_rreq_uncached[1]),
        .raddr_2_i    (frontend_icache_addr[1]),
        .rreq_2_ack_o (icache_frontend_rreq_ack[1]),
        .rvalid_2_o   (icache_frontend_valid[1]),
        .rdata_2_o    (icache_frontend_data[1]),

        // <-> AXI Controller
        .axi_addr_o   (icache_axi_addr),
        .axi_rreq_o   (icache_axi_rreq),
        .axi_rdy_i    (axi_icache_rdy),
        .axi_rvalid_i (axi_icache_rvalid),
        .axi_rlast_i  (),
        .axi_data_i   (axi_icache_data),

        .invalid_i(),

        //-> CACOP
        .cacop_i(icacop_op_en[0]),
        .cacop_mode_i(cacop_op_mode[0]),
        .cacop_addr_i({tlb_data_result.tag,tlb_data_result.index,tlb_data_result.offset}),
        .cacop_ack_o(icacop_ack)
   );
    

    // Frontend <-> Instruction Buffer
    logic ib_frontend_stallreq;
    instr_info_t frontend_ib_instr_info[FETCH_WIDTH];
    logic [`RegBus] next_pc;

    // Frontend <-> Backend 
    logic backend_redirect;
    logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_redirect_ftq_id;
    logic [COMMIT_WIDTH-1:0] backend_commit_bitmask; // suggest whether last instr in basic block is committed
    logic [COMMIT_WIDTH-1:0][$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_commit_ftq_id;
    backend_commit_meta_t [COMMIT_WIDTH-1:0] backend_commit_meta;

    // All frontend structures
    frontend u_frontend (
        .clk(clk),
        .rst(rst),

        // <-> ICache
        .icache_read_req_o(frontend_icache_rreq), // -> ICache
        .icache_read_req_uncached_o(frontend_icache_rreq_uncached),
        .icache_read_addr_o(frontend_icache_addr), 
        .icache_rreq_ack_i(icache_frontend_rreq_ack),
        .icache_read_valid_i(icache_frontend_valid),  // <- ICache
        .icache_read_data_i(icache_frontend_data),  // <- ICache

        // <-> Backend
        .backend_next_pc_i   (next_pc),       // backend PC, <- pc_gen
        .backend_flush_i     (backend_redirect), // backend flush, usually come with next_pc
        .backend_flush_ftq_id_i(backend_redirect_ftq_id),
        .backend_commit_bitmask_i (backend_commit_bitmask),
        .backend_commit_ftq_id_i(backend_commit_ftq_id),
        .backend_commit_meta_i(),

        // <-> Instruction Buffer
        .instr_buffer_stallreq_i(ib_frontend_stallreq),   // instruction buffer is full
        .instr_buffer_o         (frontend_ib_instr_info),  // -> IB

        // <- CSR
        .csr_pg(csr_pg),
        .csr_da(csr_da),
        .csr_dmw0(csr_dmw0),
        .csr_dmw1(csr_dmw1),
        .csr_plv(csr_plv),
        .csr_datf(csr_datf),

        // <-> TLB
        .tlb_o(frontend_tlb),
        .tlb_i(tlb_inst)
    );

    instr_info_t ib_backend_instr_info[2];  // IB -> ID

    logic [DECODE_WIDTH-1:0] id_ib_accept;
    logic [DECODE_WIDTH-1:0] dispatch_id_accept;

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
        .backend_accept_i(id_ib_accept),  // FIXME: does not carefully designed
        .backend_flush_i(backend_redirect),  // Assure output is reset the next cycle
        .backend_instr_o(ib_backend_instr_info)  // -> ID
    );


    // ID <-> Regfile
    logic [1:0][1:0] dispatch_regfile_reg_read_valid;
    logic [1:0][1:0][`RegAddrBus] dispatch_regfile_reg_read_addr;
    logic [1:0][1:0][`RegBus] regfile_dispatch_reg_read_data;

    // ID -> ID_DISPATCH
    id_dispatch_struct [1:0] id_id_dispatch;

    // ID Stage
    generate
        for (genvar i = 0; i < 2; i++) begin : id
            id u_id (
                .instr_buffer_i(ib_backend_instr_info[i]),

                // -> Dispatch
                .dispatch_o(id_id_dispatch[i]),

                // <- CSR Registers
                .has_int        (has_int),
                .csr_plv        (csr_plv)
            );
        end
    endgenerate

    // ID_DISPATCH -> EXE
    id_dispatch_struct [1:0] id_dispatch_dispatch;

    // ID -- DISPATCH, Sequential
    id_dispatch u_id_dispatch (
        .clk       (clk),
        .rst       (rst),
        .stall     (~pipeline_advance[5]),
        .flush     (backend_redirect),
        .id_i      (id_id_dispatch),
        .id_dispatch_accept_o(id_ib_accept),
        // Dispatch
        .dispatch_issue_i(dispatch_id_accept),
        .dispatch_o(id_dispatch_dispatch)
    );

    // Dispatch -> EXE
    dispatch_ex_struct [1:0] dispatch_exe;

    // Data forwarding
    data_forward_t [ISSUE_WIDTH-1:0] ex_data_forward, mem1_data_forward, mem2_data_forward, wb_data_forward;

    // Dispatch Stage, Sequential logic
    dispatch u_dispatch (
        .clk (clk),
        .rst (rst),

        // <- ID
        .id_i(id_dispatch_dispatch),

        // <-> Ctrl
        .stall(~pipeline_advance[4]),
        .flush(backend_redirect),

        // Data forwarding    
        .ex_data_forward_i(ex_data_forward),
        .mem1_data_forward_i(mem1_data_forward),
        .mem2_data_forward_i(mem2_data_forward),
        .wb_data_forward_i(wb_data_forward),

        // <-> Regfile
        .regfile_reg_read_valid_o(dispatch_regfile_reg_read_valid),
        .regfile_reg_read_addr_o (dispatch_regfile_reg_read_addr),
        .regfile_reg_read_data_i (regfile_dispatch_reg_read_data),

        // <-> CSR
        .csr_read_addr(dispatch_csr_read_addr),
        .csr_data(dispatch_csr_data),

        // -> IB
        .ib_accept_o(dispatch_id_accept),

        // -> EXE
        .exe_o(dispatch_exe)
    );


    logic flush;

    //tlb
    logic data_addr_trans_en;

    logic idle_flush;
    logic icache_flush;
    logic [`InstAddrBus] idle_pc;

    logic disable_cache;
    logic [ISSUE_WIDTH-1:0][$clog2(FRONTEND_FTQ_SIZE)-1:0] wb_ctrl_ftq_id;
    logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] ctrl_frontend_ftq_id;

    // Redirect signal for frontend
    assign backend_redirect = ex_redirect[0] | pipeline_flush[6]; 

    assign backend_redirect_ftq_id = (pipeline_flush[6]) ? ctrl_frontend_ftq_id :
                                (ex_redirect[0]) ? ex_redirect_ftq_id[0] : 
                                (ex_redirect[1] ) ? ex_redirect_ftq_id[1] : 0;

    assign next_pc = pipeline_flush[6] ? backend_redirect_pc :
                     (ex_redirect[0]) ? ex_redirect_target[0] : 
                     (ex_redirect[1]) ? ex_redirect_target[1] : 0;


    ex_mem_struct ex_mem_signal[2];
    logic [1:0] tlb_stallreq;

    // EXE Stage
    logic [1:0] ex_stallreq;
    logic [63:0] csr_timer_64;
    logic [31:0] csr_tid;
    generate
        for (genvar i = 0; i < 2; i++) begin : ex
            ex u_ex (
                .clk  (clk),
                .rst(rst),

                // Pipeline control signals
                .flush(pipeline_flush[3]),
                .advance(pipeline_advance[3]),
                .advance_ready(ex_advance_ready[i]),

                // Previous stage
                .dispatch_i(dispatch_exe[i]),
                // Next stage
                .ex_o_buffer(ex_mem_signal[i]),

                // <-> CSR
                .timer_64(csr_timer_64),
                .tid(csr_tid),
                .csr_ex_signal(csr_mem_signal),

                // -> Ctrl, Redirect signals
                .ex_redirect_o(ex_redirect[i]),
                .ex_redirect_target_o(ex_redirect_target[i]),
                .ex_redirect_ftq_id_o(ex_redirect_ftq_id[i]),

                // -> Dispatch, data forward
                .data_forward_o(ex_data_forward[i]),

                // -> TLB
                .tlb_rreq_o(tlb_data_rreq[i]),

                // <-> Cache, CACOP
                .icacop_op_en(icacop_op_en[i]),
                .icacop_op_ack_i(icacop_ack),
                .dcacop_op_en(dcacop_op_en),
                .cacop_op_mode(cacop_op_mode[i])
            );
        end
    endgenerate


    mem1_mem2_struct mem1_mem2_signal[2];
    mem2_wb_struct mem2_wb_signal[2];

    logic mem_wb_LLbit_we[2];
    logic mem_wb_LLbit_value[2];
    tlb_inv_t tlb_inv_signal_i;

    csr_to_mem_struct csr_mem_signal;
    tlb_to_mem_struct tlb_mem_signal;
    assign tlb_mem_signal = {tlb_data_result.tag,tlb_data_result.found,tlb_data_result.tlb_index,tlb_data_result.tlb_v,
                            tlb_data_result.tlb_d,tlb_data_result.tlb_mat,tlb_data_result.tlb_plv};

    assign csr_mem_signal = {csr_pg,csr_da,csr_dmw0,csr_dmw1,csr_plv,csr_datm};
   
    logic [1:0] data_fetch, mem_tlbsrch;


    logic [1:0] mem1_stallreq;

    generate
        for (genvar i = 0; i < 2; i++) begin : mem1
            mem1 u_mem1 (
                .clk(clk),
                .rst(rst),

                // Pipeline control signals
                .flush(pipeline_flush[2]),
                .advance(pipeline_advance[2]),
                .advance_ready(mem1_advance_ready[i]),

                // Previous stage
                .ex_i(ex_mem_signal[i]),
                // Next stage
                .mem2_o_buffer(mem1_mem2_signal[i]),

                // <-> DCache
                .dcache_rreq_o(mem_cache_signal[i]),
                .dcache_ready_i(dcache_ready),
                .dcache_ack_i(dcache_ack),

                // <- TLB
                .tlb_result_i(tlb_data_result),

                // <- CSR
                .LLbit_i(LLbit_o),
                .csr_plv(csr_plv),

                // Data forward
                // -> Dispatch
                .data_forward_o(mem1_data_forward[i])

            );
        end
    endgenerate


    generate
        for(genvar i=0;i<2;i=i+1)begin : mem2
            mem2 u_mem2(
                .clk(clk),
                .rst(rst),

                // Pipeline control signals
                .flush(pipeline_flush[1]),
                .advance(pipeline_advance[1]),
                .advance_ready(mem2_advance_ready[i]),

                // Previous stage
                .mem1_i(mem1_mem2_signal[i]),
                // Next stage
                .mem2_o_buffer(mem2_wb_signal[i]),

                // -> Dispatch, data forward
                .data_forward_o(mem2_data_forward[i]),

                // <- DCache
                .data_ok(mem_data_ok),
                .cache_data_i(cache_mem_data)
            );
        end
    endgenerate

    wb_ctrl_struct [1:0] wb_ctrl_signal;
    logic [1:0] mem2_stallreq;

    generate
        for (genvar i = 0; i < 2; i++) begin : wb
            wb u_wb (
                .clk  (clk),
                .rst  (rst),

                // Pipeline control signals
                .flush(pipeline_flush[0]),
                .advance(pipeline_advance[0]),

                .mem_i(mem2_wb_signal[i]),

                // -> DCache
                .dcache_flush_o(wb_dcache_flush[i]),
                .dcache_store_commit_o(dcache_store_commit[i]),

                // -> Dispatch
                .data_forward_o(wb_data_forward[i]),

                //to ctrl
                .wb_ctrl_signal(wb_ctrl_signal[i])
            );
        end
    endgenerate


    regs_file #(
        .READ_PORTS(4)  // 2 for each ID, 2 ID in total, TODO: remove magic number
    ) u_regfile (
        .clk(clk),

        // Write signals
        .we_i({regfile_write[1].we, regfile_write[0].we}),
        .waddr_i({regfile_write[1].waddr, regfile_write[0].waddr}),
        .wdata_i({regfile_write[1].wdata, regfile_write[0].wdata}),

        // Read signals
        // Registers are read in dispatch stage
        .read_valid_i(dispatch_regfile_reg_read_valid),
        .read_addr_i (dispatch_regfile_reg_read_addr),
        .read_data_o (regfile_dispatch_reg_read_data)
    );




    logic tlbrd_en;

    wb_llbit_t llbit_i;
    logic inv_stallreq;


    ctrl u_ctrl(
        .clk(clk),
        .rst(rst),

        // -> Frontend
        .backend_commit_block_o(backend_commit_bitmask),
        .backend_flush_ftq_id_o(ctrl_frontend_ftq_id),

        // <- WB
        .wb_i(wb_ctrl_signal),

        // Pipeline control signal
        .ex_redirect_i(ex_redirect),
        .ex_advance_ready_i(ex_advance_ready),
        .mem1_advance_ready_i(mem1_advance_ready), 
        .mem2_advance_ready_i(mem2_advance_ready),
        .flush_o(pipeline_flush), 
        .advance_o(pipeline_advance),
        .backend_redirect_pc_o(backend_redirect_pc),

        // <- CSR
        .csr_eentry_i(csr_eentry),
        .csr_tlbrentry_i(csr_tlbrentry),
        .csr_era_i(csr_era),

        // -> CSR
        .csr_excp(excp_flush),
        .csr_ertn(ertn_flush),
        .csr_era(csr_era_i),
        .csr_esubcode(csr_esubcode_i),
        .csr_ecode(csr_ecode_i),
        .va_error(va_error_i),
        .bad_va(bad_va_i),
        .excp_tlbrefill(excp_tlbrefill),
        .excp_tlb(excp_tlb),
        .excp_tlb_vppn(excp_tlb_vppn),
        .tlbsrch_found(tlbsrch_found),
        .tlbsrch_index(tlbsrch_index),
        .tlbrd_en(tlbrd_en),
        .llbit_signal(),

        .inv_o(tlb_inv_signal_i),
        .inv_stallreq(inv_stallreq),

        .tlbwr_en(tlb_write_signal_i.tlbwr_en),
        .tlbsrch_en(tlbsrch_en),
        .tlbfill_en(tlb_write_signal_i.tlbfill_en),

        // <- TLB
        .tlbsrch_result_i(tlb_mem_signal),

        .regfile_o(regfile_write),
        .csr_write_o(csr_write),

        // -> Difftest
        .excp_instr(excp_instr),
        .difftest_commit_o(difftest_commit_info)
    );
    
    

    cs_reg u_cs_reg (
        .clk(clk),
        .rst(rst),
        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush),
        .interrupt_i({1'b0,intrpt}),
        .ecode_i(csr_ecode_i),
        .write_signal_1(csr_write[0]),
        .write_signal_2(csr_write[1]),
        .raddr(dispatch_csr_read_addr),
        .rdata(dispatch_csr_data),
        .llbit_i(llbit_i.value),
        .llbit_set_i(llbit_i.we),
        .llbit_o(LLbit_o),
        .vppn_o(csr_vppn_o),
        .era_i(csr_era_i),
        .timer_64_o(csr_timer_64),
        .tid_o(csr_tid),
        .plv_o(csr_plv),
        .esubcode_i(csr_esubcode_i),
        .va_error_i(va_error_i),
        .bad_va_i(bad_va_i),
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
        .rand_index(tlb_write_signal_i.rand_index),
        .tlbehi_out(tlb_write_signal_i.tlbehi),
        .tlbelo0_out(tlb_write_signal_i.tlbelo0),
        .tlbelo1_out(tlb_write_signal_i.tlbelo1),
        .tlbidx_out(tlb_write_signal_i.tlbidx),
        .pg_out(csr_pg),
        .da_out(csr_da),
        .dmw0_out(csr_dmw0),
        .dmw1_out(csr_dmw1),
        .datf_out(csr_datf),
        .datm_out(csr_datm),
        .ecode_out(tlb_write_signal_i.ecode),
        .tlbrd_en(tlbrd_en),
        .tlbehi_in(tlb_read_signal_o.tlbehi),
        .tlbelo0_in(tlb_read_signal_o.tlbelo0),
        .tlbelo1_in(tlb_read_signal_o.tlbelo1),
        .tlbidx_in(tlb_read_signal_o.tlbidx),
        .asid_in(tlb_read_signal_o.asid)
    );

    tlb u_tlb (
        .clk               (clk),
        .asid              (csr_asid),
        //trans mode 
        .data_addr_trans_en(data_addr_trans_en),
        //inst addr trans
        .inst_i(frontend_tlb),
        .inst_o(tlb_inst),
        //data addr trans 
        .data_i(tlb_data_rreq[0]), // Memory access is single issued
        .data_o(tlb_data_result),
        //tlbwr tlbfill tlb write 
        .write_signal_i(tlb_write_signal_i),
        //tlbp tlb read
        .read_signal_o(tlb_read_signal_o),
        //invtlb 
        .inv_signal_i(tlb_inv_signal_i),
        //from csr
        .csr_dmw0(csr_dmw0),
        .csr_dmw1(csr_dmw1),
        .csr_da(csr_da),
        .csr_pg(csr_pg),

        .rand_index_diff(rand_index_diff)
    );

    // Difftest Delay signals
    diff_commit [COMMIT_WIDTH-1:0] difftest_commit_info_delay1;
    logic csr_rstat_commit[2];
    logic [`RegBus] csr_data_commit[2];

    always_ff @( posedge clk ) begin 
        difftest_commit_info_delay1 <= difftest_commit_info;
        csr_rstat_commit[0] <= csr_write[0].we && (csr_write[0].addr == 14'h5) | difftest_commit_info[0].csr_rstat;
        csr_data_commit[0] <= difftest_commit_info[0].csr_rstat ? u_cs_reg.csr_estat : csr_write[0].data;
    end

    always_ff @(posedge clk) begin
        debug0_wb_pc <= difftest_commit_info[0].pc; 
        debug0_wb_rf_wen <= {3'b0,regfile_write[0].we};
        debug0_wb_rf_wdata <= regfile_write[0].wdata;
        debug0_wb_rf_wnum <= regfile_write[0].waddr;
        `ifdef CPU_2CMT
        debug1_wb_pc <= difftest_commit_info[1].pc; 
        debug1_wb_rf_wen <= {3'b0,regfile_write[1].we};
        debug1_wb_rf_wdata <= regfile_write[1].wdata;
        debug1_wb_rf_wnum <= regfile_write[1].waddr;
        `endif
    end
`ifdef SIMULATION
    logic excp_flush_commit;
    logic ertn_flush_commit;
    logic [`RegBus] excp_pc_commit;
    logic [5:0] csr_ecode_commit;
    logic [`InstBus] excp_instr_commit;
    logic tlbfill_en_commit;
    logic [4:0] rand_index_commit;

    always_ff @( posedge clk ) begin 
        excp_flush_commit <= excp_flush;
        ertn_flush_commit <= ertn_flush;
        excp_pc_commit <= csr_era_i;
        csr_ecode_commit <= csr_ecode_i;
        excp_instr_commit <= excp_instr;
        tlbfill_en_commit <= tlb_write_signal_i.tlbfill_en;
        rand_index_commit <= rand_index_diff;
    end
`endif 
    // difftest dpi-c
`ifdef SIMU  // SIMU is defined in chiplab run_func/makefile
    DifftestInstrCommit difftest_instr_commit_0 (  
        .clock         (aclk),
        .coreid        (0),                             // only one core, so always 0
        .index         (0),                             // commit channel index
        .valid         (difftest_commit_info_delay1[0].valid),  // 1 means valid
        .pc            (difftest_commit_info_delay1[0].pc),
        .instr         (difftest_commit_info_delay1[0].instr),
        .skip          (0),                             // not implemented in CHIPLAB, keep 0 
        .is_TLBFILL    (tlbfill_en_commit),
        .TLBFILL_index (rand_index_commit),
        .is_CNTinst    (difftest_commit_info_delay1[0].is_CNTinst),
        .timer_64_value(difftest_commit_info_delay1[0].timer_64),
        .wen           (debug0_wb_rf_wen),
        .wdest         ({3'b0, debug0_wb_rf_wnum}),
        .wdata         (debug0_wb_rf_wdata),
        .csr_rstat     (csr_rstat_commit[0]),
        .csr_data      (csr_data_commit[0])
    );
    DifftestInstrCommit difftest_instr_commit_1 (  
        .clock         (aclk),
        .coreid        (0),                             // only one core, so always 0
        .index         (1),                             // commit channel index
        .skip          (0),                             
        .valid         (difftest_commit_info_delay1[1].valid),  // 1 means valid
        .pc            (difftest_commit_info_delay1[1].pc),
        .instr         (difftest_commit_info_delay1[1].instr),
        .is_TLBFILL    (tlbfill_en_commit),
        .TLBFILL_index (rand_index_commit),
        .is_CNTinst    (difftest_commit_info_delay1[1].is_CNTinst),
        .timer_64_value(difftest_commit_info_delay1[1].timer_64),
        .wen           (debug1_wb_rf_wen),
        .wdest         ({3'b0, debug1_wb_rf_wnum}),
        .wdata         (debug1_wb_rf_wdata),
        .csr_rstat     (csr_rstat_commit[1]),
        .csr_data      (csr_data_commit[1])
    );

    DifftestStoreEvent difftest_store_event(
        .clock              (aclk),
        .coreid             (0),
        .index              (0),
        .valid              (difftest_commit_info_delay1[0].inst_st_en | difftest_commit_info_delay1[1].inst_st_en),
        .storePAddr         (difftest_commit_info_delay1[0].st_paddr | difftest_commit_info_delay1[1].st_paddr),
        .storeVAddr         (difftest_commit_info_delay1[0].st_vaddr |difftest_commit_info_delay1[1].st_vaddr),
        .storeData          (difftest_commit_info_delay1[0].st_data | difftest_commit_info_delay1[1].st_data)
    );

    DifftestLoadEvent difftest_load_event(
        .clock              (aclk),
        .coreid             (0),
        .index              (0),
        .valid              (difftest_commit_info_delay1[0].inst_ld_en | difftest_commit_info_delay1[1].inst_ld_en),
        .paddr              (difftest_commit_info_delay1[0].ld_paddr | difftest_commit_info_delay1[1].ld_paddr),
        .vaddr              (difftest_commit_info_delay1[0].ld_vaddr | difftest_commit_info_delay1[1].ld_vaddr)
    );

    DifftestTrapEvent difftest_trap_event(
        .clock              (aclk),
        .coreid             (0),
        .valid              (),
        .code               (),
        .pc                 (),
        .cycleCnt           (),
        .instrCnt           ()
    );

    DifftestExcpEvent difftest_excp_event(
       .clock              (aclk),
       .coreid             (0),
       .excp_valid         (excp_flush_commit),
       .eret               (ertn_flush_commit),
       .intrNo             (u_cs_reg.csr_estat[12:2]),
       .cause              (csr_ecode_commit),
       .exceptionPC        (excp_pc_commit),
       .exceptionInst      (excp_instr_commit)
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

        // According to example core
        .llbctl   ({u_cs_reg.csr_llbctl[31:1], u_cs_reg.llbit}),

        .dmw0     (u_cs_reg.csr_dmw0),
        .dmw1     (u_cs_reg.csr_dmw1)
    );

    // Assume regfile instance name is u_regfile
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

`ifdef DEBUG
// FPGA Debug core
ila_1 ila_cpu_top (
	.clk(clk), // input wire clk


	.probe0(u_axi_master.inst_r_state), // input wire [3:0]  probe0  
	.probe1(u_axi_master.data_r_state), // input wire [3:0]  probe1 
	.probe2(u_axi_master.w_state), // input wire [3:0]  probe2 
	.probe3({21'b0,u_icache.hit,u_icache.miss_1, u_icache.miss_2,u_icache.cacop_i,u_axi_master.dcache_rd_type_i,u_axi_master.s_arsize}), // input wire [31:0]  probe3 
	.probe4(u_axi_master.icache_rd_req_i), // input wire [0:0]  probe4 
	.probe5(u_axi_master.icache_ret_valid_o), // input wire [0:0]  probe5 
	.probe6(u_icache.state), // input wire [31:0]  probe6 
	.probe7(u_tlb.data_i.fetch), // input wire [0:0]  probe7 
	.probe8(u_tlb.we), // input wire [0:0]  probe8 
	.probe9(u_tlb.data_i.vaddr), // input wire [31:0]  probe9 
	.probe10({u_tlb.data_o.tag,u_tlb.data_o.index,u_tlb.data_o.offset}), // input wire [31:0]  probe10 
	.probe11(u_tlb.data_addr_trans_en), // input wire [0:0]  probe11 
	.probe12(next_pc), // input wire [31:0]  probe12 
	.probe13(u_frontend.u_ifu.p1_pc), // input wire [31:0]  probe13 
	.probe14(u_axi_master.s_awaddr), // input wire [31:0]  probe14 
	.probe15(u_axi_master.s_araddr), // input wire [31:0]  probe15 
	.probe16(u_axi_master.s_awready), // input wire [0:0]  probe16 
	.probe17(u_axi_master.s_awvalid), // input wire [0:0]  probe17 
	.probe18(u_axi_master.s_wready), // input wire [0:0]  probe18 
	.probe19(u_axi_master.s_wvalid) // input wire [0:0]  probe19
);
`endif

endmodule
