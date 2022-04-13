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

module cpu_top (
    input wire clk,
    input wire rst,

    input wire[`RegBus] dram_data_i_1,
    input wire[`RegBus] dram_data_i_2,
    input wire[`RegBus] ram_rdata_i_1,
    input wire[`RegBus] ram_rdata_i_2,

    output wire[`RegBus] ram_raddr_o_1,
    output wire[`RegBus] ram_raddr_o_2,
    output wire[`RegBus] ram_wdata_o,
    output wire[`RegBus] ram_waddr_o,
    output wire ram_wen_o,
    output wire ram_en_o,

    output wire[`RegBus] dram_addr_o_1,
    output wire[`RegBus] dram_data_o_1,
    output wire dram_we_o_1,
    output wire[3:0] dram_sel_o_1,
    output wire dram_ce_o_1,
    output wire[`InstAddrBus] dram_pc_o_1,

    output wire[`RegBus] dram_addr_o_2,
    output wire[`RegBus] dram_data_o_2,
    output wire dram_we_o_2,
    output wire[3:0] dram_sel_o_2,
    output wire dram_ce_o_2,
    output wire[`InstAddrBus] dram_pc_o_2,

    output wire[`RegBus] debug_commit_pc_1,
    output wire debug_commit_valid_1,
    output wire[`InstBus] debug_commit_instr_1,
    output wire debug_commit_wreg_1,
    output wire[`RegAddrBus] debug_commit_reg_waddr_1,
    output wire[`RegBus] debug_commit_reg_wdata_1,
    output wire[`RegBus] debug_commit_pc_2,
    output wire debug_commit_valid_2,
    output wire[`InstBus] debug_commit_instr_2,
    output wire debug_commit_wreg_2,
    output wire[`RegAddrBus] debug_commit_reg_waddr_2,
    output wire[`RegBus] debug_commit_reg_wdata_2,
    output wire[1023:0] debug_reg,
    output wire Instram_branch_flag
  );

  wire[`InstAddrBus] pc_1;
  wire[`InstAddrBus] pc_2;
  wire chip_enable;

  wire [`InstAddrBus]pc_buffer_1;
  wire [`InstAddrBus]pc_buffer_2;

  assign ram_en_o = chip_enable;
  assign ram_raddr_o_1 = pc_buffer_1;
  assign ram_raddr_o_2 = pc_buffer_2;

  wire branch_flag;
  assign Instram_branch_flag=branch_flag;
  wire[`RegBus] branch_target_address;
  wire[`RegBus] link_addr;
  wire flush;
  wire[`RegBus] new_pc;
  wire[6:0] stall1; // [pc_reg,if_buffer_1, if_id, id_ex, ex_mem, mem_wb, ctrl]
  wire[6:0] stall2;

  pc_reg u_pc_reg(
           .clk(clk),
           .rst(rst),
           .pc_1(pc_1),
           .pc_2(pc_2),
           .ce(chip_enable),
           .branch_flag_i(branch_flag),
           .branch_target_address(branch_target_address),
           .flush(flush),
           .new_pc(new_pc),
           .stall1(stall1[0]),
           .stall2(stall2[0])
         );

  wire if_inst_valid_1;
  wire if_inst_valid_2;

  if_buffer if_buffer_1(
              .clk(clk),
              .rst(rst),
              .pc_i(pc_1),
              .branch_flag_i(branch_flag),
              .pc_valid(if_inst_valid_1),
              .pc_o(pc_buffer_1),
              .flush(flush),
              .stall(stall1[1])
            );

  if_buffer if_buffer_2(
              .clk(clk),
              .rst(rst),
              .pc_i(pc_2),
              .branch_flag_i(branch_flag),
              .pc_valid(if_inst_valid_2),
              .pc_o(pc_buffer_2),
              .flush(flush),
              .stall(stall2[1])
            );


  wire[`InstAddrBus] id_pc_1;
  wire[`InstBus] id_inst_1;
  wire[`InstAddrBus] id_pc_2;
  wire[`InstBus] id_inst_2;

  //  wire if_id_instr_invalid;
  if_id u_if_id_1(
          .clk(clk),
          .rst(rst),
          .if_pc_i(pc_buffer_1),
          .if_inst_i(ram_rdata_i_1),
          .id_pc_o(id_pc_1),
          .id_inst_o(id_inst_1),
          .if_inst_valid(if_inst_valid_1),
          .branch_flag_i(branch_flag),
          .flush(flush),
          .stall(stall1[2])
        );
    
  if_id u_if_id_2(
          .clk(clk),
          .rst(rst),
          .if_pc_i(pc_buffer_2),
          .if_inst_i(ram_rdata_i_2),
          .id_pc_o(id_pc_2),
          .id_inst_o(id_inst_2),
          .if_inst_valid(if_inst_valid_2),
          .branch_flag_i(branch_flag),
          .flush(flush),
          .stall(stall2[2])
        );

  wire[`AluOpBus] id_aluop_1;
  wire[`AluSelBus] id_alusel_1;
  wire[`RegBus] id_reg1_1;
  wire[`RegBus] id_reg2_1;
  wire[`RegAddrBus] id_reg_waddr_1;
  wire id_wreg_1;
  wire id_inst_valid_1;
  wire[`InstAddrBus] id_inst_pc_1;
  wire[`RegBus] id_inst_o_1;

  wire reg1_read_1;
  wire reg2_read_1;
  wire[`RegAddrBus] reg1_addr_1;
  wire[`RegAddrBus] reg2_addr_1;
  wire[`RegBus] reg1_data_1;
  wire[`RegBus] reg2_data_1;

  wire ex_wreg_o_1;
  wire[`RegAddrBus] ex_reg_waddr_o_1;
  wire[`RegBus] ex_reg_wdata_1;
  wire[`AluOpBus] ex_aluop_o_1;

  wire mem_wreg_o_1;
  wire[`RegAddrBus] mem_reg_waddr_o_1;
  wire[`RegBus] mem_reg_wdata_o_1;

  wire stallreq_from_id_1;
  wire stallreq_from_ex_1;

  wire[1:0] id_excepttype_o_1;
  wire[`RegBus] id_current_inst_address_o_1;

  wire ex_wreg_o_2;
  wire[`RegAddrBus] ex_reg_waddr_o_2;
  wire[`RegBus] ex_reg_wdata_2;
  wire[`AluOpBus] ex_aluop_o_2;

  wire mem_wreg_o_2;
  wire[`RegAddrBus] mem_reg_waddr_o_2;
  wire[`RegBus] mem_reg_wdata_o_2;

  wire[`RegAddrBus] reg1_addr_2;
  wire[`RegAddrBus] reg2_addr_2;

  wire[`RegBus] link_addr_1;
  wire[`RegBus] link_addr_2;

  wire[`RegAddrBus] id_reg_waddr_2;

  wire stallreq_to_next_1;
  wire stallreq_to_next_2;


  id u_id_1(
       .rst(rst),
       .pc_i(id_pc_1),
       .inst_i(id_inst_1),

       .pc_i_other(pc_buffer_2),

       .reg1_data_i (reg1_data_1 ),
       .reg2_data_i (reg2_data_1 ),

       .ex_wreg_i_1   (ex_wreg_o_1 ),
       .ex_waddr_i_1  (ex_reg_waddr_o_1),
       .ex_wdata_i_1  (ex_reg_wdata_1),
       .ex_aluop_i_1  (ex_aluop_o_1),

       .ex_wreg_i_2   (ex_wreg_o_2 ),
       .ex_waddr_i_2  (ex_reg_waddr_o_2),
       .ex_wdata_i_2  (ex_reg_wdata_2),
       .ex_aluop_i_2  (ex_aluop_o_2),

       .mem_wreg_i_1  (mem_wreg_o_1),
       .mem_waddr_i_1 (mem_reg_waddr_o_1),
       .mem_wdata_i_1 (mem_reg_wdata_o_1),

       .mem_wreg_i_2  (mem_wreg_o_2),
       .mem_waddr_i_2 (mem_reg_waddr_o_2),
       .mem_wdata_i_2 (mem_reg_wdata_o_2),

       .reg1_read_o (reg1_read_1 ),
       .reg2_read_o (reg2_read_1 ),

       .reg1_addr_o (reg1_addr_1 ),
       .reg2_addr_o (reg2_addr_1 ),

       .aluop_o     (id_aluop_1     ),
       .alusel_o    (id_alusel_1    ),
       .reg1_o      (id_reg1_1      ),
       .reg2_o      (id_reg2_1      ),
       .reg_waddr_o (id_reg_waddr_1 ),
       .wreg_o      (id_wreg_1     ),
       .inst_valid(id_inst_valid_1),
       .inst_pc(id_inst_pc_1),
       .inst_o(id_inst_o_1),

       .branch_flag_o(branch_flag),
       .branch_target_address_o(branch_target_address),
       .link_addr_o(link_addr_1),

       .stallreq(stallreq_to_next_1),

       .excepttype_o(id_excepttype_o_1),
       .current_inst_address_o(id_current_inst_address_o_1)
     );

  wire[`AluOpBus] id_aluop_2;
  wire[`AluSelBus] id_alusel_2;
  wire[`RegBus] id_reg1_2;
  wire[`RegBus] id_reg2_2;
  
  wire id_wreg_2;
  wire id_inst_valid_2;
  wire[`InstAddrBus] id_inst_pc_2;
  wire[`RegBus] id_inst_o_2;

  wire reg1_read_2;
  wire reg2_read_2;
  wire[`RegBus] reg1_data_2;
  wire[`RegBus] reg2_data_2;

 

  wire stallreq_from_id_2;
  wire stallreq_from_ex_2;

  wire[1:0] id_excepttype_o_2;
  wire[`RegBus] id_current_inst_address_o_2;

  

  id u_id_2(
       .rst(rst),
       .pc_i(id_pc_2),
       .inst_i(id_inst_2),

       .pc_i_other(pc_buffer_1),

       .reg1_data_i (reg1_data_2 ),
       .reg2_data_i (reg2_data_2 ),

       .ex_wreg_i_1   (ex_wreg_o_2 ),
       .ex_waddr_i_1  (ex_reg_waddr_o_2),
       .ex_wdata_i_1  (ex_reg_wdata_2),
       .ex_aluop_i_1  (ex_aluop_o_2),

       .ex_wreg_i_2   (ex_wreg_o_1 ),
       .ex_waddr_i_2  (ex_reg_waddr_o_1),
       .ex_wdata_i_2  (ex_reg_wdata_1),
       .ex_aluop_i_2  (ex_aluop_o_1),

       .mem_wreg_i_1  (mem_wreg_o_2),
       .mem_waddr_i_1 (mem_reg_waddr_o_2),
       .mem_wdata_i_1 (mem_reg_wdata_o_2),

       .mem_wreg_i_2  (mem_wreg_o_1),
       .mem_waddr_i_2 (mem_reg_waddr_o_1),
       .mem_wdata_i_2 (mem_reg_wdata_o_1),

       .reg1_read_o (reg1_read_2 ),
       .reg2_read_o (reg2_read_2 ),

       .reg1_addr_o (reg1_addr_2 ),
       .reg2_addr_o (reg2_addr_2 ),

       .aluop_o     (id_aluop_2     ),
       .alusel_o    (id_alusel_2    ),
       .reg1_o      (id_reg1_2      ),
       .reg2_o      (id_reg2_2      ),
       .reg_waddr_o (id_reg_waddr_2 ),
       .wreg_o      (id_wreg_2     ),
       .inst_valid(id_inst_valid_2),
       .inst_pc(id_inst_pc_2),
       .inst_o(id_inst_o_2),

       .branch_flag_o(branch_flag),
       .branch_target_address_o(branch_target_address),
       .link_addr_o(link_addr_2),

       .stallreq(stallreq_to_next_2),

       .excepttype_o(id_excepttype_o_2),
       .current_inst_address_o(id_current_inst_address_o_2)

     );

  wire[`AluOpBus] ex_aluop_1;
  wire[`AluSelBus] ex_alusel_1;
  wire[`RegBus] ex_reg1_1;
  wire[`RegBus] ex_reg2_1;
  wire[`RegAddrBus] ex_reg_waddr_i_1;
  wire ex_wreg_i_1;
  wire ex_inst_valid_i_1;
  wire[`InstAddrBus] ex_inst_pc_i_1;
  wire[`RegBus] ex_link_address_1;
  wire[`RegBus] ex_inst_i_1;
  wire[1:0] ex_excepttype_i_1;
  wire[`RegBus] ex_current_inst_address_i_1;

  id_ex id_ex_1(
          .clk(clk),
          .rst(rst),
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

          .reg1_addr_i(reg1_addr_1),
          .reg2_addr_i(reg2_addr_1),  
          .pc_i_other(id_inst_pc_2),
          .reg1_addr_i_other(reg1_addr_2),
          .reg2_addr_i_other(reg2_addr_2),
          .waddr_i_other(id_reg_waddr_2),

          .stallreq_from_id(stallreq_to_next_1),
          .stallreq(stallreq_from_id_1)
        );

  wire[`AluOpBus] ex_aluop_2;
  wire[`AluSelBus] ex_alusel_2;
  wire[`RegBus] ex_reg1_2;
  wire[`RegBus] ex_reg2_2;
  wire[`RegAddrBus] ex_reg_waddr_i_2;
  wire ex_wreg_i_2;
  wire ex_inst_valid_i_2;
  wire[`InstAddrBus] ex_inst_pc_i_2;
  wire[`RegBus] ex_link_address_2;
  wire[`RegBus] ex_inst_i_2;
  wire[1:0] ex_excepttype_i_2;
  wire[`RegBus] ex_current_inst_address_i_2;

  id_ex id_ex_2(
          .clk(clk),
          .rst(rst),
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

          .reg1_addr_i(reg1_addr_2),
          .reg2_addr_i(reg2_addr_2),  
          .pc_i_other(id_inst_pc_1),
          .reg1_addr_i_other(reg1_addr_1),
          .reg2_addr_i_other(reg2_addr_2),
          .waddr_i_other(id_reg_waddr_1),

          .stallreq_from_id(stallreq_to_next_2),
          .stallreq(stallreq_from_id_2)
        );


  wire ex_inst_valid_o_1;
  wire[`InstAddrBus] ex_inst_pc_o_1;
  wire[`RegBus] ex_addr_o_1;
  wire[`RegBus] ex_reg2_o_1;
  wire[1:0] ex_excepttype_o_1;
  wire[`RegBus] ex_current_inst_address_o_1;

  ex u_ex_1(
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

       .stallreq(stallreq_from_ex_1)
     );

  wire ex_inst_valid_o_2;
  wire[`InstAddrBus] ex_inst_pc_o_2;
  wire[`RegBus] ex_addr_o_2;
  wire[`RegBus] ex_reg2_o_2;
  wire[1:0] ex_excepttype_o_2;
  wire[`RegBus] ex_current_inst_address_o_2;

  ex u_ex_2(
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

       .stallreq(stallreq_from_ex_2)
     );


  wire mem_wreg_i_1;
  wire[`RegAddrBus] mem_reg_waddr_i_1;
  wire[`RegBus] mem_reg_wdata_i_1;

  wire mem_inst_valid_1;
  wire[`InstAddrBus] mem_inst_pc_1;

  wire[`AluOpBus] mem_aluop_i_1;
  wire[`RegBus] mem_addr_i_1;
  wire[`RegBus] mem_reg2_i_1;
  wire[1:0] mem_excepttype_i_1;
  wire[`RegBus] mem_current_inst_address_i_1;

  ex_mem u_ex_mem_1(
           .clk(clk       ),
           .rst(rst       ),
           .stall(stall1[4]),

           .ex_wd     (ex_reg_waddr_o_1    ),
           .ex_wreg   (ex_wreg_o_1   ),
           .ex_wdata  (ex_reg_wdata_1  ),
           .ex_inst_pc(ex_inst_pc_o_1),
           .ex_inst_valid(ex_inst_valid_o_1),
           .ex_aluop(ex_aluop_o_1),
           .ex_mem_addr(ex_addr_o_1),
           .ex_reg2(ex_reg2_o_1),
           .flush(flush),
           .ex_excepttype(ex_excepttype_o_1),
           .ex_current_inst_address(ex_current_inst_address_o_1),

           .mem_wd(mem_reg_waddr_i_1    ),
           .mem_wreg(mem_wreg_i_1  ),
           .mem_wdata(mem_reg_wdata_i_1 ),
           .mem_inst_valid(mem_inst_valid_1),
           .mem_inst_pc(mem_inst_pc_1),
           .mem_aluop(mem_aluop_i_1),
           .mem_mem_addr(mem_addr_i_1),
           .mem_reg2(mem_reg2_i_1),
           .mem_excepttype(mem_excepttype_i_1),
           .mem_current_inst_address(mem_current_inst_address_i_1)
         );


  wire mem_wreg_i_2;
  wire[`RegAddrBus] mem_reg_waddr_i_2;
  wire[`RegBus] mem_reg_wdata_i_2;

  wire mem_inst_valid_2;
  wire[`InstAddrBus] mem_inst_pc_2;

  wire[`AluOpBus] mem_aluop_i_2;
  wire[`RegBus] mem_addr_i_2;
  wire[`RegBus] mem_reg2_i_2;
  wire[1:0] mem_excepttype_i_2;
  wire[`RegBus] mem_current_inst_address_i_2;


  ex_mem u_ex_mem_2(
           .clk(clk       ),
           .rst(rst       ),
           .stall(stall2[4]),

           .ex_wd     (ex_reg_waddr_o_2    ),
           .ex_wreg   (ex_wreg_o_2   ),
           .ex_wdata  (ex_reg_wdata_2  ),
           .ex_inst_pc(ex_inst_pc_o_2),
           .ex_inst_valid(ex_inst_valid_o_2),
           .ex_aluop(ex_aluop_o_2),
           .ex_mem_addr(ex_addr_o_2),
           .ex_reg2(ex_reg2_o_2),
           .flush(flush),
           .ex_excepttype(ex_excepttype_o_2),
           .ex_current_inst_address(ex_current_inst_address_o_2),

           .mem_wd(mem_reg_waddr_i_2    ),
           .mem_wreg(mem_wreg_i_2  ),
           .mem_wdata(mem_reg_wdata_i_2 ),
           .mem_inst_valid(mem_inst_valid_2),
           .mem_inst_pc(mem_inst_pc_2),
           .mem_aluop(mem_aluop_i_2),
           .mem_mem_addr(mem_addr_i_2),
           .mem_reg2(mem_reg2_i_2),
           .mem_excepttype(mem_excepttype_i_2),
           .mem_current_inst_address(mem_current_inst_address_i_2)
         );

  wire LLbit_o_1;
  wire wb_LLbit_we_i_1;
  wire wb_LLbit_value_i_1;
  wire mem_LLbit_we_o_1;
  wire mem_LLbit_value_o_1;
  wire[1:0] mem_excepttype_o;
  wire[`RegBus] mem_current_inst_address_o_1;
  wire[`InstAddrBus] wb_inst_pc_1;

  mem u_mem_1(
        .rst     (rst     ),

        .inst_pc_i(mem_inst_pc_1),
        .wd_i    (mem_reg_waddr_i_1    ),
        .wreg_i  (mem_wreg_i_1  ),
        .wdata_i (mem_reg_wdata_i_1),
        .aluop_i(mem_aluop_i_1),
        .mem_addr_i(mem_addr_i_1),
        .reg2_i(mem_reg2_i_1),

        .mem_data_i(dram_data_i_1),

        .LLbit_i(LLbit_o_1),
        .wb_LLbit_we_i(wb_LLbit_we_i_1),
        .wb_LLbit_value_i(wb_LLbit_value_i_1),

        .excepttype_i(mem_excepttype_i_1),
        .current_inst_address_i(mem_current_inst_address_i_1),

        .inst_pc_o(wb_inst_pc_1),
        .wd_o    (mem_reg_waddr_o_1),
        .wreg_o  (mem_wreg_o_1 ),
        .wdata_o (mem_reg_wdata_o_1 ),

        .mem_addr_o(dram_addr_o_1),
        .mem_we_o(dram_we_o_1),
        .mem_sel_o(dram_sel_o_1),
        .mem_data_o(dram_data_o_1),
        .mem_ce_o(dram_ce_o_1),

        .LLbit_we_o(mem_LLbit_we_o_1),
        .LLbit_value_o(mem_LLbit_value_o_1),

        .excepttype_o(mem_excepttype_o),
        .current_inst_address_o(mem_current_inst_address_o_1)

      );
    
  wire LLbit_o_2;
  wire wb_LLbit_we_i_2;
  wire wb_LLbit_value_i_2;
  wire mem_LLbit_we_o_2;
  wire mem_LLbit_value_o_2;
  wire[`RegBus] mem_current_inst_address_o_2 ;
  wire[`InstAddrBus] wb_inst_pc_2;

  mem u_mem_2(
        .rst     (rst     ),

        .inst_pc_i(mem_inst_pc_2),
        .wd_i    (mem_reg_waddr_i_2    ),
        .wreg_i  (mem_wreg_i_2  ),
        .wdata_i (mem_reg_wdata_i_2),
        .aluop_i(mem_aluop_i_2),
        .mem_addr_i(mem_addr_i_2),
        .reg2_i(mem_reg2_i_2),

        .mem_data_i(dram_data_i_2),

        .LLbit_i(LLbit_o_2),
        .wb_LLbit_we_i(wb_LLbit_we_i_2),
        .wb_LLbit_value_i(wb_LLbit_value_i_2),

        .excepttype_i(mem_excepttype_i_2),
        .current_inst_address_i(mem_current_inst_address_i_2),

        .inst_pc_o(wb_inst_pc_2),
        .wd_o    (mem_reg_waddr_o_2),
        .wreg_o  (mem_wreg_o_2 ),
        .wdata_o (mem_reg_wdata_o_2 ),

        .mem_addr_o(dram_addr_o_2),
        .mem_we_o(dram_we_o_2),
        .mem_sel_o(dram_sel_o_2),
        .mem_data_o(dram_data_o_2),
        .mem_ce_o(dram_ce_o_2),

        .LLbit_we_o(mem_LLbit_we_o_2),
        .LLbit_value_o(mem_LLbit_value_o_2),

        .excepttype_o(mem_excepttype_o),
        .current_inst_address_o(mem_current_inst_address_o_2)

      );
  
  assign dram_pc_o_1 = wb_inst_pc_1;
  assign dram_pc_o_2 = wb_inst_pc_2;

  wire wb_wreg_1;
  wire[`RegAddrBus] wb_reg_waddr_1;
  wire[`RegBus] wb_reg_wdata_1;

  assign debug_commit_wreg_1 = wb_wreg_1;
  assign debug_commit_reg_waddr_1 = wb_reg_waddr_1;
  assign debug_commit_reg_wdata_1 = wb_reg_wdata_1;



  mem_wb mem_wb_1(
           .clk(clk),
           .rst(rst),
           .stall(stall1[5]),

           .mem_wd(mem_reg_waddr_o_1),
           .mem_wreg(mem_wreg_o_1),
           .mem_wdata(mem_reg_wdata_o_1),
           .mem_inst_pc        (mem_inst_pc_1        ),
           .mem_instr          (          ),
           .mem_inst_valid     (mem_inst_valid_1     ),

           .mem_LLbit_we(mem_LLbit_we_o_1),
           .mem_LLbit_value(mem_LLbit_value_o_1),

           .flush(flush),

           .wb_wd(wb_reg_waddr_1),
           .wb_wreg(wb_wreg_1),
           .wb_wdata(wb_reg_wdata_1),

           .wb_LLbit_we(wb_LLbit_we_i_1),
           .wb_LLbit_value(wb_LLbit_value_i_1),

           .debug_commit_pc    (debug_commit_pc_1    ),
           .debug_commit_valid (debug_commit_valid_1 ),
           .debug_commit_instr (debug_commit_instr_1 )
         );
  
  wire wb_wreg_2;
  wire[`RegAddrBus] wb_reg_waddr_2;
  wire[`RegBus] wb_reg_wdata_2;

  assign debug_commit_wreg_2 = wb_wreg_2;
  assign debug_commit_reg_waddr_2 = wb_reg_waddr_2;
  assign debug_commit_reg_wdata_2 = wb_reg_wdata_2;

  mem_wb mem_wb_2(
           .clk(clk),
           .rst(rst),
           .stall(stall2[5]),

           .mem_wd(mem_reg_waddr_o_2),
           .mem_wreg(mem_wreg_o_2),
           .mem_wdata(mem_reg_wdata_o_2),
           .mem_inst_pc        (mem_inst_pc_2        ),
           .mem_instr          (          ),
           .mem_inst_valid     (mem_inst_valid_2     ),

           .mem_LLbit_we(mem_LLbit_we_o_2),
           .mem_LLbit_value(mem_LLbit_value_o_2),

           .flush(flush),

           .wb_wd(wb_reg_waddr_2),
           .wb_wreg(wb_wreg_2),
           .wb_wdata(wb_reg_wdata_2),

           .wb_LLbit_we(wb_LLbit_we_i),
           .wb_LLbit_value(wb_LLbit_value_2),

           .debug_commit_pc    (debug_commit_pc_2    ),
           .debug_commit_valid (debug_commit_valid_2 ),
           .debug_commit_instr (debug_commit_instr_2 )
         );

  regfile u_regfile(
            .clk(clk       ),
            .rst(rst       ),

            .we_1        (wb_wreg_1),
            .pc_i_1      (),
            .waddr_1     (wb_reg_waddr_1),
            .wdata_1     (wb_reg_wdata_1),
            .we_2        (wb_wreg_2),
            .pc_i_2      (),
            .waddr_2     (wb_reg_waddr_2),
            .wdata_2     (wb_reg_wdata_2),

            .re1_1       (reg1_read_1),
            .raddr1_1    (reg1_addr_1),
            .rdata1_1    (reg1_data_1),
            .re2_1       (reg2_read_1),
            .raddr2_1    (reg2_addr_1),
            .rdata2_1    (reg2_data_1),
            .re1_2       (reg1_read_2),
            .raddr1_2    (reg1_addr_2),
            .rdata1_2    (reg1_data_2),
            .re2_2       (reg2_read_2),
            .raddr2_2    (reg2_addr_2),
            .rdata2_2    (reg2_data_2),
            .debug_reg (debug_reg)
          );

  ctrl u_ctrl(
         .clk                   (clk                   ),
         .rst                   (rst                   ),
         .stall1(stall1),
         .stallreq_from_id_1(stallreq_from_id_1),
         .stallreq_from_ex_1(stallreq_from_ex_1),
         .stall2(stall2),
         .stallreq_from_id_2(stallreq_from_id_2),
         .stallreq_from_ex_2(stallreq_from_ex_2),
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


endmodule
