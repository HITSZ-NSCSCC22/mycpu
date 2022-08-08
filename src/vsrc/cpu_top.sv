`include "defines.sv"
`include "core_types.sv"
`include "core_config.sv"
`include "csr_defines.sv"
`include "frontend/frontend_defines.sv"
`include "axi/axi_interface.sv"
`include "axi/axi_3x1_crossbar.v"
`include "cs_reg.sv"
`include "tlb.sv"
`include "tlb_entry.sv"
`include "frontend/frontend.sv"
`include "instr_buffer.sv"
`include "icache.sv"
`include "Cache/dcache.sv"
`include "ctrl.sv"
`include "Reg/regs_file.sv"
`include "pipeline/1_decode/id.sv"
`include "pipeline/1_decode/id_dispatch.sv"
`include "pipeline/2_dispatch/dispatch.sv"
`include "pipeline/3_execution/ex.sv"
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
    output       [                   3:0] arid,
    output       [                  31:0] araddr,
    output       [                   7:0] arlen,
    output       [                   2:0] arsize,
    output       [                   1:0] arburst,
    output       [                   1:0] arlock,
    output       [                   3:0] arcache,
    output       [                   2:0] arprot,
    output                                arvalid,
    input                                 arready,
    // read back
    input        [                   3:0] rid,
    input        [    AXI_DATA_WIDTH-1:0] rdata,
    input        [                   1:0] rresp,
    input                                 rlast,
    input                                 rvalid,
    output                                rready,
    // write request
    output       [                   3:0] awid,
    output       [                  31:0] awaddr,
    output       [                   7:0] awlen,
    output       [                   2:0] awsize,
    output       [                   1:0] awburst,
    output       [                   1:0] awlock,
    output       [                   3:0] awcache,
    output       [                   2:0] awprot,
    output                                awvalid,
    input                                 awready,
    // write data
    output reg   [                   3:0] wid,
    output       [    AXI_DATA_WIDTH-1:0] wdata,
    output       [(AXI_DATA_WIDTH/8)-1:0] wstrb,
    output                                wlast,
    output                                wvalid,
    input                                 wready,
    // write back
    input        [                   3:0] bid,
    input        [                   1:0] bresp,
    input                                 bvalid,
    output                                bready,
    // debug info
    output logic [                  31:0] debug0_wb_pc,
    output logic [                   3:0] debug0_wb_rf_wen,
    output logic [                   4:0] debug0_wb_rf_wnum,
    output logic [                  31:0] debug0_wb_rf_wdata,
`ifdef CPU_2CMT
    output logic [                  31:0] debug1_wb_pc,
    output logic [                   3:0] debug1_wb_rf_wen,
    output logic [                   4:0] debug1_wb_rf_wnum,
    output logic [                  31:0] debug1_wb_rf_wdata
`endif
);

    // Clock signal
    logic clk;
    assign clk = aclk;

    // Reset signal
    logic rst_n;
    logic rst;
    logic l2_cache_initialing;
    assign rst_n = ~rst;
    assign rst   = ~aresetn | l2_cache_initialing;

    // Pipeline control signal
    logic [6:0] pipeline_advance, pipeline_flush, pipeline_clear;
    logic [ISSUE_WIDTH-1:0] ex_advance_ready, mem1_advance_ready, mem2_advance_ready;

    // Frontend <-> ICache
    logic [1:0] frontend_icache_rreq;
    logic [1:0] frontend_icache_rreq_uncached;
    logic [1:0][`InstAddrBus] frontend_icache_addr;
    logic [1:0] icache_frontend_rreq_ack;
    logic [1:0] icache_frontend_valid;
    logic [1:0][ICACHELINE_WIDTH-1:0] icache_frontend_data;

    // ICache <- TLB
    // Frontend <-> TLB
    inst_tlb_t frontend_tlb;
    tlb_inst_t tlb_inst;

    // Frontend <-> Instruction Buffer
    logic ib_frontend_stallreq;
    instr_info_t frontend_ib_instr_info[FETCH_WIDTH];
    logic [`RegBus] next_pc;

    // Frontend <-> Backend 
    logic backend_redirect;
    logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_redirect_ftq_id;
    logic [COMMIT_WIDTH-1:0] backend_commit_bitmask; // suggest whether last instr in basic block is committed, including exception
    logic [COMMIT_WIDTH-1:0] backend_commit_block_bitmask;
    // Currently one branch instruction per cycle is supported
    logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] backend_commit_ftq_id;
    backend_commit_meta_t backend_commit_meta;


    logic [`InstBus] excp_instr;
    logic [1:0][13:0] dispatch_csr_read_addr;
    logic [1:0][`RegBus] dispatch_csr_data;

    logic icacop_op_en[2], dcacop_op_en[2], control_dcache_cacop;
    logic icacop_ack, dcacop_ack;
    logic [1:0] icacop_op_mode[2], dcacop_op_mode[2], control_dcache_cacop_mode;
    logic [`RegBus] control_dcache_cacop_addr;
    logic has_int;

    // EX
    logic [ISSUE_WIDTH-1:0] ex_redirect;
    logic [ISSUE_WIDTH-1:0][$clog2(FRONTEND_FTQ_SIZE)-1:0] ex_redirect_ftq_id;
    logic [ISSUE_WIDTH-1:0][ADDR_WIDTH-1:0] ex_redirect_target;
    logic [ISSUE_WIDTH-1:0] ex_is_branch;
    logic [ISSUE_WIDTH-1:0] ex_jump_target_mispredict;
    logic [ISSUE_WIDTH-1:0][ADDR_WIDTH-1:0] ex_jump_target_addr;
    logic [ISSUE_WIDTH-1:0][ADDR_WIDTH-1:0] ex_fall_through_addr;
    logic [ISSUE_WIDTH-1:0][$clog2(FRONTEND_FTQ_SIZE)-1:0] ex_ftq_query_addr;
    logic [ISSUE_WIDTH-1:0][ADDR_WIDTH-1:0] ex_ftq_query_pc;


    // AXI
    axi_interface icache_axi (), dcache_axi (), uncache_axi ();

    // ICache <-> AXI Controller
    logic icache_axi_rreq;
    logic axi_icache_rdy, axi_icache_rvalid;
    logic axi_icache_rlast;
    logic [31:0] axi_icache_data;  // 32b
    logic [`RegBus] icache_axi_addr;

    // DCache <-> AXI Controller
    logic dcache_axi_rreq;  // Read handshake
    logic axi_dcache_rd_rdy;
    logic axi_dcache_rvalid;
    logic axi_dcache_rlast;
    logic dcache_axi_wreq;  // Write handshake
    logic axi_dcache_wr_rdy;
    logic axi_dcache_wr_done;
    logic [`DataAddrBus] dcache_axi_raddr;
    logic [`DataAddrBus] dcache_axi_waddr;
    logic [`DataAddrBus] dcache_axi_addr;
    assign dcache_axi_addr = dcache_axi_rreq ? dcache_axi_raddr : dcache_axi_wreq ? dcache_axi_waddr : 0;
    logic [127:0] dcache_axi_data;
    logic [3:0] dcache_axi_wstrb;  // Byte selection
    logic [31:0] axi_dcache_data;  // AXI Read result
    logic [2:0] dcache_rd_type;
    logic [2:0] dcache_wr_type;

    logic [`RegBus] cache_mem_data;
    logic mem_data_ok, mem_addr_ok;

    // MEM1 <-> DCache
    mem_dcache_rreq_t mem_cache_signal[2];
    logic mem_cache_we, mem_cache_ce;
    logic [2:0] mem_cache_req_type;
    logic [3:0] mem_cache_sel;
    logic [2:0] mem_uncache_en;
    logic [31:0] mem_cache_addr, mem_cache_data;
    logic [`RegBus] mem_cache_pc;
    logic [1:0] wb_dcache_flush;  // flush dcache if excp
    logic [1:0][`RegBus] wb_dcache_flush_pc;
    logic dcache_ack, dcache_ready;
    logic [1:0] mem_valid;

    assign mem_cache_ce = mem_cache_signal[0].ce | mem_cache_signal[1].ce;
    assign mem_cache_we = mem_cache_signal[0].we | mem_cache_signal[1].we;
    assign mem_cache_sel =  mem_cache_signal[0].we ? mem_cache_signal[0].sel : mem_cache_signal[1].we ? mem_cache_signal[1].sel : 0;
    assign mem_cache_req_type = mem_cache_signal[0].ce ? mem_cache_signal[0].req_type : mem_cache_signal[1].ce ? mem_cache_signal[1].req_type : 0;
    assign mem_cache_addr = mem_cache_signal[0].addr | mem_cache_signal[1].addr;
    assign mem_cache_data =  mem_cache_signal[0].we ? mem_cache_signal[0].data : mem_cache_signal[1].we ? mem_cache_signal[1].data : 0;

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

    csr_to_mem_struct csr_mem_signal;
    tlb_to_mem_struct tlb_mem_signal;

    // CSR signals
    logic excp_flush;
    logic ertn_flush;
    logic [63:0] csr_timer_64;
    logic [31:0] csr_tid;
    logic [31:0] csr_era_i;
    logic [8:0] csr_esubcode_i;
    logic [5:0] csr_ecode_i;
    logic va_error_i;
    logic [31:0] bad_va_i;
    logic tlbsrch_en;
    logic tlbsrch_found;
    logic [$clog2(TLB_NUM)-1:0] tlbsrch_index;
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

    logic [$clog2(TLB_NUM)-1:0] rand_index_diff;

    logic control_dcache_valid, control_dcache_ready;
    logic [`RegBus] control_dcache_addr, control_dcache_wdata, control_dcache_rdata;
    logic [3:0] control_dcache_wstrb;

    // PMU
    pmu_input_t pmu_data;
    assign pmu_data.ib_full = ib_frontend_stallreq;
    assign pmu_data.ib_empty = u_instr_buffer.write_ptr == u_instr_buffer.read_ptr;
    assign pmu_data.bpu_branch_instr = backend_commit_meta.is_branch;
    assign pmu_data.bpu_valid = ex[0].u_ex.special_info.predict_valid & ex[0].u_ex.advance;
    assign pmu_data.bpu_miss = ex_redirect[0];
    assign pmu_data.bpu_conditional_branch = (backend_commit_meta.branch_type == BRANCH_TYPE_COND) & backend_commit_meta.is_branch;
    assign pmu_data.bpu_conditional_miss = (backend_commit_meta.branch_type == BRANCH_TYPE_COND) & (backend_commit_meta.is_taken ^ backend_commit_meta.predicted_taken) & backend_commit_meta.is_branch;
    assign pmu_data.bpu_ftb_dirty = ex_jump_target_mispredict[0];
    assign pmu_data.dcache_req = u_dcache.state == u_dcache.IDLE & mem_cache_ce;
    assign pmu_data.dcache_miss = u_dcache.state == u_dcache.IDLE & u_dcache.next_state == u_dcache.READ_REQ| u_dcache.next_state == u_dcache.WRITE_REQ;
    assign pmu_data.icache_req = (u_icache.rreq_1_i | u_icache.rreq_2_i) & u_icache.state == u_icache.IDLE;
    assign pmu_data.icache_miss = u_icache.miss_1_pulse | u_icache.miss_2_pulse;

    dcache u_dcache (
        .clk(clk),
        .rst(rst),
        .mem_valid(mem_valid[0]),

        .valid   (mem_cache_ce),
        .vaddr   (mem_cache_addr),
        .req_type(mem_cache_req_type),
        .wstrb   (mem_cache_sel),
        .wdata   (mem_cache_data),

        .uncache_en(mem_uncache_en[0]),
        .paddr({tlb_data_result.tag, tlb_data_result.index, tlb_data_result.offset}),

        .cacop_i     (dcacop_op_en[0]),
        .cacop_mode_i(dcacop_op_mode[0]),

        .cpu_flush(wb_dcache_flush[0]),

        .dcache_ready(dcache_ready),
        .data_ok(mem_data_ok),
        .rdata(cache_mem_data),

        .m_axi(dcache_axi)
    );

    icache u_icache (
        .clk(clk),
        .rst(rst),

        // Port A
        .rreq_1_i         (frontend_icache_rreq[0]),
        .rreq_1_uncached_i(frontend_icache_rreq_uncached[0]),
        // .rreq_1_uncached_i(0),
        .raddr_1_i        (frontend_icache_addr[0]),
        .rreq_1_ack_o     (icache_frontend_rreq_ack[0]),
        .rvalid_1_o       (icache_frontend_valid[0]),
        .rdata_1_o        (icache_frontend_data[0]),
        // Port B
        .rreq_2_i         (frontend_icache_rreq[1]),
        .rreq_2_uncached_i(frontend_icache_rreq_uncached[1]),
        // .rreq_2_uncached_i(0),
        .raddr_2_i        (frontend_icache_addr[1]),
        .rreq_2_ack_o     (icache_frontend_rreq_ack[1]),
        .rvalid_2_o       (icache_frontend_valid[1]),
        .rdata_2_o        (icache_frontend_data[1]),

        // <-> AXI Controller
        .m_axi(icache_axi),

        .invalid_i(),

        //-> CACOP
        .cacop_i(icacop_op_en[0]),
        .cacop_mode_i(icacop_op_mode[0]),
        .cacop_addr_i({tlb_data_result.tag, tlb_data_result.index, tlb_data_result.offset}),
        .cacop_ack_o(icacop_ack)
    );

    always_ff @(posedge clk) begin
        if (awvalid) wid <= awid;
    end
`ifdef L2_CACHE
    system_cache_0 l2_cache (
        .ACLK          (aclk),                 // input wire ACLK
        .ARESETN       (aresetn),              // input wire ARESETN
        .Initializing  (l2_cache_initialing),  // output wire Initializing
        .S0_AXI_AWID   (icache_axi.awid),      // input wire [0 : 0] S0_AXI_AWID
        .S0_AXI_AWADDR (icache_axi.awaddr),    // input wire [31 : 0] S0_AXI_AWADDR
        .S0_AXI_AWLEN  (icache_axi.awlen),     // input wire [7 : 0] S0_AXI_AWLEN
        .S0_AXI_AWSIZE (icache_axi.awsize),    // input wire [2 : 0] S0_AXI_AWSIZE
        .S0_AXI_AWBURST(icache_axi.awburst),   // input wire [1 : 0] S0_AXI_AWBURST
        .S0_AXI_AWLOCK (1'b0),                 // input wire S0_AXI_AWLOCK
        .S0_AXI_AWCACHE(icache_axi.awcache),   // input wire [3 : 0] S0_AXI_AWCACHE
        .S0_AXI_AWPROT (3'b0),                 // input wire [2 : 0] S0_AXI_AWPROT
        .S0_AXI_AWQOS  (4'b0),                 // input wire [3 : 0] S0_AXI_AWQOS
        .S0_AXI_AWVALID(icache_axi.awvalid),   // input wire S0_AXI_AWVALID
        .S0_AXI_AWREADY(icache_axi.awready),   // output wire S0_AXI_AWREADY
        .S0_AXI_AWUSER (1'b0),                 // input wire [0 : 0] S0_AXI_AWUSER
        .S0_AXI_WDATA  (icache_axi.wdata),     // input wire [127 : 0] S0_AXI_WDATA
        .S0_AXI_WSTRB  (icache_axi.wstrb),     // input wire [15 : 0] S0_AXI_WSTRB
        .S0_AXI_WLAST  (icache_axi.wlast),     // input wire S0_AXI_WLAST
        .S0_AXI_WVALID (icache_axi.wvalid),    // input wire S0_AXI_WVALID
        .S0_AXI_WREADY (icache_axi.wready),    // output wire S0_AXI_WREADY
        .S0_AXI_BRESP  (icache_axi.bresp),     // output wire [1 : 0] S0_AXI_BRESP
        .S0_AXI_BID    (icache_axi.bid),       // output wire [0 : 0] S0_AXI_BID
        .S0_AXI_BVALID (icache_axi.bvalid),    // output wire S0_AXI_BVALID
        .S0_AXI_BREADY (icache_axi.bready),    // input wire S0_AXI_BREADY
        .S0_AXI_ARID   (icache_axi.arid),      // input wire [0 : 0] S0_AXI_ARID
        .S0_AXI_ARADDR (icache_axi.araddr),    // input wire [31 : 0] S0_AXI_ARADDR
        .S0_AXI_ARLEN  (icache_axi.arlen),     // input wire [7 : 0] S0_AXI_ARLEN
        .S0_AXI_ARSIZE (icache_axi.arsize),    // input wire [2 : 0] S0_AXI_ARSIZE
        .S0_AXI_ARBURST(icache_axi.arburst),   // input wire [1 : 0] S0_AXI_ARBURST
        .S0_AXI_ARLOCK (1'b0),                 // input wire S0_AXI_ARLOCK
        .S0_AXI_ARCACHE(icache_axi.arcache),   // input wire [3 : 0] S0_AXI_ARCACHE
        .S0_AXI_ARPROT (3'b0),                 // input wire [2 : 0] S0_AXI_ARPROT
        .S0_AXI_ARQOS  (4'b0),                 // input wire [3 : 0] S0_AXI_ARQOS
        .S0_AXI_ARVALID(icache_axi.arvalid),   // input wire S0_AXI_ARVALID
        .S0_AXI_ARREADY(icache_axi.arready),   // output wire S0_AXI_ARREADY
        .S0_AXI_ARUSER (1'b0),                 // input wire [0 : 0] S0_AXI_ARUSER
        .S0_AXI_RID    (icache_axi.rid),       // output wire [0 : 0] S0_AXI_RID
        .S0_AXI_RDATA  (icache_axi.rdata),     // output wire [127 : 0] S0_AXI_RDATA
        .S0_AXI_RRESP  (icache_axi.rresp),     // output wire [1 : 0] S0_AXI_RRESP
        .S0_AXI_RLAST  (icache_axi.rlast),     // output wire S0_AXI_RLAST
        .S0_AXI_RVALID (icache_axi.rvalid),    // output wire S0_AXI_RVALID
        .S0_AXI_RREADY (icache_axi.rready),    // input wire S0_AXI_RREADY
        .S1_AXI_AWID   (dcache_axi.awid),      // input wire [0 : 0] S1_AXI_AWID
        .S1_AXI_AWADDR (dcache_axi.awaddr),    // input wire [31 : 0] S1_AXI_AWADDR
        .S1_AXI_AWLEN  (dcache_axi.awlen),     // input wire [7 : 0] S1_AXI_AWLEN
        .S1_AXI_AWSIZE (dcache_axi.awsize),    // input wire [2 : 0] S1_AXI_AWSIZE
        .S1_AXI_AWBURST(dcache_axi.awburst),   // input wire [1 : 0] S1_AXI_AWBURST
        .S1_AXI_AWLOCK (1'b0),                 // input wire S1_AXI_AWLOCK
        .S1_AXI_AWCACHE(dcache_axi.awcache),   // input wire [3 : 0] S1_AXI_AWCACHE
        .S1_AXI_AWPROT (3'b0),                 // input wire [2 : 0] S1_AXI_AWPROT
        .S1_AXI_AWQOS  (4'b0),                 // input wire [3 : 0] S1_AXI_AWQOS
        .S1_AXI_AWVALID(dcache_axi.awvalid),   // input wire S1_AXI_AWVALID
        .S1_AXI_AWREADY(dcache_axi.awready),   // output wire S1_AXI_AWREADY
        .S1_AXI_AWUSER (1'b0),                 // input wire [0 : 0] S1_AXI_AWUSER
        .S1_AXI_WDATA  (dcache_axi.wdata),     // input wire [127 : 0] S1_AXI_WDATA
        .S1_AXI_WSTRB  (dcache_axi.wstrb),     // input wire [15 : 0] S1_AXI_WSTRB
        .S1_AXI_WLAST  (dcache_axi.wlast),     // input wire S1_AXI_WLAST
        .S1_AXI_WVALID (dcache_axi.wvalid),    // input wire S1_AXI_WVALID
        .S1_AXI_WREADY (dcache_axi.wready),    // output wire S1_AXI_WREADY
        .S1_AXI_BRESP  (dcache_axi.bresp),     // output wire [1 : 0] S1_AXI_BRESP
        .S1_AXI_BID    (dcache_axi.bid),       // output wire [0 : 0] S1_AXI_BID
        .S1_AXI_BVALID (dcache_axi.bvalid),    // output wire S1_AXI_BVALID
        .S1_AXI_BREADY (dcache_axi.bready),    // input wire S1_AXI_BREADY
        .S1_AXI_ARID   (dcache_axi.arid),      // input wire [0 : 0] S1_AXI_ARID
        .S1_AXI_ARADDR (dcache_axi.araddr),    // input wire [31 : 0] S1_AXI_ARADDR
        .S1_AXI_ARLEN  (dcache_axi.arlen),     // input wire [7 : 0] S1_AXI_ARLEN
        .S1_AXI_ARSIZE (dcache_axi.arsize),    // input wire [2 : 0] S1_AXI_ARSIZE
        .S1_AXI_ARBURST(dcache_axi.arburst),   // input wire [1 : 0] S1_AXI_ARBURST
        .S1_AXI_ARLOCK (1'b0),                 // input wire S1_AXI_ARLOCK
        .S1_AXI_ARCACHE(dcache_axi.arcache),   // input wire [3 : 0] S1_AXI_ARCACHE
        .S1_AXI_ARPROT (3'b0),                 // input wire [2 : 0] S1_AXI_ARPROT
        .S1_AXI_ARQOS  (4'b0),                 // input wire [3 : 0] S1_AXI_ARQOS
        .S1_AXI_ARVALID(dcache_axi.arvalid),   // input wire S1_AXI_ARVALID
        .S1_AXI_ARREADY(dcache_axi.arready),   // output wire S1_AXI_ARREADY
        .S1_AXI_ARUSER (1'b0),                 // input wire [0 : 0] S1_AXI_ARUSER
        .S1_AXI_RID    (dcache_axi.rid),       // output wire [0 : 0] S1_AXI_RID
        .S1_AXI_RDATA  (dcache_axi.rdata),     // output wire [127 : 0] S1_AXI_RDATA
        .S1_AXI_RRESP  (dcache_axi.rresp),     // output wire [1 : 0] S1_AXI_RRESP
        .S1_AXI_RLAST  (dcache_axi.rlast),     // output wire S1_AXI_RLAST
        .S1_AXI_RVALID (dcache_axi.rvalid),    // output wire S1_AXI_RVALID
        .S1_AXI_RREADY (dcache_axi.rready),    // input wire S1_AXI_RREADY
        .S2_AXI_AWID   (uncache_axi.awid),     // input wire [0 : 0] S2_AXI_AWID
        .S2_AXI_AWADDR (uncache_axi.awaddr),   // input wire [31 : 0] S2_AXI_AWADDR
        .S2_AXI_AWLEN  (uncache_axi.awlen),    // input wire [7 : 0] S2_AXI_AWLEN
        .S2_AXI_AWSIZE (uncache_axi.awsize),   // input wire [2 : 0] S2_AXI_AWSIZE
        .S2_AXI_AWBURST(uncache_axi.awburst),  // input wire [1 : 0] S2_AXI_AWBURST
        .S2_AXI_AWLOCK (1'b0),                 // input wire S2_AXI_AWLOCK
        .S2_AXI_AWCACHE(uncache_axi.awcache),  // input wire [3 : 0] S2_AXI_AWCACHE
        .S2_AXI_AWPROT (3'b0),                 // input wire [2 : 0] S2_AXI_AWPROT
        .S2_AXI_AWQOS  (4'b0),                 // input wire [3 : 0] S2_AXI_AWQOS
        .S2_AXI_AWVALID(uncache_axi.awvalid),  // input wire S2_AXI_AWVALID
        .S2_AXI_AWREADY(uncache_axi.awready),  // output wire S2_AXI_AWREADY
        .S2_AXI_AWUSER (1'b0),                 // input wire [0 : 0] S2_AXI_AWUSER
        .S2_AXI_WDATA  (uncache_axi.wdata),    // input wire [127 : 0] S2_AXI_WDATA
        .S2_AXI_WSTRB  (uncache_axi.wstrb),    // input wire [15 : 0] S2_AXI_WSTRB
        .S2_AXI_WLAST  (uncache_axi.wlast),    // input wire S2_AXI_WLAST
        .S2_AXI_WVALID (uncache_axi.wvalid),   // input wire S2_AXI_WVALID
        .S2_AXI_WREADY (uncache_axi.wready),   // output wire S2_AXI_WREADY
        .S2_AXI_BRESP  (uncache_axi.bresp),    // output wire [1 : 0] S2_AXI_BRESP
        .S2_AXI_BID    (uncache_axi.bid),      // output wire [0 : 0] S2_AXI_BID
        .S2_AXI_BVALID (uncache_axi.bvalid),   // output wire S2_AXI_BVALID
        .S2_AXI_BREADY (uncache_axi.bready),   // input wire S2_AXI_BREADY
        .S2_AXI_ARID   (uncache_axi.arid),     // input wire [0 : 0] S2_AXI_ARID
        .S2_AXI_ARADDR (uncache_axi.araddr),   // input wire [31 : 0] S2_AXI_ARADDR
        .S2_AXI_ARLEN  (uncache_axi.arlen),    // input wire [7 : 0] S2_AXI_ARLEN
        .S2_AXI_ARSIZE (uncache_axi.arsize),   // input wire [2 : 0] S2_AXI_ARSIZE
        .S2_AXI_ARBURST(uncache_axi.arburst),  // input wire [1 : 0] S2_AXI_ARBURST
        .S2_AXI_ARLOCK (1'b0),                 // input wire S2_AXI_ARLOCK
        .S2_AXI_ARCACHE(uncache_axi.arcache),  // input wire [3 : 0] S2_AXI_ARCACHE
        .S2_AXI_ARPROT (3'b0),                 // input wire [2 : 0] S2_AXI_ARPROT
        .S2_AXI_ARQOS  (4'b0),                 // input wire [3 : 0] S2_AXI_ARQOS
        .S2_AXI_ARVALID(uncache_axi.arvalid),  // input wire S2_AXI_ARVALID
        .S2_AXI_ARREADY(uncache_axi.arready),  // output wire S2_AXI_ARREADY
        .S2_AXI_ARUSER (1'b0),                 // input wire [0 : 0] S2_AXI_ARUSER
        .S2_AXI_RID    (uncache_axi.rid),      // output wire [0 : 0] S2_AXI_RID
        .S2_AXI_RDATA  (uncache_axi.rdata),    // output wire [127 : 0] S2_AXI_RDATA
        .S2_AXI_RRESP  (uncache_axi.rresp),    // output wire [1 : 0] S2_AXI_RRESP
        .S2_AXI_RLAST  (uncache_axi.rlast),    // output wire S2_AXI_RLAST
        .S2_AXI_RVALID (uncache_axi.rvalid),   // output wire S2_AXI_RVALID
        .S2_AXI_RREADY (uncache_axi.rready),   // input wire S2_AXI_RREADY
        .M0_AXI_AWID   (awid),                 // output wire [3 : 0] M0_AXI_AWID
        .M0_AXI_AWADDR (awaddr),               // output wire [31 : 0] M0_AXI_AWADDR
        .M0_AXI_AWLEN  (awlen),                // output wire [7 : 0] M0_AXI_AWLEN
        .M0_AXI_AWSIZE (awsize),               // output wire [2 : 0] M0_AXI_AWSIZE
        .M0_AXI_AWBURST(awburst),              // output wire [1 : 0] M0_AXI_AWBURST
        .M0_AXI_AWLOCK (awlock),               // output wire M0_AXI_AWLOCK
        .M0_AXI_AWCACHE(awcache),              // output wire [3 : 0] M0_AXI_AWCACHE
        .M0_AXI_AWPROT (awprot),               // output wire [2 : 0] M0_AXI_AWPROT
        .M0_AXI_AWQOS  (),                     // output wire [3 : 0] M0_AXI_AWQOS
        .M0_AXI_AWVALID(awvalid),              // output wire M0_AXI_AWVALID
        .M0_AXI_AWREADY(awready),              // input wire M0_AXI_AWREADY
        .M0_AXI_WDATA  (wdata),                // output wire [31 : 0] M0_AXI_WDATA
        .M0_AXI_WSTRB  (wstrb),                // output wire [3 : 0] M0_AXI_WSTRB
        .M0_AXI_WLAST  (wlast),                // output wire M0_AXI_WLAST
        .M0_AXI_WVALID (wvalid),               // output wire M0_AXI_WVALID
        .M0_AXI_WREADY (wready),               // input wire M0_AXI_WREADY
        .M0_AXI_BRESP  (bresp),                // input wire [1 : 0] M0_AXI_BRESP
        .M0_AXI_BID    (bid),                  // input wire [3 : 0] M0_AXI_BID
        .M0_AXI_BVALID (bvalid),               // input wire M0_AXI_BVALID
        .M0_AXI_BREADY (bready),               // output wire M0_AXI_BREADY
        .M0_AXI_ARID   (arid),                 // output wire [3 : 0] M0_AXI_ARID
        .M0_AXI_ARADDR (araddr),               // output wire [31 : 0] M0_AXI_ARADDR
        .M0_AXI_ARLEN  (arlen),                // output wire [7 : 0] M0_AXI_ARLEN
        .M0_AXI_ARSIZE (arsize),               // output wire [2 : 0] M0_AXI_ARSIZE
        .M0_AXI_ARBURST(arburst),              // output wire [1 : 0] M0_AXI_ARBURST
        .M0_AXI_ARLOCK (arlock),               // output wire M0_AXI_ARLOCK
        .M0_AXI_ARCACHE(arcache),              // output wire [3 : 0] M0_AXI_ARCACHE
        .M0_AXI_ARPROT (arprot),               // output wire [2 : 0] M0_AXI_ARPROT
        .M0_AXI_ARQOS  (),                     // output wire [3 : 0] M0_AXI_ARQOS
        .M0_AXI_ARVALID(arvalid),              // output wire M0_AXI_ARVALID
        .M0_AXI_ARREADY(arready),              // input wire M0_AXI_ARREADY
        .M0_AXI_RID    (rid),                  // input wire [3 : 0] M0_AXI_RID
        .M0_AXI_RDATA  (rdata),                // input wire [31 : 0] M0_AXI_RDATA
        .M0_AXI_RRESP  (rresp),                // input wire [1 : 0] M0_AXI_RRESP
        .M0_AXI_RLAST  (rlast),                // input wire M0_AXI_RLAST
        .M0_AXI_RVALID (rvalid),               // input wire M0_AXI_RVALID
        .M0_AXI_RREADY (rready)                // output wire M0_AXI_RREADY
    );
`else
    // AXI Arbitary
    axi_3x1_crossbar #(
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .S_ID_WIDTH(2),
        .M_ID_WIDTH(4),
        .M00_ADDR_WIDTH(32)
    ) u_axi_3x1_crossbar (
        .clk            (clk),
        .rst            (rst),
        .s00_axi_awid   (icache_axi.awid),
        .s00_axi_awaddr (icache_axi.awaddr),
        .s00_axi_awlen  (icache_axi.awlen),
        .s00_axi_awsize (icache_axi.awsize),
        .s00_axi_awburst(icache_axi.awburst),
        .s00_axi_awcache(icache_axi.awcache),
        .s00_axi_awvalid(icache_axi.awvalid),
        .s00_axi_awready(icache_axi.awready),
        .s00_axi_wdata  (icache_axi.wdata),
        .s00_axi_wstrb  (icache_axi.wstrb),
        .s00_axi_wlast  (icache_axi.wlast),
        .s00_axi_wvalid (icache_axi.wvalid),
        .s00_axi_wready (icache_axi.wready),
        .s00_axi_bid    (icache_axi.bid),
        .s00_axi_bresp  (icache_axi.bresp),
        .s00_axi_bvalid (icache_axi.bvalid),
        .s00_axi_bready (icache_axi.bready),
        .s00_axi_arid   (icache_axi.arid),
        .s00_axi_araddr (icache_axi.araddr),
        .s00_axi_arlen  (icache_axi.arlen),
        .s00_axi_arsize (icache_axi.arsize),
        .s00_axi_arburst(icache_axi.arburst),
        .s00_axi_arcache(icache_axi.arcache),
        .s00_axi_arvalid(icache_axi.arvalid),
        .s00_axi_arready(icache_axi.arready),
        .s00_axi_rid    (icache_axi.rid),
        .s00_axi_rdata  (icache_axi.rdata),
        .s00_axi_rresp  (icache_axi.rresp),
        .s00_axi_rlast  (icache_axi.rlast),
        .s00_axi_rvalid (icache_axi.rvalid),
        .s00_axi_rready (icache_axi.rready),
        .s01_axi_awid   (dcache_axi.awid),
        .s01_axi_awaddr (dcache_axi.awaddr),
        .s01_axi_awlen  (dcache_axi.awlen),
        .s01_axi_awsize (dcache_axi.awsize),
        .s01_axi_awburst(dcache_axi.awburst),
        .s01_axi_awcache(dcache_axi.awcache),
        .s01_axi_awvalid(dcache_axi.awvalid),
        .s01_axi_awready(dcache_axi.awready),
        .s01_axi_wdata  (dcache_axi.wdata),
        .s01_axi_wstrb  (dcache_axi.wstrb),
        .s01_axi_wlast  (dcache_axi.wlast),
        .s01_axi_wvalid (dcache_axi.wvalid),
        .s01_axi_wready (dcache_axi.wready),
        .s01_axi_bid    (dcache_axi.bid),
        .s01_axi_bresp  (dcache_axi.bresp),
        .s01_axi_bvalid (dcache_axi.bvalid),
        .s01_axi_bready (dcache_axi.bready),
        .s01_axi_arid   (dcache_axi.arid),
        .s01_axi_araddr (dcache_axi.araddr),
        .s01_axi_arlen  (dcache_axi.arlen),
        .s01_axi_arsize (dcache_axi.arsize),
        .s01_axi_arburst(dcache_axi.arburst),
        .s01_axi_arcache(dcache_axi.arcache),
        .s01_axi_arvalid(dcache_axi.arvalid),
        .s01_axi_arready(dcache_axi.arready),
        .s01_axi_rid    (dcache_axi.rid),
        .s01_axi_rdata  (dcache_axi.rdata),
        .s01_axi_rresp  (dcache_axi.rresp),
        .s01_axi_rlast  (dcache_axi.rlast),
        .s01_axi_rvalid (dcache_axi.rvalid),
        .s01_axi_rready (dcache_axi.rready),
        .m00_axi_awid   (awid),
        .m00_axi_awaddr (awaddr),
        .m00_axi_awlen  (awlen),
        .m00_axi_awsize (awsize),
        .m00_axi_awburst(awburst),
        .m00_axi_awlock (awlock),
        .m00_axi_awcache(awcache),
        .m00_axi_awprot (awprot),
        .m00_axi_awvalid(awvalid),
        .m00_axi_awready(awready),
        .m00_axi_wdata  (wdata),
        .m00_axi_wstrb  (wstrb),
        .m00_axi_wlast  (wlast),
        .m00_axi_wvalid (wvalid),
        .m00_axi_wready (wready),
        .m00_axi_bid    (bid),
        .m00_axi_bresp  (bresp),
        .m00_axi_bvalid (bvalid),
        .m00_axi_bready (bready),
        .m00_axi_arid   (arid),
        .m00_axi_araddr (araddr),
        .m00_axi_arlen  (arlen),
        .m00_axi_arsize (arsize),
        .m00_axi_arburst(arburst),
        .m00_axi_arlock (arlock),
        .m00_axi_arcache(arcache),
        .m00_axi_arprot (arprot),
        .m00_axi_arvalid(arvalid),
        .m00_axi_arready(arready),
        .m00_axi_rid    (rid),
        .m00_axi_rdata  (rdata),
        .m00_axi_rresp  (rresp),
        .m00_axi_rlast  (rlast),
        .m00_axi_rvalid (rvalid),
        .m00_axi_rready (rready)
    );

`endif

    // All frontend structures
    frontend u_frontend (
        .clk(clk),
        .rst(rst),

        // <-> ICache
        .icache_read_req_o(frontend_icache_rreq),  // -> ICache
        .icache_read_req_uncached_o(frontend_icache_rreq_uncached),
        .icache_read_addr_o(frontend_icache_addr),
        .icache_rreq_ack_i(icache_frontend_rreq_ack),
        .icache_read_valid_i(icache_frontend_valid),  // <- ICache
        .icache_read_data_i(icache_frontend_data),  // <- ICache

        // <-> Backend
        .backend_next_pc_i(next_pc),  // backend PC, <- pc_gen
        .backend_flush_i(backend_redirect),  // backend flush, usually come with next_pc
        .backend_flush_ftq_id_i(backend_redirect_ftq_id),
        .backend_commit_bitmask_i(backend_commit_bitmask),
        .backend_commit_ftq_id_i(backend_commit_ftq_id),
        .backend_commit_meta_i(backend_commit_meta),
        .backend_commit_block_bitmask_i(backend_commit_block_bitmask),

        .backend_ftq_meta_update_valid_i(ex_is_branch[0]),
        .backend_ftq_meta_update_ftb_dirty_i(ex_jump_target_mispredict[0]),
        .backend_ftq_meta_update_jump_target_i(ex_jump_target_addr[0]),
        .backend_ftq_meta_update_fall_through_i(ex_fall_through_addr[0]),
        .backend_ftq_update_meta_id_i(ex_redirect_ftq_id[0]),
        // <-> EX
        .ex_query_addr_i(ex_ftq_query_addr[0]),
        .ex_query_pc_o(ex_ftq_query_pc[0]),

        // <-> Instruction Buffer
        .instr_buffer_stallreq_i(ib_frontend_stallreq),   // instruction buffer is full
        .instr_buffer_o         (frontend_ib_instr_info), // -> IB

        // <- CSR
        .csr_pg  (csr_pg),
        .csr_da  (csr_da),
        .csr_dmw0(csr_dmw0),
        .csr_dmw1(csr_dmw1),
        .csr_plv (csr_plv),
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
                .has_int(has_int),
                .csr_plv(csr_plv)
            );
        end
    endgenerate

    // ID_DISPATCH -> EXE
    id_dispatch_struct [1:0] id_dispatch_dispatch;

    // ID -- DISPATCH, Sequential
    id_dispatch u_id_dispatch (
        .clk                 (clk),
        .rst                 (rst),
        .stall               (~pipeline_advance[5]),
        .flush               (backend_redirect),
        .id_i                (id_id_dispatch),
        .id_dispatch_accept_o(id_ib_accept),
        // Dispatch
        .dispatch_issue_i    (dispatch_id_accept),
        .dispatch_o          (id_dispatch_dispatch)
    );

    // Dispatch -> EXE
    dispatch_ex_struct [1:0] dispatch_exe;

    // Data forwarding
    data_forward_t [ISSUE_WIDTH-1:0]
        ex_data_forward, mem1_data_forward, mem2_data_forward, wb_data_forward;

    // Dispatch Stage, Sequential logic
    dispatch u_dispatch (
        .clk(clk),
        .rst(rst),

        // <- ID
        .id_i(id_dispatch_dispatch),

        // <-> Ctrl
        .stall(~pipeline_advance[4]),
        .flush(backend_redirect),

        // Data forwarding    
        .ex_data_forward_i  (ex_data_forward),
        .mem1_data_forward_i(mem1_data_forward),
        .mem2_data_forward_i(mem2_data_forward),
        .wb_data_forward_i  (wb_data_forward),

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
        .exe_o(dispatch_exe),

        // PMU
        .pmu_dispatch_backend_nop(pmu_data.dispatch_backend_nop),
        .pmu_dispatch_frontend_nop(pmu_data.dispatch_frontend_nop),
        .pmu_dispatch_single_issue(pmu_data.dispatch_single_issue),
        .pmu_dispatch_datadep_nop(pmu_data.dispatch_datadep_nop),
        .pmu_dispatch_instr_cnt(pmu_data.dispatch_instr_cnt)
    );


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
    generate
        for (genvar i = 0; i < 2; i++) begin : ex
            ex u_ex (
                .clk(clk),
                .rst(rst),

                // Pipeline control signals
                .flush(pipeline_flush[3]),
                .clear(pipeline_clear[3]),
                .advance(pipeline_advance[3]),
                .advance_ready(ex_advance_ready[i]),

                // Previous stage
                .dispatch_i (dispatch_exe[i]),
                // Next stage
                .ex_o_buffer(ex_mem_signal[i]),

                // <-> CSR
                .LLbit_i(LLbit_o),
                .timer_64(csr_timer_64),
                .tid(csr_tid),
                .csr_ex_signal(csr_mem_signal),

                // <-> FTQ, next FTQ pc query
                .ftq_query_addr_o(ex_ftq_query_addr[i]),
                .ftq_query_pc_i  (ex_ftq_query_pc[i]),

                .dcache_rreq_o (mem_cache_signal[i]),
                .dcache_ready_i(i == 0 ? dcache_ready : 1),

                .icacop_en_o  (icacop_op_en[i]),
                .icacop_mode_o(icacop_op_mode[i]),
                .icacop_ack_i (icacop_ack),

                .dcacop_en_o  (dcacop_op_en[i]),
                .dcacop_mode_o(dcacop_op_mode[i]),

                // Redirect signals
                .ex_redirect_o(ex_redirect[i]),
                .ex_redirect_target_o(ex_redirect_target[i]),
                .ex_redirect_ftq_id_o(ex_redirect_ftq_id[i]),
                // BPU train meta
                .ex_is_branch_o(ex_is_branch[i]),
                .ex_jump_target_mispredict_o(ex_jump_target_mispredict[i]),
                .ex_jump_target_addr_o(ex_jump_target_addr[i]),
                .ex_fall_through_addr_o(ex_fall_through_addr[i]),

                // -> Dispatch, data forward
                .data_forward_o(ex_data_forward[i]),

                // -> TLB
                .tlb_rreq_o(tlb_data_rreq[i])
            );
        end
    endgenerate


    mem1_mem2_struct mem1_mem2_signal[2];
    mem2_wb_struct mem2_wb_signal[2];
    tlb_inv_t tlb_inv_signal_i;

    assign tlb_mem_signal = {
        tlb_data_result.tag,
        tlb_data_result.found,
        tlb_data_result.tlb_index,
        tlb_data_result.tlb_v,
        tlb_data_result.tlb_d,
        tlb_data_result.tlb_mat,
        tlb_data_result.tlb_plv
    };

    assign csr_mem_signal = {csr_pg, csr_da, csr_dmw0, csr_dmw1, csr_plv, csr_datm};

    ////////////////////////////////////////////////////////////////
    // MEM1
    ////////////////////////////////////////////////////////////////
    generate
        for (genvar i = 0; i < 2; i++) begin : mem1
            mem1 u_mem1 (
                .clk(clk),
                .rst(rst),

                // Pipeline control signals
                .flush(pipeline_flush[2]),
                .clear(pipeline_clear[2]),
                .advance(pipeline_advance[2]),
                .advance_ready(mem1_advance_ready[i]),

                // Previous stage
                .ex_i(ex_mem_signal[i]),
                // Next stage
                .mem2_o_buffer(mem1_mem2_signal[i]),

                .uncache_en(mem_uncache_en[i]),

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

    ////////////////////////////////////////////////////////////////
    // MEM2
    ////////////////////////////////////////////////////////////////
    generate
        for (genvar i = 0; i < 2; i = i + 1) begin : mem2
            mem2 u_mem2 (
                .clk(clk),
                .rst(rst),

                // Pipeline control signals
                .flush(pipeline_flush[1]),
                .clear(pipeline_clear[1]),
                .advance(pipeline_advance[1]),
                .advance_ready(mem2_advance_ready[i]),

                // Previous stage
                .mem1_i(mem1_mem2_signal[i]),
                // Next stage
                .mem2_o_buffer(mem2_wb_signal[i]),

                // -> Dispatch, data forward
                .data_forward_o(mem2_data_forward[i]),

                // <- DCache
                .mem_valid(mem_valid[i]),
                .data_ok(mem_data_ok),
                .cache_data_i(cache_mem_data)
            );
        end
    endgenerate

    wb_ctrl_struct [1:0] wb_ctrl_signal;

    ////////////////////////////////////////////////////////////////
    // WB
    ////////////////////////////////////////////////////////////////
    generate
        for (genvar i = 0; i < 2; i++) begin : wb
            wb u_wb (
                .clk(clk),
                .rst(rst),

                // Pipeline control signals
                .flush  (pipeline_flush[0]),
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

    wb_llbit_t llbit_write;

    ctrl u_ctrl (
        .clk(clk),
        .rst(rst),

        // -> Frontend
        .backend_commit_bitmask_o(backend_commit_bitmask),
        .backend_commit_block_bitmask_o(backend_commit_block_bitmask),
        .backend_flush_ftq_id_o(ctrl_frontend_ftq_id),
        .backend_commit_ftq_id_o(backend_commit_ftq_id),
        .backend_commit_meta_o(backend_commit_meta),

        // <- WB
        .wb_i(wb_ctrl_signal),

        // Pipeline control signal
        .ex_redirect_i(ex_redirect),
        .ex_advance_ready_i(ex_advance_ready),
        .mem1_advance_ready_i(mem1_advance_ready),
        .mem2_advance_ready_i(mem2_advance_ready),
        .flush_o(pipeline_flush),
        .advance_o(pipeline_advance),
        .clear_o(pipeline_clear),
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
        .llbit_signal(llbit_write),

        .inv_o(tlb_inv_signal_i),
        .inv_stallreq(inv_stallreq),

        .tlbwr_en  (tlb_write_signal_i.tlbwr_en),
        .tlbsrch_en(tlbsrch_en),
        .tlbfill_en(tlb_write_signal_i.tlbfill_en),

        // <- TLB
        .tlbsrch_result_i(tlb_mem_signal),

        .regfile_o  (regfile_write),
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
        .interrupt_i({1'b0, intrpt}),
        .ecode_i(csr_ecode_i),
        .write_signal_1(csr_write[0]),
        .write_signal_2(csr_write[1]),
        .raddr(dispatch_csr_read_addr),
        .rdata(dispatch_csr_data),
        .llbit_i(llbit_write.value),
        .llbit_set_i(llbit_write.we),
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
        .asid_in(tlb_read_signal_o.asid),

        // PMU
        .pmu_in(pmu_data)
    );

    tlb u_tlb (
        .clk           (clk),
        .asid          (csr_asid),
        //inst addr trans
        .inst_i        (frontend_tlb),
        .inst_o        (tlb_inst),
        //data addr trans 
        .data_i        (tlb_data_rreq[0]),    // Memory access is single issued
        .data_o        (tlb_data_result),
        //tlbwr tlbfill tlb write 
        .write_signal_i(tlb_write_signal_i),
        //tlbp tlb read
        .read_signal_o (tlb_read_signal_o),
        //invtlb 
        .inv_signal_i  (tlb_inv_signal_i),
        //from csr
        .csr_dmw0      (csr_dmw0),
        .csr_dmw1      (csr_dmw1),
        .csr_da        (csr_da),
        .csr_pg        (csr_pg),

        .rand_index_diff(rand_index_diff)
    );

    // Difftest Delay signals
    diff_commit [COMMIT_WIDTH-1:0] difftest_commit_info_delay1;
    logic csr_rstat_commit[2];
    logic [`RegBus] csr_data_commit[2];

    always_ff @(posedge clk) begin
        difftest_commit_info_delay1 <= difftest_commit_info;
        csr_rstat_commit[0] <= (csr_write[0].we && (csr_write[0].addr == 14'h5)) | difftest_commit_info[0].csr_rstat;
        csr_data_commit[0] <= difftest_commit_info[0].csr_rstat ? regfile_write[0].wdata : csr_write[0].data;
    end

    always_ff @(posedge clk) begin
        debug0_wb_pc <= difftest_commit_info[0].pc;
        debug0_wb_rf_wen <= {3'b0, regfile_write[0].we};
        debug0_wb_rf_wdata <= regfile_write[0].wdata;
        debug0_wb_rf_wnum <= regfile_write[0].waddr;
`ifdef CPU_2CMT
        debug1_wb_pc <= difftest_commit_info[1].pc;
        debug1_wb_rf_wen <= {3'b0, regfile_write[1].we};
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
    logic [$clog2(TLB_NUM)-1:0] rand_index_commit;

    always_ff @(posedge clk) begin
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
        .clock(aclk),
        .coreid(0),  // only one core, so always 0
        .index(0),  // commit channel index
        .valid(difftest_commit_info_delay1[0].valid),  // 1 means valid
        .pc(difftest_commit_info_delay1[0].pc),
        .instr(difftest_commit_info_delay1[0].instr),
        .skip(0),  // not implemented in CHIPLAB, keep 0 
        .is_TLBFILL(tlbfill_en_commit),
        .TLBFILL_index(rand_index_commit),
        .is_CNTinst(difftest_commit_info_delay1[0].is_CNTinst),
        .timer_64_value(difftest_commit_info_delay1[0].timer_64),
        .wen(debug0_wb_rf_wen),
        .wdest({3'b0, debug0_wb_rf_wnum}),
        .wdata(debug0_wb_rf_wdata),
        .csr_rstat(csr_rstat_commit[0]),
        .csr_data(csr_data_commit[0])
    );
    DifftestInstrCommit difftest_instr_commit_1 (
        .clock         (aclk),
        .coreid        (0),                                          // only one core, so always 0
        .index         (1),                                          // commit channel index
        .skip          (0),
        .valid         (difftest_commit_info_delay1[1].valid),       // 1 means valid
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

    DifftestStoreEvent difftest_store_event (
        .clock(aclk),
        .coreid(0),
        .index(0),
        .valid              (difftest_commit_info_delay1[0].inst_st_en | difftest_commit_info_delay1[1].inst_st_en),
        .storePAddr         (difftest_commit_info_delay1[0].st_paddr | difftest_commit_info_delay1[1].st_paddr),
        .storeVAddr         (difftest_commit_info_delay1[0].st_vaddr |difftest_commit_info_delay1[1].st_vaddr),
        .storeData(difftest_commit_info_delay1[0].st_data | difftest_commit_info_delay1[1].st_data)
    );

    DifftestLoadEvent difftest_load_event (
        .clock(aclk),
        .coreid(0),
        .index(0),
        .valid              (difftest_commit_info_delay1[0].inst_ld_en | difftest_commit_info_delay1[1].inst_ld_en),
        .paddr(difftest_commit_info_delay1[0].ld_paddr | difftest_commit_info_delay1[1].ld_paddr),
        .vaddr(difftest_commit_info_delay1[0].ld_vaddr | difftest_commit_info_delay1[1].ld_vaddr)
    );

    DifftestTrapEvent difftest_trap_event (
        .clock   (aclk),
        .coreid  (0),
        .valid   (),
        .code    (),
        .pc      (),
        .cycleCnt(),
        .instrCnt()
    );

    DifftestExcpEvent difftest_excp_event (
        .clock        (aclk),
        .coreid       (0),
        .excp_valid   (excp_flush_commit),
        .eret         (ertn_flush_commit),
        .intrNo       (u_cs_reg.csr_estat[12:2]),
        .cause        (csr_ecode_commit),
        .exceptionPC  (excp_pc_commit),
        .exceptionInst(excp_instr_commit)
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
        .llbctl({u_cs_reg.csr_llbctl[31:1], u_cs_reg.llbit}),

        .dmw0(u_cs_reg.csr_dmw0),
        .dmw1(u_cs_reg.csr_dmw1)
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
        .clk(clk),  // input wire clk


        .probe0(u_dcache.u_dcache_fifo.empty),  // input wire [3:0]  probe0  
        .probe1(u_dcache.cacop_mode_i),  // input wire [3:0]  probe1 
        .probe2(u_dcache.u_dcache_fifo.queue_valid),  // input wire [3:0]  probe2 
        .probe3(u_dcache.fifo_axi_wr_data),  // input wire [31:0]  probe3 
        .probe4(u_dcache.fifo_full),  // input wire [0:0]  probe4 
        .probe5(u_dcache.dcache_stall),  // input wire [0:0]  probe5 
        .probe6(u_dcache.state),  // input wire [31:0]  probe6 
        .probe7(u_dcache.cacop_op_mode0),  // input wire [0:0]  probe7 
        .probe8(u_dcache.cacop_i),  // input wire [0:0]  probe8 
        .probe9(u_dcache.vaddr),  // input wire [31:0]  probe9 
        .probe10(0),  // input wire [31:0]  probe10 
        .probe11(u_dcache.axi_addr_o),  // input wire [0:0]  probe11 
        .probe12(u_dcache.fifo_axi_wr_req),  // input wire [31:0]  probe12 
        .probe13(u_dcache.axi_wdata_o),  // input wire [31:0]  probe13 
        .probe14(0),  // input wire [31:0]  probe14 
        .probe15(u_dcache.fifo_axi_wr_addr),  // input wire [31:0]  probe15 
        .probe16(0),  // input wire [0:0]  probe16 
        .probe17(0),  // input wire [0:0]  probe17 
        .probe18(0),  // input wire [0:0]  probe18 
        .probe19(u_dcache.axi_bvalid_i),  // input wire [0:0]  probe19
        .probe20(u_cs_reg.timer_64),  // input wire [63:0]  probe20 
        .probe21(u_dcache.cacop_op_mode1),  // input wire [31:0]  probe21 
        .probe22(u_dcache.p3_cacop_op_mode0),  // input wire [31:0]  probe22 
        .probe23(u_dcache.p3_cacop_op_mode1),  // input wire [31:0]  probe23 
        .probe24(mem1[0].u_mem1.ex_i.instr_info.pc),  // input wire [31:0]  probe24 
        .probe25(mem1[0].u_mem1.ex_i.instr_info.instr),  // input wire [31:0]  probe25 
        .probe26(u_dcache.p3_cacop_op_mode2_hit),  // input wire [31:0]  probe26 
        .probe27(u_dcache.cacop_op_mode2_hit),  // input wire [0:0]  probe27
        .probe28(u_dcache.cacop_op_mode2),  // input wire [31:0]  probe28 
        .probe29(u_dcache.cacop_way),  // input wire [31:0]  probe29 
        .probe30(u_dcache.paddr),  // input wire [31:0]  probe30 
        .probe31(u_dcache.fifo_wreq),  // input wire [31:0]  probe31 
        .probe32(u_dcache.u_dcache_fifo.state),  // input wire [31:0]  probe32 
        .probe33(u_dcache.fifo_waddr),  // input wire [31:0]  probe33 
        .probe34(u_dcache.fifo_wdata),  // input wire [31:0]  probe34 
        .probe35(u_dcache.p3_cacop)  // input wire [31:0]  probe35
    );
`endif

endmodule
