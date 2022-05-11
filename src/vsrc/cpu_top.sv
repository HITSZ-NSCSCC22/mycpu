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
    output logic [31:0] debug0_wb_pc,
    output logic [ 3:0] debug0_wb_rf_wen,
    output logic [ 4:0] debug0_wb_rf_wnum,
    output logic [31:0] debug0_wb_rf_wdata
    `ifdef CPU_2debug_commit
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

    // Global enable signal
    logic chip_enable;

    // ICache <-> AXI Controller
    logic axi_busy;
    logic [`RegBus] axi_data;
    logic [`RegBus] axi_addr;

    // MEM <-> AXI Controller
    // TODO: replace with DCache
    logic data_axi_we;
    logic [`DataAddrBus] data_axi_addr;
    logic [`RegBus] data_axi_data;
    logic [`RegBus] axi_mem_data;
    logic data_axi_busy;


    mem_axi_struct mem_axi_signal[2];

    assign data_axi_we = mem_axi_signal[0].we | mem_axi_signal[1].we;
    assign data_axi_addr = mem_axi_signal[0].we ? mem_axi_signal[1].addr : mem_axi_signal[1].we ? mem_axi_signal[1].addr : 32'b0;
    assign data_axi_data = mem_axi_signal[0].we ? mem_axi_signal[1].data : mem_axi_signal[1].we ? mem_axi_signal[1].data : 32'b0;

    axi_master u_axi_master (
        .aclk   (aclk),
        .aresetn(aresetn),

        // <-> ICache
        .inst_cpu_addr_i(axi_addr),
        .inst_cpu_ce_i(axi_addr != 0),  // FIXME: ce should not be used as valid?
        .inst_cpu_data_i(0),
        .inst_cpu_we_i(1'b0),
        .inst_cpu_sel_i(4'b1111),
        .inst_stall_i(),  // FIXME: stall & flush
        .inst_flush_i(backend_flush), // FIXME: use ctrl module instead
        .inst_cpu_data_o(axi_data),
        .inst_stallreq(axi_busy),
        .inst_id(4'b0000),  // Read Instruction only, TODO: move this from AXI to cache

        // <-> MEM Stage
        .data_cpu_addr_i(data_axi_addr),
        .data_cpu_ce_i(data_axi_addr != 0),  // FIXME: ce should not be used as valid?
        .data_cpu_data_i(data_axi_data),
        .data_cpu_we_i(1'b0),  // FIXME: Write enable
        .data_cpu_sel_i(4'b1111),
        .data_stall_i(),
        .data_flush_i(),
        .data_cpu_data_o(axi_mem_data),
        .data_stallreq(data_axi_busy),
        .data_id(4'b0000),

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
        .flush(backend_flush),
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

    // Frontend <-> Backend 
    logic backend_flush;

    // All frontend structures
    frontend u_frontend (
        .clk(clk),
        .rst(rst),

        // <-> ICache
        .icache_read_addr_o(frontend_icache_addr),  // -> ICache
        .icache_stallreq_i(icache_frontend_stallreq),  // <- ICache, I$ cannot accept more addr requests
        .icache_read_valid_i(icache_frontend_valid),  // <- ICache
        .icache_read_addr_i(icache_frontend_addr),  // <- ICache
        .icache_read_data_i(icache_frontend_data),  // <- ICache

        // <-> Backend
        .branch_update_info_i(),              // branch update signals, <- EXE Stage
        .backend_next_pc_i   (next_pc),       // backend PC, <- pc_gen
        .backend_flush_i     (backend_flush), // backend flush, usually come with next_pc

        // <-> Instruction Buffer
        .instr_buffer_stallreq_i(ib_frontend_stallreq),   // instruction buffer is full
        .instr_buffer_o         (frontend_ib_instr_info)  // -> IB
    );

    instr_buffer_info_t ib_backend_instr_info[2];  // IB -> ID
    logic [5:0] stall;

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
                // FIXME: excp info, currently unused
                .excp_i        (),
                .excp_num_i    (),

                // -> Dispatch
                .dispatch_o(id_id_dispatch[i]),

                // Exception broadcast
                .broadcast_excp_o    (),
                .broadcast_excp_num_o(),

                // <-> CSR Registers
                .has_int        (has_int),
                .csr_data_i     (id_csr_data[i]),
                .csr_plv        (csr_plv),
                .csr_read_addr_o(id_csr_read_addr_o[i])
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

    //data relate
    ex_dispatch_struct ex_data_forward[2];
    mem_dispatch_struct mem_data_forward[2];


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

        .stall(),
        .flush(backend_flush),

        // Data forwarding    
        .ex_data_forward(ex_data_forward),
        .mem_data_forward(mem_data_forward),

        // <-> Regfile
        .regfile_reg_read_valid_o(dispatch_regfile_reg_read_valid),
        .regfile_reg_read_addr_o (dispatch_regfile_reg_read_addr),
        .regfile_reg_read_data_i (regfile_dispatch_reg_read_data),

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
    logic [31:0] csr_era_i;
    logic [31:0] wb_csr_era[2];
    logic [8:0] csr_esubcode_i;
    logic [8:0] wb_csr_esubcode[2];
    logic [5:0] csr_ecode_i;
    logic [5:0] wb_csr_ecode[2];
    logic va_error_i;
    logic wb_va_error[2];
    logic [31:0] bad_va_i;
    logic [31:0] wb_bad_va[2];
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

    logic idle_flush;
    logic [`InstAddrBus] idle_pc;
    logic wb_excp_flush[2];
    logic wb_ertn_flush[2];

    assign excp_flush = wb_excp_flush[0] | wb_excp_flush[1];
    assign ertn_flush = wb_ertn_flush[0] | wb_ertn_flush[1];


    logic disable_cache;
    logic [1:0] branch_flag;

    assign backend_flush = excp_flush | ertn_flush | branch_flag[0] | branch_flag[1];

    assign next_pc = branch_flag[0] ? branch_target_address[0] : 
                     branch_flag[1] ? branch_target_address[1] :
                     (excp_flush && !excp_tlbrefill) ? csr_eentry :
                     (excp_flush && excp_tlbrefill) ? csr_tlbrentry :
                     ertn_flush ? csr_era : `ZeroWord;


    ex_mem_struct ex_signal_o[2];
    logic ex_excp_i[2];
    logic [8:0] ex_excp_num_i[2];


    // EXE Stage
    generate
        for (genvar i = 0; i < 2; i++) begin : ex
            ex u_ex (
                .rst(rst),

                .dispatch_i(dispatch_exe[i]),
                .csr_vppn  (),

                .ex_o(ex_signal_o[i]),

                .stallreq(),

                .branch_flag(branch_flag[i]),
                .branch_target_address(branch_target_address[i]),

                .ex_data_forward(ex_data_forward[i]),

                .excp_i(ex_excp_i[i]),
                .excp_num_i(ex_excp_num_i[i]),
                .excp_o(ex_excp_o[i]),
                .excp_num_o(ex_excp_num_o[i])
            );
        end
    endgenerate

    logic ex_excp_o[2];
    logic [9:0] ex_excp_num_o[2];


    logic mem_excp_i[2];
    logic [9:0] mem_excp_num_i[2];
    logic mem_excp_o[2];
    logic [15:0] mem_excp_num_o[2];

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
                .stall(stall[2]),
                .flush(ex_mem_flush[i]),

                .ex_current_inst_address(),
                .excp_i(ex_excp_o[i]),
                .excp_num_i(ex_excp_num_o[i]),

                .mem_current_inst_address(),
                .excp_o(mem_excp_i[i]),
                .excp_num_o(mem_excp_num_i[i])
            );
        end

    endgenerate

    mem_wb_struct mem_signal_o[2];

    logic LLbit_o;
    logic mem_wb_LLbit_we[2];
    logic mem_wb_LLbit_value[2];

    csr_to_mem_struct csr_mem_signal;
    tlb_to_mem_struct tlb_mem_signal;

    assign csr_mem_signal = {csr_pg,csr_da,csr_dmw0,csr_dmw1,csr_plv,csr_datf};
    assign tlb_mem_signal = {data_tlb_found,data_tlb_index,data_tlb_v,data_tlb_d,data_tlb_mat,data_tlb_plv};

    generate
        for (genvar i = 0; i < 2; i++) begin : mem
            mem u_mem (
                .rst(rst),

                .signal_i(mem_signal_i[i]),

                .signal_o(mem_signal_o[i]),

                .signal_axi_o(mem_axi_signal[i]),

                .mem_data_i(axi_mem_data),

                .LLbit_i(LLbit_o),
                .wb_LLbit_we_i(wb_LLbit_we_i[i]),
                .wb_LLbit_value_i(wb_LLbit_value_i[i]),
                .LLbit_we_o(mem_wb_LLbit_we[i]),
                .LLbit_value_o(mem_wb_LLbit_value[i]),

                .excp_i(mem_excp_i[i]),
                .excp_num_i(mem_excp_num_i[i]),
                .excp_o(mem_excp_o[i]),
                .excp_num_o(mem_excp_num_o[i]),

                .csr_mem_signal(csr_mem_signal),
                .disable_cache(1'b0),

                .mem_data_forward(mem_data_forward[i]),

                .data_addr_trans_en(mem_data_addr_trans_en[i]),
                .dmw0_en(mem_data_dmw0_en[i]),
                .dmw1_en(mem_data_dmw1_en[i]),
                .cacop_op_mode_di(cacop_op_mode_di),

                .tlb_mem_signal(tlb_mem_signal)
            );
        end

    endgenerate


    logic [18:0] wb_excp_tlb_vppn[2];

    logic wb_excp_tlbrefill[2];
    wb_reg wb_reg_signal[2];

    logic wb_LLbit_we_i[2];
    logic wb_LLbit_value_i[2];
    logic [46:0] wb_csr_signal[2];

    // Difftest Related
    logic [1:0] debug_commit_valid;
    logic [1:0][`InstBus] debug_commit_instr;
    logic [1:0][`InstAddrBus] debug_commit_pc;

    generate
        for (genvar i = 0; i < 2; i++) begin : mem_wb
            mem_wb u_mem_wb (
                .clk  (clk),
                .rst  (rst),
                .stall(stall[3]),

                .mem_signal_o(mem_signal_o[i]),

                .mem_LLbit_we(mem_wb_LLbit_we[i]),
                .mem_LLbit_value(mem_wb_LLbit_value[i]),

                .flush(flush),

                .wb_reg_o(wb_reg_signal[i]),

                .wb_csr_signal_o(wb_csr_signal[i]),

                .debug_commit_pc(debug_commit_pc[i]),
                .debug_commit_valid(debug_commit_valid[i]),
                .debug_commit_instr(debug_commit_instr[i]),

                .wb_LLbit_we(wb_LLbit_we_i[i]),
                .wb_LLbit_value(wb_LLbit_value_i[i]),

                .excp_i  (mem_excp_o[i]),
                .excp_num(mem_excp_num_o[i]),

                //to csr
                .csr_era(wb_csr_era[i]),
                .csr_esubcode(wb_csr_esubcode[i]),
                .csr_ecode(wb_csr_ecode[i]),
                .excp_flush(wb_excp_flush[i]),
                .ertn_flush(wb_ertn_flush[i]),
                .va_error(wb_va_error[i]),
                .bad_va(wb_bad_va[i]),
                .excp_tlbrefill(),
                .excp_tlb(),
                .excp_tlb_vppn()
            );
        end
    endgenerate


    regfile #(
        .READ_PORTS(4)  // 2 for each ID, 2 ID in total, TODO: remove magic number
    ) u_regfile (
        .clk(clk),
        .rst(rst),

        .we_1   (wb_reg_signal[0].we),
        .pc_i_1 (wb_reg_signal[0].pc),
        .waddr_1(wb_reg_signal[0].waddr),
        .wdata_1(wb_reg_signal[0].wdata),
        .we_2   (wb_reg_signal[1].we),
        .pc_i_2 (wb_reg_signal[1].pc),
        .waddr_2(wb_reg_signal[1].waddr),
        .wdata_2(wb_reg_signal[1].wdata),

        // Read signals
        // Registers are read in dispatch stage
        .read_valid_i(dispatch_regfile_reg_read_valid),
        .read_addr_i (dispatch_regfile_reg_read_addr),
        .read_data_o (regfile_dispatch_reg_read_data)
    );

    ctrl u_ctrl(
    	.ex_branch_flag_i (branch_flag),
        .stallreg_from_dispatch(stallreg_from_dispatch),

        .stall(),
        .ex_mem_flush_o   (ex_mem_flush)
    );
    


    LLbit_reg u_LLbit_reg (
        .clk(clk),
        .rst(rst),
        .flush(1'b0),
        .LLbit_i_1(wb_LLbit_value_i[0]),
        .LLbit_i_2(wb_LLbit_value_i[1]),
        .we(wb_LLbit_we_i[0] | wb_LLbit_we_i[1]),
        .LLbit_o(LLbit_o)
    );


    //目前没有进行冲突处理，是假设不会同时出现两条异常同时发生
    assign csr_era_i = wb_csr_era[0] | wb_csr_era[1];
    assign csr_ecode_i = wb_csr_ecode[0] | wb_csr_ecode[1];
    assign csr_esubcode_i = wb_csr_esubcode[0] | wb_csr_esubcode[1];
    assign excp_flush = wb_excp_flush[0] | wb_excp_flush[1];
    assign ertn_flush = wb_ertn_flush[0] | wb_ertn_flush[1];
    assign va_error_i = wb_va_error[0] | wb_va_error[1];
    assign bad_va_i = wb_bad_va[0] | wb_bad_va[1];
    assign excp_tlbrefill = wb_excp_tlbrefill[0] | wb_excp_tlbrefill[1];
    assign excp_tlb_vppn = wb_excp_tlb_vppn[0] | wb_excp_tlb_vppn[1];

    logic [13:0] id_csr_read_addr_o[2];
    logic [`RegBus] id_csr_data[2];

    cs_reg u_cs_reg (
        .clk(clk),
        .rst(rst),
        .excp_flush(excp_flush),
        .ertn_flush(ertn_flush),
        .write_signal_1(wb_csr_signal[0]),
        .write_signal_2(wb_csr_signal[1]),
        .raddr_1(id_csr_read_addr_o[0]),
        .raddr_2(id_csr_read_addr_o[1]),
        .rdata_1(id_csr_data[0]),
        .rdata_2(id_csr_data[1]),
        .era_i(csr_era_i),
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
        .asid_in(tlbr_asid)
    );


    assign data_addr_trans_en = mem_data_addr_trans_en[0] | mem_data_addr_trans_en[1];
    assign data_dmw0_en = mem_data_dmw0_en[0] | mem_data_dmw0_en[1];
    assign data_dmw1_en = mem_data_dmw1_en[0] | mem_data_dmw1_en[1];
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

    // Difftest Delay signals
    logic [1:0] debug_commit_valid_delay1;
    logic [1:0][`InstBus] debug_commit_instr_delay1;
    logic [1:0][`InstAddrBus] debug_commit_pc_delay1;
    always_ff @(posedge clk) begin
        debug_commit_instr_delay1 <= debug_commit_instr;
        debug_commit_pc_delay1 <= debug_commit_pc;
        debug_commit_valid_delay1 <= debug_commit_valid;
    end

    always_ff @(posedge clk) begin
        debug0_wb_pc <= wb_reg_signal[0].pc; 
        debug0_wb_rf_wen <= {3'b0,wb_reg_signal[0].we};
        debug0_wb_rf_wdata <= wb_reg_signal[0].wdata;
        debug0_wb_rf_wnum <= wb_reg_signal[0].waddr;
        `ifdef CPU_2debug_commit
        debug1_wb_pc <= wb_reg_signal[1].pc;
        debug1_wb_rf_wen <= {3'b0, wb_reg_signal[1].we};
        debug1_wb_rf_wdata <= wb_reg_signal[1].wdata;
        debug1_wb_rf_wnum <= wb_reg_signal[1].waddr;
        `endif
    end
    // difftest dpi-c
`ifdef SIMU  // simu is defined in chiplab run_func/makefile
    DifftestInstrCommit difftest_instr_commit_0 (  // todo: not finished yet, blank signal is needed
        .clock         (aclk),
        .coreid        (0),                             // only one core, so always 0
        .index         (0),                             // commit channel index
        .valid         (debug_commit_valid_delay1[0]),  // 1 means valid
        .pc            (debug_commit_pc_delay1[0]),
        .instr         (debug_commit_instr_delay1[0]),
        .skip          (0),                             // not sure meaning, but keep 0 for now
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
    DifftestInstrCommit difftest_instr_commit_1 (  // todo: not finished yet, blank signal is needed
        .clock         (aclk),
        .coreid        (0),                             // only one core, so always 0
        .index         (1),                             // commit channel index
        .valid         (debug_commit_valid_delay1[1]),  // 1 means valid
        .pc            (debug_commit_pc_delay1[1]),
        .instr         (debug_commit_instr_delay1[1]),
        .skip          (0),                             // not sure meaning, but keep 0 for now
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

    DifftestStoreEvent DifftestStoreEvent(
        .clock              (aclk),
        .coreid             (0),
        .index              (0),
        .valid              (debug_commit_inst_st_en),
        .storePAddr         (debug_commit_st_paddr),
        .storeVAddr         (debug_commit_st_vaddr),
        .storeData          (debug_commit_st_data)
    );

    DifftestLoadEvent DifftestLoadEvent(
        .clock              (aclk),
        .coreid             (0),
        .index              (0),
        .valid              (debug_commit_inst_ld_en),
        .paddr              (debug_commit_ld_paddr),
        .vaddr              (debug_commit_ld_vaddr)
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
