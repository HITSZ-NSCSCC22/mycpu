`include "../defines.v"
`include "1_fetch/if_id.v"
`include "2_decode/id.v"
`include "2_decode/id_ex.v"
`include "3_execution/ex.v"
`include "3_execution/ex_mem.v"
`include "4_mem/mem.v"
`include "4_mem/mem_wb.v"

module cpu_top (
    input wire clk,
    input wire rst,
    input wire[`RegBus] dram_data_i,
    input wire[`RegBus] ram_rdata_i,

    output wire[`RegBus] ram_raddr_o,
    output wire[`RegBus] ram_wdata_o,
    output wire[`RegBus] ram_waddr_o,
    output wire ram_wen_o,
    output wire ram_en_o,

    output wire[`RegBus] dram_addr_o,
    output wire[`RegBus] dram_data_o,
    output wire dram_we_o,
    output wire[3:0] dram_sel_o,
    output wire dram_ce_o,

    output wire[`RegBus] debug_commit_pc,
    output wire debug_commit_valid,
    output wire[`InstBus] debug_commit_instr,
    output wire debug_commit_wreg,
    output wire[`RegAddrBus] debug_commit_reg_waddr,
    output wire[`RegBus] debug_commit_reg_wdata,
    output wire[1023:0] debug_reg,
    output wire Instram_branch_flag
  );

  wire[`InstAddrBus] pc;
  wire chip_enable;

  assign ram_en_o = chip_enable;
  assign ram_raddr_o = pc;

  wire branch_flag;
  assign Instram_branch_flag=branch_flag;
  wire[`RegBus] branch_target_address;
  wire[`RegBus] link_addr;

  wire [`InstAddrBus]pc2;
  if_buffer if_buffer_1(
              .clk(clk),
              .rst(rst),
              .pc_i(pc),
              .branch_flag_i(branch_flag),
              .pc_valid(if_inst_valid),
              .pc_o(pc2)
            );


  wire[`InstAddrBus] id_pc;
  wire[`InstBus] id_inst;
  wire if_inst_valid;

  //  wire if_id_instr_invalid;
  if_id u_if_id(
          .clk(clk),
          .rst(rst),
          .if_pc_i(pc2),
          .if_inst_i(ram_rdata_i),
          .id_pc_o(id_pc),
          .id_inst_o(id_inst),
          .if_inst_valid(if_inst_valid),
          .branch_flag_i(branch_flag)
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

       .stallreq(stallreq_from_id)
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

  id_ex id_ex0(
          .clk(clk),
          .rst(rst),

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

          .ex_aluop(ex_aluop),
          .ex_alusel(ex_alusel),
          .ex_reg1(ex_reg1),
          .ex_reg2(ex_reg2),
          .ex_wd(ex_reg_waddr_i),
          .ex_wreg(ex_wreg_i),
          .ex_inst_pc(ex_inst_pc_i),
          .ex_inst_valid(ex_inst_valid_i),
          .ex_link_address(ex_link_address),
          .ex_inst(ex_inst_i)
        );


  wire ex_inst_valid_o;
  wire[`InstAddrBus] ex_inst_pc_o;
  wire[`RegBus] ex_addr_o;
  wire[`RegBus] ex_reg2_o;

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

       .wd_o(ex_reg_waddr_o),
       .wreg_o(ex_wreg_o),
       .wdata_o(ex_reg_wdata),
       .inst_valid_o(ex_inst_valid_o),
       .inst_pc_o(ex_inst_pc_o),
       .aluop_o(ex_aluop_o),
       .mem_addr_o(ex_addr_o),
       .reg2_o(ex_reg2_o)
     );


  wire mem_wreg_i;
  wire[`RegAddrBus] mem_reg_waddr_i;
  wire[`RegBus] mem_reg_wdata_i;

  wire mem_inst_valid;
  wire[`InstAddrBus] mem_inst_pc;

  wire[`AluOpBus] mem_aluop_i;
  wire[`RegBus] mem_addr_i;
  wire[`RegBus] mem_reg2_i;

  ex_mem u_ex_mem(
           .clk(clk       ),
           .rst(rst       ),

           .ex_wd     (ex_reg_waddr_o    ),
           .ex_wreg   (ex_wreg_o   ),
           .ex_wdata  (ex_reg_wdata  ),
           .ex_inst_pc(ex_inst_pc_o),
           .ex_inst_valid(ex_inst_valid_o),
           .ex_aluop(ex_aluop_o),
           .ex_mem_addr(ex_addr_o),
           .ex_reg2(ex_reg2_o),

           .mem_wd(mem_reg_waddr_i    ),
           .mem_wreg(mem_wreg_i  ),
           .mem_wdata(mem_reg_wdata_i ),
           .mem_inst_valid(mem_inst_valid),
           .mem_inst_pc(mem_inst_pc),
           .mem_aluop(mem_aluop_i),
           .mem_mem_addr(mem_addr_i),
           .mem_reg2(mem_reg2_i)
         );

  wire LLbit_o;
  wire wb_LLbit_we_i;
  wire wb_LLbit_value_i;
  wire mem_LLbit_we_o;
  wire mem_LLbit_value_o;

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


        .wd_o    (mem_reg_waddr_o),
        .wreg_o  (mem_wreg_o ),
        .wdata_o (mem_reg_wdata_o ),

        .mem_addr_o(dram_addr_o),
        .mem_we_o(dram_we_o),
        .mem_sel_o(dram_sel_o),
        .mem_data_o(dram_data_o),
        .mem_ce_o(dram_ce_o),

        .LLbit_we_o(mem_LLbit_we_o),
        .LLbit_value_o(mem_LLbit_value_o)

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

           .mem_wd(mem_reg_waddr_o),
           .mem_wreg(mem_wreg_o),
           .mem_wdata(mem_reg_wdata_o),
           .mem_inst_pc        (mem_inst_pc        ),
           .mem_instr          (          ),
           .mem_inst_valid     (mem_inst_valid     ),

           .mem_LLbit_we(mem_LLbit_we_o),
           .mem_LLbit_value(mem_LLbit_value_o),

           .wb_wd(wb_reg_waddr),
           .wb_wreg(wb_wreg),
           .wb_wdata(wb_reg_wdata),

           .wb_LLbit_we(wb_LLbit_we_i),
           .wb_LLbit_value(wb_LLbit_value_i),

           .debug_commit_pc    (debug_commit_pc    ),
           .debug_commit_valid (debug_commit_valid ),
           .debug_commit_instr (debug_commit_instr )
         );

  

endmodule