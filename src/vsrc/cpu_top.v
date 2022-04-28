`include "defines.v"
`include "pc_reg.v"
`include "if_buffer.v"
`include "regfile.v"
`include "pipeline/1_fetch/if_id.v"
`include "pipeline/2_decode/id.v"
`include "pipeline/2_decode/id_ex.v"
`include "pipeline/3_execution/ex.v"
`include "pipeline/3_execution/ex_mem.v"
`include "pipeline/4_mem/mem.v"
`include "pipeline/4_mem/mem_wb.v"
`include "pipeline/3_execution/div.v"
`include "../AXI/axi_defines.v"
module cpu_top (
    input wire clk,
    input wire rst,
    // input wire[`RegBus] dram_data_i,
    // input wire[`RegBus] ram_rdata_i,

    // output wire[`RegBus] ram_raddr_o,
    // output wire[`RegBus] ram_wdata_o,
    // output wire[`RegBus] ram_waddr_o,
    // output wire ram_wen_o,
    // output wire ram_en_o,

    // output wire[`RegBus] dram_addr_o,
    // output wire[`RegBus] dram_data_o,
    // output wire dram_we_o,
    // output wire[3:0] dram_sel_o,
    // output wire dram_ce_o,

    output wire[`RegBus] debug_commit_pc,
    output wire debug_commit_valid,
    output wire[`InstBus] debug_commit_instr,
    output wire debug_commit_wreg,
    output wire[`RegAddrBus] debug_commit_reg_waddr,
    output wire[`RegBus] debug_commit_reg_wdata,
    output wire[1023:0] debug_reg,
    output wire Instram_branch_flag,
    output wire [6:0]ram_flush, //both ram use
    output wire [6:0]ram_stall, //both ram use

    //AXI interface
    
    //IRAM
    //ar
    output wire [`ID]i_arid,  //arbitration
    output wire [`ADDR]i_araddr,
    output wire [`Len]i_arlen,
    output wire [`Size]i_arsize,
    output wire [`Burst]i_arburst,
    output wire [`Lock]i_arlock,
    output wire [`Cache]i_arcache,
    output wire [`Prot]i_arprot,
    output wire i_arvalid,
    input wire i_arready,

    //r
    input wire [`ID]i_rid,
    input wire [`Data]i_rdata,
    input wire [`Resp]i_rresp,
    input wire i_rlast,//the last read data
    input wire i_rvalid,
    output wire i_rready,

    //aw
    output wire [`ID]i_awid,
    output wire [`ADDR]i_awaddr,
    output wire [`Len]i_awlen,
    output wire [`Size]i_awsize,
    output wire [`Burst]i_awburst,
    output wire [`Lock]i_awlock,
    output wire [`Cache]i_awcache,
    output wire [`Prot]i_awprot,
    output wire i_awvalid,
    input wire i_awready,

    //w
    output wire [`ID]i_wid,
    output wire [`Data]i_wdata,
    output wire [3:0]i_wstrb,//字节选通位和sel差不多
    output wire  i_wlast,
    output wire i_wvalid,
    input wire i_wready,

    //b
    input wire [`ID]i_bid,
    input wire [`Resp]i_bresp,
    input wire i_bvalid,
    output wire i_bready,

    //DRAM
    //ar
    output wire [`ID]d_arid,  //arbitration
    output wire [`ADDR]d_araddr,
    output wire [`Len]d_arlen,
    output wire [`Size]d_arsize,
    output wire [`Burst]d_arburst,
    output wire [`Lock]d_arlock,
    output wire [`Cache]d_arcache,
    output wire [`Prot]d_arprot,
    output wire d_arvalid,
    input wire d_arready,

    //r
    input wire [`ID]d_rid,
    input wire [`Data]d_rdata,
    input wire [`Resp]d_rresp,
    input wire d_rlast,//the last read data
    input wire d_rvalid,
    output wire d_rready,

    //aw
    output wire [`ID]d_awid,
    output wire [`ADDR]d_awaddr,
    output wire [`Len]d_awlen,
    output wire [`Size]d_awsize,
    output wire [`Burst]d_awburst,
    output wire [`Lock]d_awlock,
    output wire [`Cache]d_awcache,
    output wire [`Prot]d_awprot,
    output wire d_awvalid,
    input wire d_awready,

    //w
    output wire [`ID]d_wid,
    output wire [`Data]d_wdata,
    output wire [3:0]d_wstrb,//字节选通位和sel差不多
    output wire  d_wlast,
    output wire d_wvalid,
    input wire d_wready,

    //b
    input wire [`ID]d_bid,
    input wire [`Resp]d_bresp,
    input wire d_bvalid,
    output wire d_bready
  );

  wire[`InstAddrBus] pc;
  wire chip_enable;

  assign ram_en_o = chip_enable;
  assign ram_raddr_o = pc;

  wire branch_flag;
  assign Instram_branch_flag=branch_flag;
  wire[`RegBus] branch_target_address;
  wire[`RegBus] link_addr;
  wire flush;
  wire[`RegBus] new_pc;
  wire[6:0] stall; // [pc_reg,if_buffer_1, if_id, id_ex, ex_mem, mem_wb, ctrl]

  pc_reg u_pc_reg(
           .clk(clk),
           .rst(rst),
           .pc(pc),
           .ce(chip_enable),
           .branch_flag_i(branch_flag),
           .branch_target_address(branch_target_address),
           .flush(flush),
           .new_pc(new_pc),
           .stall(stall[0])
         );

  //AXI Master interface for fetch instruction channel
  wire aresetn=~rst;
  wire axi_stall=&stall;
  wire stallreq_from_if;
  wire [31:0]inst_data_from_axi;
  axi_Master inst_interface(
            .aclk(clk),
            .aresetn(aresetn), //low is valid
    
    //CPU
            .cpu_addr_i(pc),
            .cpu_ce_i(chip_enable),
            .cpu_data_i(0),
            .cpu_we_i(0) ,
            .cpu_sel_i(4'b1111), 
            .stall_i(axi_stall),
            .flush_i(0),
            .cpu_data_o(inst_data_from_axi),
            .stallreq(stallreq_from_if),
            .id(4'b0000),//决定是读数据还是取指令

    //ar
            .s_arid(i_arid),  //arbitration
            .s_araddr(i_araddr),
            .s_arlen(i_arlen),
            .s_arsize(i_arsize),
            .s_arburst(i_arburst),
            .s_arlock(i_arlock),
            .s_arcache(i_arcache),
            .s_arprot(i_arprot),
            .s_arvalid(i_arvalid),
            .s_arready(i_arready),

    //r
            .s_rid(i_rid),
            .s_rdata(i_rdata),
            .s_rresp(i_rresp),
            .s_rlast(i_rlast),//the last read data
            .s_rvalid(i_rvalid),
            .s_rready(i_rready),

    //aw
            .s_awid(i_awid),
            .s_awaddr(i_awaddr),
            .s_awlen(i_awlen),
            .s_awsize(i_awsize),
            .s_awburst(i_awburst),
            .s_awlock(i_awlock),
            .s_awcache(i_awcache),
            .s_awprot(i_awprot),
            .s_awvalid(i_awvalid),
            .s_awready(i_awready),

    //w
            .s_wid(i_wid),
            .s_wdata(i_wdata),
            .s_wstrb(i_wstrb),//字节选通位和sel差不多
            .s_wlast(i_wlast),
            .s_wvalid(i_wvalid),
            .s_wready(i_wready),

    //b
            .s_bid(i_bid),
            .s_bresp(i_bresp),
            .s_bvalid(i_bvalid),
            .s_bready(i_bready)

  );

  wire [`InstAddrBus]pc2;
  wire if_inst_valid;
  if_buffer if_buffer_1(
              .clk(clk),
              .rst(rst),
              .pc_i(pc),
              .branch_flag_i(branch_flag),
              .pc_valid(if_inst_valid),
              .pc_o(pc2),
              .flush(flush),
              .stall(stall[1])
            );


  wire[`InstAddrBus] id_pc;
  wire[`InstBus] id_inst;
  //  wire if_id_instr_invalid;
  if_id u_if_id(
          .clk(clk),
          .rst(rst),
          .if_pc_i(pc2),
          .if_inst_i(inst_data_from_axi),
          .id_pc_o(id_pc),
          .id_inst_o(id_inst),
          .if_inst_valid(if_inst_valid),
          .branch_flag_i(branch_flag),
          .flush(flush),
          .stall(stall[2])
        );

  wire[`AluOpBus] id_aluop;
  wire[`AluSelBus] id_alusel;
  wire[`RegBus] id_reg1;
  wire[`RegBus] id_reg2;
  wire[`RegAddrBus] id_reg_waddr;
  wire id_wreg;
  wire id_inst_valid;
  wire[`InstAddrBus] id_inst_pc;
  wire[`RegBus] id_inst_o;

  wire reg1_read;
  wire reg2_read;
  wire[`RegAddrBus] reg1_addr;
  wire[`RegAddrBus] reg2_addr;
  wire[`RegBus] reg1_data;
  wire[`RegBus] reg2_data;

  wire ex_wreg_o;
  wire[`RegAddrBus] ex_reg_waddr_o;
  wire[`RegBus] ex_reg_wdata;
  wire[`AluOpBus] ex_aluop_o;

  wire mem_wreg_o;
  wire[`RegAddrBus] mem_reg_waddr_o;
  wire[`RegBus] mem_reg_wdata_o;

  wire stallreq_from_id;
  wire stallreq_from_ex;

  wire[1:0] id_excepttype_o;
  wire[`RegBus] id_current_inst_address_o;


  id u_id(
       .rst(rst),
       .pc_i(id_pc),
       .inst_i(id_inst),

       .reg1_data_i (reg1_data ),
       .reg2_data_i (reg2_data ),

       .ex_wreg_i   (ex_wreg_o ),
       .ex_waddr_i  (ex_reg_waddr_o),
       .ex_wdata_i  (ex_reg_wdata),
       .ex_aluop_i  (ex_aluop_o),

       .mem_wreg_i  (mem_wreg_o),
       .mem_waddr_i (mem_reg_waddr_o),
       .mem_wdata_i (mem_reg_wdata_o),

       .reg1_read_o (reg1_read ),
       .reg2_read_o (reg2_read ),

       .reg1_addr_o (reg1_addr ),
       .reg2_addr_o (reg2_addr ),

       .aluop_o     (id_aluop     ),
       .alusel_o    (id_alusel    ),
       .reg1_o      (id_reg1      ),
       .reg2_o      (id_reg2      ),
       .reg_waddr_o (id_reg_waddr ),
       .wreg_o      (id_wreg     ),
       .inst_valid(id_inst_valid),
       .inst_pc(id_inst_pc),
       .inst_o(id_inst_o),

       .branch_flag_o(branch_flag),
       .branch_target_address_o(branch_target_address),
       .link_addr_o(link_addr),

       .stallreq(stallreq_from_id),

       .excepttype_o(id_excepttype_o),
       .current_inst_address_o(id_current_inst_address_o)
     );

  wire[`AluOpBus] ex_aluop;
  wire[`AluSelBus] ex_alusel;
  wire[`RegBus] ex_reg1;
  wire[`RegBus] ex_reg2;
  wire[`RegAddrBus] ex_reg_waddr_i;
  wire ex_wreg_i;
  wire ex_inst_valid_i;
  wire[`InstAddrBus] ex_inst_pc_i;
  wire[`RegBus] ex_link_address;
  wire[`RegBus] ex_inst_i;
  wire[1:0] ex_excepttype_i;
  wire[`RegBus] ex_current_inst_address_i;

  id_ex id_ex0(
          .clk(clk),
          .rst(rst),
          .stall(stall),

          .id_aluop(id_aluop),
          .id_alusel(id_alusel),
          .id_reg1(id_reg1),
          .id_reg2(id_reg2),
          .id_wd(id_reg_waddr),
          .id_wreg(id_wreg),
          .id_inst_pc(id_inst_pc),
          .id_inst_valid(id_inst_valid),
          .id_link_address(link_addr),
          .id_inst(id_inst_o),
          .flush(flush),
          .id_excepttype(id_excepttype_o),
          .id_current_inst_address(id_current_inst_address_o),

          .ex_aluop(ex_aluop),
          .ex_alusel(ex_alusel),
          .ex_reg1(ex_reg1),
          .ex_reg2(ex_reg2),
          .ex_wd(ex_reg_waddr_i),
          .ex_wreg(ex_wreg_i),
          .ex_inst_pc(ex_inst_pc_i),
          .ex_inst_valid(ex_inst_valid_i),
          .ex_link_address(ex_link_address),
          .ex_inst(ex_inst_i),
          .ex_excepttype(ex_excepttype_i),
          .ex_current_inst_address(ex_current_inst_address_i)

        );


  wire ex_inst_valid_o;
  wire[`InstAddrBus] ex_inst_pc_o;
  wire[`RegBus] ex_addr_o;
  wire[`RegBus] ex_reg2_o;
  wire[1:0] ex_excepttype_o;
  wire[`RegBus] ex_current_inst_address_o;
  wire[`RegBus] dividend;
  wire[`RegBus] divisor;
  wire div_valid1;
  wire div_valid2;
  wire div_signed;
  wire div_start;
  wire ready; //finish flag
  wire[63:0] result;
  wire[31:0] cnt;
  
  ex u_ex(
       .rst(rst),

       .aluop_i(ex_aluop),
       .alusel_i(ex_alusel),
       .reg1_i(ex_reg1),
       .reg2_i(ex_reg2),
       .wd_i(ex_reg_waddr_i),
       .wreg_i(ex_wreg_i),
       .inst_valid_i(ex_inst_valid_i),
       .inst_pc_i(ex_inst_pc_i),
       .inst_i(ex_inst_i),
       .link_addr_i(ex_link_address),
       .excepttype_i(ex_excepttype_i),
       .current_inst_address_i(ex_current_inst_address_i),

       .wd_o(ex_reg_waddr_o),
       .wreg_o(ex_wreg_o),
       .wdata_o(ex_reg_wdata),
       .inst_valid_o(ex_inst_valid_o),
       .inst_pc_o(ex_inst_pc_o),
       .aluop_o(ex_aluop_o),
       .mem_addr_o(ex_addr_o),
       .reg2_o(ex_reg2_o),
       .excepttype_o(ex_excepttype_o),
       .current_inst_address_o(ex_current_inst_address_o),

       
       .dividend(dividend),
       .divisor(divisor),
       .div_start(div_start),
       .div_signed(div_signed),
       .div_valid1(div_valid1),
       .div_valid2(div_valid2),
       
       .div_ready_i(ready),
       .div_result_i(result),
       .cnt(cnt),

       .stallreq(stallreq_from_ex)
     );



  div u_div(
    .clk(clk),
    .rst(rst),
    .dividend(dividend),
    .divisor(divisor),
    .div_start(div_start),
    .valid1(div_valid1),
    .valid2(div_valid2),
    .isSigned(div_signed),

    .ready(ready),
    .result(result),
    .cnt(cnt)
  );


  wire mem_wreg_i;
  wire[`RegAddrBus] mem_reg_waddr_i;
  wire[`RegBus] mem_reg_wdata_i;

  wire mem_inst_valid;
  wire[`InstAddrBus] mem_inst_pc;

  wire[`AluOpBus] mem_aluop_i;
  wire[`RegBus] mem_addr_i;
  wire[`RegBus] mem_reg2_i;
  wire[1:0] mem_excepttype_i;
  wire[`RegBus] mem_current_inst_address_i;

  ex_mem u_ex_mem(
           .clk(clk       ),
           .rst(rst       ),
           .stall(stall),

           .ex_wd     (ex_reg_waddr_o    ),
           .ex_wreg   (ex_wreg_o   ),
           .ex_wdata  (ex_reg_wdata  ),
           .ex_inst_pc(ex_inst_pc_o),
           .ex_inst_valid(ex_inst_valid_o),
           .ex_aluop(ex_aluop_o),
           .ex_mem_addr(ex_addr_o),
           .ex_reg2(ex_reg2_o),
           .flush(flush),
           .ex_excepttype(ex_excepttype_o),
           .ex_current_inst_address(ex_current_inst_address_o),

           .mem_wd(mem_reg_waddr_i    ),
           .mem_wreg(mem_wreg_i  ),
           .mem_wdata(mem_reg_wdata_i ),
           .mem_inst_valid(mem_inst_valid),
           .mem_inst_pc(mem_inst_pc),
           .mem_aluop(mem_aluop_i),
           .mem_mem_addr(mem_addr_i),
           .mem_reg2(mem_reg2_i),
           .mem_excepttype(mem_excepttype_i),
           .mem_current_inst_address(mem_current_inst_address_i)
         );

  wire LLbit_o;
  wire wb_LLbit_we_i;
  wire wb_LLbit_value_i;
  wire mem_LLbit_we_o;
  wire mem_LLbit_value_o;
  wire[1:0] mem_excepttype_o;
  wire[`RegBus] mem_current_inst_address_o;

  wire[`RegBus] dram_addr_o;
  wire[`RegBus] dram_data_o;
  wire dram_we_o;
  wire[3:0] dram_sel_o;
  wire dram_ce_o;
  wire[`RegBus] dram_data_i;
  
  mem u_mem(
        .rst     (rst     ),

        .wd_i    (mem_reg_waddr_i    ),
        .wreg_i  (mem_wreg_i  ),
        .wdata_i (mem_reg_wdata_i),
        .aluop_i(mem_aluop_i),
        .mem_addr_i(mem_addr_i),
        .reg2_i(mem_reg2_i),

        .mem_data_i(dram_data_i),

        .LLbit_i(LLbit_o),
        .wb_LLbit_we_i(wb_LLbit_we_i),
        .wb_LLbit_value_i(wb_LLbit_value_i),

        .excepttype_i(mem_excepttype_i),
        .current_inst_address_i(mem_current_inst_address_i),


        .wd_o    (mem_reg_waddr_o),
        .wreg_o  (mem_wreg_o ),
        .wdata_o (mem_reg_wdata_o ),

        .mem_addr_o(dram_addr_o),
        .mem_we_o(dram_we_o),
        .mem_sel_o(dram_sel_o),
        .mem_data_o(dram_data_o),
        .mem_ce_o(dram_ce_o),

        .LLbit_we_o(mem_LLbit_we_o),
        .LLbit_value_o(mem_LLbit_value_o),

        .excepttype_o(mem_excepttype_o),
        .current_inst_address_o(mem_current_inst_address_o)

      );

    
  wire stallreq_from_mem;

  //AXI Master interface for data ram
  axi_Master data_interface(
        .aclk(clk),
        .aresetn(aresetn), //low is valid

    //CPU
        .cpu_addr_i(dram_addr_o),
        .cpu_ce_i(dram_ce_o),
        .cpu_data_i(dram_data_o),
        .cpu_we_i(dram_we_o) ,
        .cpu_sel_i(dram_sel_o), 
        .stall_i(axi_stall),
        .flush_i(0),
        .cpu_data_o(dram_data_i),
        .stallreq(stallreq_from_mem),
        .id(4'b0001),//决定是读数据还是取指令

    //ar
        .s_arid(d_arid),  //arbitration
        .s_araddr(d_araddr),
        .s_arlen(d_arlen),
        .s_arsize(d_arsize),
        .s_arburst(d_arburst),
        .s_arlock(d_arlock),
        .s_arcache(d_arcache),
        .s_arprot(d_arprot),
        .s_arvalid(d_arvalid),
        .s_arready(d_arready),

    //r
        .s_rid(d_rid),
        .s_rdata(d_rdata),
        .s_rresp(d_rresp),
        .s_rlast(d_rlast),//the last read data
        .s_rvalid(d_rvalid),
        .s_rready(d_rready),

    //aw
        .s_awid(d_awid),
        .s_awaddr(d_awaddr),
        .s_awlen(d_awlen),
        .s_awsize(d_awsize),
        .s_awburst(d_awburst),
        .s_awlock(d_awlock),
        .s_awcache(d_awcache),
        .s_awprot(d_awprot),
        .s_awvalid(d_awvalid),
        .s_awready(d_awready),

    //w
        .s_wid(d_wid),
        .s_wdata(d_wdata),
        .s_wstrb(d_wstrb),//字节选通位和sel差不多
        .s_wlast(d_wlast),
        .s_wvalid(d_wvalid),
        .s_wready(d_wready),

    //b
        .s_bid(d_bid),
        .s_bresp(d_bresp),
        .s_bvalid(d_bvalid),
        .s_bready(d_bready)

  );


  wire wb_wreg;
  wire[`RegAddrBus] wb_reg_waddr;
  wire[`RegBus] wb_reg_wdata;

  assign debug_commit_wreg = wb_wreg;
  assign debug_commit_reg_waddr = wb_reg_waddr;
  assign debug_commit_reg_wdata = wb_reg_wdata;



  mem_wb mem_wb0(
           .clk(clk),
           .rst(rst),
           .stall(stall),

           .mem_wd(mem_reg_waddr_o),
           .mem_wreg(mem_wreg_o),
           .mem_wdata(mem_reg_wdata_o),
           .mem_inst_pc        (mem_inst_pc        ),
           .mem_instr          (          ),
           .mem_inst_valid     (mem_inst_valid     ),

           .mem_LLbit_we(mem_LLbit_we_o),
           .mem_LLbit_value(mem_LLbit_value_o),

           .flush(flush),

           .wb_wd(wb_reg_waddr),
           .wb_wreg(wb_wreg),
           .wb_wdata(wb_reg_wdata),

           .wb_LLbit_we(wb_LLbit_we_i),
           .wb_LLbit_value(wb_LLbit_value_i),

           .debug_commit_pc    (debug_commit_pc    ),
           .debug_commit_valid (debug_commit_valid ),
           .debug_commit_instr (debug_commit_instr )
         );

  regfile u_regfile(
            .clk(clk       ),
            .rst(rst       ),

            .we        (wb_wreg),
            .waddr     (wb_reg_waddr),
            .wdata     (wb_reg_wdata),

            .re1       (reg1_read),
            .raddr1    (reg1_addr),
            .rdata1    (reg1_data),
            .re2       (reg2_read),
            .raddr2    (reg2_addr),
            .rdata2    (reg2_data),
            .debug_reg (debug_reg)
          );

  ctrl u_ctrl(
         .clk                   (clk                   ),
         .rst                   (rst                   ),
         .stall(stall),
         .stallreq_from_if(stallreq_from_if),
         .stallreq_from_id(stallreq_from_id),
         .stallreq_from_ex(stallreq_from_ex),
         .stallreq_from_mem(stallreq_from_mem),
         .excepttype_i(mem_excepttype_o),
         .new_pc(new_pc),
         .flush(flush)
       );

  LLbit_reg u_LLbit_reg(
              .clk(clk),
              .rst(rst),
              .flush(1'b0),
              .LLbit_i(wb_LLbit_value_i),
              .we(wb_LLbit_we_i),
              .LLbit_o(LLbit_o)
            );

  assign ram_flush=flush;
  assign ram_stall=stall;
endmodule
