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
`include "icache.sv"
`include "dummy_dcache.sv"
`include "ctrl.sv"
`include "pipeline_defines.sv"
`include "pipeline/1_decode/id.sv"
`include "pipeline/1_decode/id_dispatch.sv"
`include "pipeline/2_dispatch/dispatch.sv"
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
    assign rst   = ~rst_n;

    // ICache <-> AXI Controller
    logic icache_axi_rreq;
    logic axi_icache_rdy, axi_icache_rvalid;
    logic [127:0] axi_icache_data; // 128b
    logic [`RegBus] icache_axi_addr;

    // MEM <-> AXI Controller
    logic dcache_axi_rreq; // Read handshake
    logic axi_dcache_rd_rdy;
    logic axi_dcache_rvalid;
    logic dcache_axi_wreq; // Write handshake
    logic axi_dcache_wr_rdy;
    logic [`DataAddrBus] dcache_axi_raddr;
    logic [`DataAddrBus] dcache_axi_waddr;
    logic [`DataAddrBus] dcache_axi_addr;
    assign dcache_axi_addr = dcache_axi_rreq ? dcache_axi_raddr : dcache_axi_wreq ? dcache_axi_waddr : 0;
    logic [127:0] axi_dcache_data;
    logic [127:0] dcache_axi_data;
    logic [`RegBus] cache_mem_data;
    logic mem_data_ok,mem_addr_ok;
    logic [15:0] dcache_axi_wstrb; // Byte selection

    axi_master u_axi_master (
        .aclk   (aclk),
        .aresetn(aresetn),

        // <-> ICache
        .inst_cpu_addr_i(icache_axi_addr),
        .inst_cpu_data_o(axi_icache_data),
        .inst_id(4'b0000),  // Read Instruction only
        .icache_rd_type_i(3'b000), // Read 128b for 1 time
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
        .dcache_rd_type_i(3'b000), // For [31:0]
        .dcache_rd_rdy_o(axi_dcache_rd_rdy),
        .dcache_ret_valid_o(axi_dcache_rvalid),
        .dcache_ret_last_o(), // same as ICache
        .dcache_wr_req_i(dcache_axi_wreq),
        .dcache_wr_type_i(3'b000), 
        .dcache_wr_data(dcache_axi_data),
        .dcache_wr_rdy(axi_dcache_wr_rdy),


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

    mem_cache_struct mem_cache_signal[2];
    logic mem_cache_we,mem_cache_ce;
    logic [3:0] mem_cache_sel;
    logic [31:0] mem_cache_addr,mem_cache_data;
    
    assign mem_cache_ce = mem_cache_signal[0].ce | mem_cache_signal[1].ce;
    assign mem_cache_we = mem_cache_signal[0].we | mem_cache_signal[1].we;
    assign mem_cache_sel = mem_cache_signal[0].we ? mem_cache_signal[0].sel : mem_cache_signal[1].we ? mem_cache_signal[1].sel : 0;
    assign mem_cache_addr = mem_cache_signal[0].addr | mem_cache_signal[1].addr;
    assign mem_cache_data = mem_cache_signal[0].we ? mem_cache_signal[0].data : mem_cache_signal[1].we ? mem_cache_signal[1].data : 0;
   
    dummy_dcache u_dcache(
    	.clk       (clk       ),
        .rst       (rst       ),

        .valid     (mem_cache_ce),
        .op        (mem_cache_we),
        .uncache   (1'b0),
        .index     (mem_cache_addr[11:4]),
        .tag       (mem_cache_addr[31:12]),
        .offset    (mem_cache_addr[3:0]),
        .wstrb     (mem_cache_sel),
        .wdata     (mem_cache_data),
        .addr_ok   (mem_addr_ok),
        .data_ok   (mem_data_ok),
        .rdata     (cache_mem_data),

        // <-> AXI Controller
        .rd_req    (dcache_axi_rreq),
        .rd_type   (),
        .rd_addr   (dcache_axi_raddr),
        .rd_rdy    (axi_dcache_rd_rdy),
        .ret_valid (axi_dcache_rvalid),
        .ret_last  (),
        .ret_data  (axi_dcache_data),
        .wr_req    (dcache_axi_wreq),
        .wr_type   (),
        .wr_addr   (dcache_axi_waddr),
        .wr_wstrb  (dcache_axi_wstrb),
        .wr_data   (dcache_axi_data),
        .wr_rdy    (axi_dcache_wr_rdy)
    );
    

    // FETCH_WIDTH is 4
    localparam FETCH_WIDTH = 4;

    // Frontend -> ICache
    logic [1:0] frontend_icache_rreq;
    logic [1:0][`InstAddrBus] frontend_icache_addr;

    // ICache -> Frontend
    logic [1:0]icache_frontend_valid;
    logic [1:0][127:0] icache_frontend_data; // Cacheline is 128b

    icache u_icache(
       .clk          (clk          ),
       .rst          (rst          ),
       
       // Port A
       .rreq_1_i     (frontend_icache_rreq[0]),
       .raddr_1_i    (frontend_icache_addr[0]),
       .rvalid_1_o   (icache_frontend_valid[0]),
       .rdata_1_o    (icache_frontend_data[0]),
       // Port B
       .rreq_2_i     (frontend_icache_rreq[1]),
       .raddr_2_i    (frontend_icache_addr[1]),
       .rvalid_2_o   (icache_frontend_valid[1]),
       .rdata_2_o    (icache_frontend_data[1]),

       // <-> AXI Controller
       .axi_addr_o   (icache_axi_addr),
       .axi_rreq_o   (icache_axi_rreq),
       .axi_rdy_i    (axi_icache_rdy),
       .axi_rvalid_i (axi_icache_rvalid),
       .axi_rlast_i  (),
       .axi_data_i   (axi_icache_data)
   );
    

    // Frontend <-> Instruction Buffer
    logic ib_frontend_stallreq;
    instr_buffer_info_t frontend_ib_instr_info[FETCH_WIDTH];
    logic [`RegBus] next_pc;

    // Frontend <-> Backend 
    logic backend_flush;
    logic [1:0] is_last_in_block; // <- WB, suggest whether last instr in basic block is committed

    // All frontend structures
    frontend u_frontend (
        .clk(clk),
        .rst(rst),

        // <-> ICache
        .icache_read_addr_o(frontend_icache_addr),  // -> ICache
        .icache_read_req_o(frontend_icache_rreq),
        .icache_read_valid_i(icache_frontend_valid),  // <- ICache
        .icache_read_data_i(icache_frontend_data),  // <- ICache

        // <-> Backend
        .branch_update_info_i(),              // branch update signals, <- EXE Stage, unused
        .backend_next_pc_i   (next_pc),       // backend PC, <- pc_gen
        .backend_flush_i     (backend_flush), // backend flush, usually come with next_pc
        .backend_commit_i (is_last_in_block[0] | is_last_in_block[1]),

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
        .disable_cache(),

        // <-> TLB
        .inst_addr(tlb_inst_i.vaddr),
        .inst_addr_trans_en(inst_addr_trans_en),
        .dmw0_en(tlb_inst_i.dmw0_en),
        .dmw1_en(tlb_inst_i.dmw1_en),
        .inst_tlb_found(tlb_inst_o.tlb_found),
        .inst_tlb_v(tlb_inst_o.tlb_v),
        .inst_tlb_d(tlb_inst_o.tlb_d),
        .inst_tlb_mat(tlb_inst_o.tlb_mat),
        .inst_tlb_plv(tlb_inst_o.tlb_plv)
    );

    instr_buffer_info_t ib_backend_instr_info[2];  // IB -> ID
    logic [4:0] stall; // from 4->0 {mem_wb, ex_mem, dispatch_ex, id_dispatch, _}

    logic [1:0] dispatch_ib_accept;

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
        .backend_accept_i(dispatch_ib_accept),  // FIXME: does not carefully designed
        .backend_flush_i(backend_flush),  // Assure output is reset the next cycle
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
        .stall     (stall[1]),
        .flush     (backend_flush), // FIXME: does not carefully designed
        .id_i      (id_id_dispatch),
        .dispatch_o(id_dispatch_dispatch)
    );

    // Dispatch -> EXE
    dispatch_ex_struct [1:0] dispatch_exe;

    // Data forwarding
    ex_dispatch_struct [1:0] ex_data_forward;
    mem_data_forward_t [1:0] mem_data_forward;

    logic stallreq_from_dispatch;


    // Dispatch Stage, Sequential logic
    dispatch #(
        .DECODE_WIDTH(2),
        .EXE_STAGE_WIDTH(2),
        .MEM_STAGE_WIDTH(2)
    ) u_dispatch (
        .clk (clk),
        .rst (rst),

        // <- ID
        .id_i(id_dispatch_dispatch),

        .stallreq(stallreq_from_dispatch),
        .stall(stall[2]),
        .flush(backend_flush),

        // Data forwarding    
        .ex_data_forward(ex_data_forward),
        .mem_data_forward_i(mem_data_forward),

        // <-> Regfile
        .regfile_reg_read_valid_o(dispatch_regfile_reg_read_valid),
        .regfile_reg_read_addr_o (dispatch_regfile_reg_read_addr),
        .regfile_reg_read_data_i (regfile_dispatch_reg_read_data),

        // <-> CSR
        .csr_read_addr(dispatch_csr_read_addr),
        .csr_data(dispatch_csr_data),

        // -> IB
        .ib_accept_o(dispatch_ib_accept),

        // -> EXE
        .exe_o(dispatch_exe)
    );


    logic [`RegBus] branch_target_address[2];
    logic [`RegBus] link_addr;
    logic flush;


    //tlb
    logic inst_addr_trans_en;
    logic data_addr_trans_en;

    //csr
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

    logic [9:0] csr_asid;
    logic csr_pg;
    logic csr_da;
    logic [31:0] csr_dmw0;
    logic [31:0] csr_dmw1;
    logic [1:0] csr_datf;
    logic [1:0] csr_datm;
    logic [1:0] csr_plv;

    logic idle_flush;
    logic [`InstAddrBus] idle_pc;

    logic disable_cache;
    logic [1:0] branch_flag;

    assign backend_flush = excp_flush | ertn_flush | ((branch_flag[0] | branch_flag[1]) & ~stall[2]);

    // If ex is stalling, means that the branch flag maybe invalid and waiting for the right data
    // so no jumping if ex is stalling
    assign next_pc = branch_flag[0] & ~stall[2] ? branch_target_address[0] : 
                     branch_flag[1] & ~stall[2] ? branch_target_address[1] :
                     (excp_flush && !excp_tlbrefill) ? csr_eentry :
                     (excp_flush && excp_tlbrefill) ? csr_tlbrentry :
                     ertn_flush ? csr_era : `ZeroWord;


    ex_mem_struct ex_signal_o[2];
    logic [1:0] tlb_stallreq;

    // EXE Stage
    logic [1:0] ex_stallreq;
    generate
        for (genvar i = 0; i < 2; i++) begin : ex
            ex u_ex (
                .clk  (clk),
                .rst(rst),

                .dispatch_i(dispatch_exe[i]),
                .csr_vppn  (csr_vppn_o),

                .mem_data_forward_i(mem_data_forward),

                .ex_o(ex_signal_o[i]),

                .stallreq(ex_stallreq[i]),
                .tlb_stallreq(tlb_stallreq[i]),

                .branch_flag(branch_flag[i]),
                .branch_target_address(branch_target_address[i]),

                .ex_data_forward(ex_data_forward[i])

            );
        end
    endgenerate



    logic mem_data_addr_trans_en[2];
    logic mem_data_dmw0_en[2];
    logic mem_data_dmw1_en[2];


    ex_mem_struct mem_signal_i[2];
    logic [1:0] ex_mem_flush;
    generate
        for (genvar i = 0; i < 2; i++) begin : ex_mem
            ex_mem u_ex_mem (
                .clk(clk),
                .rst(rst),
                .excp_flush(excp_flush),
                .ertn_flush(ertn_flush),

                .ex_o (ex_signal_o[i]),
                .mem_i(mem_signal_i[i]),

                // <-> Ctrl
                .stall(stall[3]),
                .flush(ex_mem_flush[i])

            );
        end

    endgenerate

    mem_wb_struct mem_signal_o[2];

    logic [1:0] mem_stallreq;

    logic LLbit_o;
    logic mem_wb_LLbit_we[2];
    logic mem_wb_LLbit_value[2];
    logic cacop_op_mode_di[2];
    assign tlb_data_i.cacop_op_mode_di =  cacop_op_mode_di[0] |  cacop_op_mode_di[1];

    csr_to_mem_struct csr_mem_signal;
    tlb_to_mem_struct tlb_mem_signal;
    assign tlb_mem_signal = {tlb_data_o.found,tlb_data_o.tlb_index,tlb_data_o.tlb_v,
                            tlb_data_o.tlb_d,tlb_data_o.tlb_mat,tlb_data_o.tlb_plv};

    assign csr_mem_signal = {csr_pg,csr_da,csr_dmw0,csr_dmw1,csr_plv,csr_datm};
    //assign tlb_mem_signal = {data_tlb_found,data_tlb_index,data_tlb_v,data_tlb_d,data_tlb_mat,data_tlb_plv};

    logic wb_LLbit_we_i[2],wb_LLbit_value_i[2],data_fetch;
    generate
        for (genvar i = 0; i < 2; i++) begin : mem
            mem u_mem (
                .rst(rst),

                .signal_i(mem_signal_i[i]),

                .signal_o(mem_signal_o[i]),

                // -> cache 
                .signal_cache_o(mem_cache_signal[i]),

                // <- AXI Controller
                .addr_ok(mem_addr_ok),
                .data_ok(mem_data_ok),
                .data_fetch(data_fetch),
                .mem_data_i(cache_mem_data),

                // -> Ctrl
                .stallreq(mem_stallreq[i]),

                .LLbit_i(LLbit_o),
                .wb_LLbit_we_i(wb_LLbit_we_i[i]),
                .wb_LLbit_value_i(wb_LLbit_value_i[i]),
                .LLbit_we_o(mem_wb_LLbit_we[i]),
                .LLbit_value_o(mem_wb_LLbit_value[i]),

                // Data forward
                // -> Dispatch
                // -> EX
                .mem_data_forward_o(mem_data_forward[i])

            );
        end

    endgenerate

    logic fetch_flush;

    wb_ctrl wb_ctrl_signal[2];

    generate
        for (genvar i = 0; i < 2; i++) begin : mem_wb
            mem_wb u_mem_wb (
                .clk  (clk),
                .rst  (rst),
                .stall(stall[4]),

                .mem_signal_o(mem_signal_o[i]),

                .mem_LLbit_we(mem_wb_LLbit_we[i]),
                .mem_LLbit_value(mem_wb_LLbit_value[i]),

                .flush(flush),

                .csr_mem_signal(csr_mem_signal),
                .disable_cache(1'b0),

                //<- tlb
                .data_addr_trans_en(mem_data_addr_trans_en[i]),
                .dmw0_en(mem_data_dmw0_en[i]),
                .dmw1_en(mem_data_dmw1_en[i]),
                .cacop_op_mode_di(cacop_op_mode_di[i]),
                //-> tlb
                .tlb_mem_signal(tlb_mem_signal),

                //to ctrl
                .wb_ctrl_signal(wb_ctrl_signal[i]),

                // -> Frontend
                .is_last_in_block(is_last_in_block[i])
            );
        end
    endgenerate


    regfile #(
        .READ_PORTS(4)  // 2 for each ID, 2 ID in total, TODO: remove magic number
    ) u_regfile (
        .clk(clk),
        .rst(rst),

        .we_1   (reg_o[0].we),
        .pc_i_1 (reg_o[0].pc),
        .waddr_1(reg_o[0].waddr),
        .wdata_1(reg_o[0].wdata),
        .we_2   (reg_o[1].we),
        .pc_i_2 (reg_o[1].pc),
        .waddr_2(reg_o[1].waddr),
        .wdata_2(reg_o[1].wdata),

        // Read signals
        // Registers are read in dispatch stage
        .read_valid_i(dispatch_regfile_reg_read_valid),
        .read_addr_i (dispatch_regfile_reg_read_addr),
        .read_data_o (regfile_dispatch_reg_read_data)
    );

    // Difftest related
    // Ctrl -> DifftestEvents
    diff_commit difftest_commit_info[2];

    // Ctrl -> Regfile
    wb_reg  reg_o[2];

    csr_write_signal  csr_w_o[2];

    logic tlbrd_en;

    ctrl u_ctrl(
        .rst(rst),
        .wb_i_1(wb_ctrl_signal[0]),
        .wb_i_2(wb_ctrl_signal[1]),

        // <- EX
    	.ex_branch_flag_i (branch_flag),
        .ex_stallreq_i (ex_stallreq),
        .tlb_stallreq(tlb_stallreq),

        .stallreq_from_dispatch(stallreq_from_dispatch),
        .mem_stallreq_i(mem_stallreq),

        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush),
        .fetch_flush(fetch_flush),

        .stall(stall),
        .ex_mem_flush_o(ex_mem_flush),
        .flush(flush),

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

        .inv_o(tlb_inv_signal_i),

        .tlbwr_en(tlb_write_signal_i.tlbwr_en),
        .tlbsrch_en(tlbsrch_en),
        .tlbfill_en(tlb_write_signal_i.tlbfill_en),

        .reg_o_0(reg_o[0]),
        .reg_o_1(reg_o[1]),
        .csr_w_o_0(csr_w_o[0]),
        .csr_w_o_1(csr_w_o[1]),

        // -> Difftest
        .excp_instr(excp_instr),
        .commit_0(difftest_commit_info[0]),
        .commit_1(difftest_commit_info[1])
    );
    
    logic [`InstBus] excp_instr;
    logic [13:0] dispatch_csr_read_addr;
    logic [`RegBus] dispatch_csr_data;

    cs_reg u_cs_reg (
        .clk(clk),
        .rst(rst),
        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush),
        .interrupt_i({1'b0,intrpt}),
        .ecode_i(csr_ecode_i),
        .write_signal_1(csr_w_o[0]),
        .write_signal_2(csr_w_o[1]),
        .raddr(dispatch_csr_read_addr),
        .rdata(dispatch_csr_data),
        .llbit_i(wb_LLbit_value_i[0] | wb_LLbit_value_i[1]),
        .llbit_set_i(wb_LLbit_we_i[0] | wb_LLbit_we_i[1]),
        .llbit_o(LLbit_o),
        .vppn_o(csr_vppn_o),
        .era_i(csr_era_i),
        .timer_64_o(),
        .tid_o(),
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

    assign data_addr_trans_en = mem_data_addr_trans_en[0] | mem_data_addr_trans_en[1];
    assign tlb_data_i.dmw0_en = mem_data_dmw0_en[0] | mem_data_dmw0_en[1];
    assign tlb_data_i.dmw1_en = mem_data_dmw1_en[0] | mem_data_dmw1_en[1];
    assign tlb_data_i.vaddr = mem_cache_addr;
    assign tlb_data_i.fetch = data_fetch;

    inst_tlb_struct tlb_inst_i;
    tlb_inst_struct tlb_inst_o;
    data_tlb_struct tlb_data_i;
    tlb_data_struct tlb_data_o;
    tlb_write_in_struct tlb_write_signal_i;
    tlb_read_out_struct tlb_read_signal_o;
    tlb_inv_in_struct tlb_inv_signal_i;
    
    assign tlb_inst_i = {35'b0};

    tlb u_tlb (
        .clk               (clk),
        .asid              (csr_asid),
        //trans mode 
        .inst_addr_trans_en(inst_addr_trans_en),
        .data_addr_trans_en(data_addr_trans_en),
        //inst addr trans
        .inst_i(tlb_inst_i),
        .inst_o(tlb_inst_o),
        //data addr trans 
        .data_i(tlb_data_i),
        .data_o(tlb_data_o),
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
        .csr_pg(csr_pg)
    );

    // Difftest Delay signals
    diff_commit difftest_commit_info_delay1[2];
    always_ff @(posedge clk) begin
        difftest_commit_info_delay1 <= difftest_commit_info;
    end

    always_ff @(posedge clk) begin
        debug0_wb_pc <= reg_o[0].pc; 
        debug0_wb_rf_wen <= {3'b0,reg_o[0].we};
        debug0_wb_rf_wdata <= reg_o[0].wdata;
        debug0_wb_rf_wnum <= reg_o[0].waddr;
        `ifdef CPU_2CMT
        debug1_wb_pc <= reg_o[1].pc;
        debug1_wb_rf_wen <= {3'b0, reg_o[1].we};
        debug1_wb_rf_wdata <= reg_o[1].wdata;
        debug1_wb_rf_wnum <= reg_o[1].waddr;
        `endif
    end

    logic excp_flush_commit;
    logic ertn_flush_commit;
    logic [`RegBus]excp_pc_commit;
    logic [5:0] csr_ecode_commit;
    logic [`InstBus] excp_instr_commit;

    always_ff @(posedge clk) begin 
        excp_flush_commit <= excp_flush;
        ertn_flush_commit <= ertn_flush;
        excp_pc_commit <= csr_era_i;
        csr_ecode_commit <= csr_ecode_i;
        excp_instr_commit <= excp_instr;
    end
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
    DifftestInstrCommit difftest_instr_commit_1 (  
        .clock         (aclk),
        .coreid        (0),                             // only one core, so always 0
        .index         (1),                             // commit channel index
        .skip          (0),                             
        .valid         (difftest_commit_info_delay1[1].valid),  // 1 means valid
        .pc            (difftest_commit_info_delay1[1].pc),
        .instr         (difftest_commit_info_delay1[1].instr),
        .is_TLBFILL    (),
        .TLBFILL_index (),
        .is_CNTinst    (),
        .timer_64_value(),
        .wen           (debug1_wb_rf_wen),
        .wdest         ({3'b0, debug1_wb_rf_wnum}),
        .wdata         (debug1_wb_rf_wdata),
        .csr_rstat     (),
        .csr_data      ()
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

    // Currently unused
    /*
    DifftestLoadEvent DifftestLoadEvent(
        .clock              (aclk),
        .coreid             (0),
        .index              (0),
        .valid              (debug_commit_inst_ld_en),
        .paddr              (debug_commit_ld_paddr),
        .vaddr              (debug_commit_ld_paddr)
    );*/

    DifftestTrapEvent DifftestTrapEvent(
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
        .llbctl   (u_cs_reg.csr_llbctl),
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


endmodule
