`include "defines.v"
`include "pc_reg.v"
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
    input wire[`RegBus] ram_rdata_i,
    output wire[`RegBus] ram_raddr_o,
    output wire[`RegBus] ram_wdata_o,
    output wire[`RegBus] ram_waddr_o,
    output wire ram_wen_o,
    output wire ram_en_o,
    output wire[`RegBus] debug_commit_pc,
    output wire debug_commit_valid,
    output wire[`InstBus] debug_commit_instr,
    output wire debug_commit_wreg,
    output wire[`RegAddrBus] debug_commit_reg_waddr,
    output wire[`RegBus] debug_commit_reg_wdata,
    output wire[1023:0] debug_reg
);

wire[`InstAddrBus] pc;
wire chip_enable;

assign ram_en_o = chip_enable;
assign ram_raddr_o = pc;

wire branch_flag;
wire[`RegBus] branch_target_address;
wire[`RegBus] link_addr;

pc_reg u_pc_reg(
    .clk(clk),
    .rst(rst),
    .pc(pc),
    .ce(chip_enable),
    .branch_flag_i(branch_flag),
    .branch_target_address(branch_target_address)
);

wire[`InstAddrBus] id_pc;
wire[`InstBus] id_inst;

if_id u_if_id(
    .clk(clk),
    .rst(rst),
    .if_pc_i(pc),
    .if_inst_i(ram_rdata_i),
    .id_pc_o(id_pc),
    .id_inst_o(id_inst)
);

wire[`AluOpBus] id_aluop;
wire[`AluSelBus] id_alusel;
wire[`RegBus] id_reg1;
wire[`RegBus] id_reg2;
wire[`RegAddrBus] id_reg_waddr;
wire id_wreg;
wire id_inst_valid;
wire[`InstAddrBus] id_inst_pc;

wire reg1_read;
wire reg2_read;
wire[`RegAddrBus] reg1_addr;
wire[`RegAddrBus] reg2_addr;
wire[`RegBus] reg1_data;
wire[`RegBus] reg2_data;

wire ex_wreg_o;
wire[`RegAddrBus] ex_reg_waddr_o;
wire[`RegBus] ex_reg_wdata;

wire mem_wreg_o;
wire[`RegAddrBus] mem_reg_waddr_o;
wire[`RegBus] mem_reg_wdata_o;


id u_id(
    .rst(rst),
    .pc_i(id_pc),
    .inst_i(id_inst),

    .reg1_data_i (reg1_data ),
    .reg2_data_i (reg2_data ),

    .ex_wreg_i   (ex_wreg_o ),
    .ex_waddr_i  (ex_reg_waddr_o),
    .ex_wdata_i  (ex_reg_wdata),

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

    .branch_flag_o(branch_flag),
    .branch_target_address_o(branch_target_address),
    .link_addr_o(link_addr)
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

    .ex_aluop(ex_aluop),
    .ex_alusel(ex_alusel),
    .ex_reg1(ex_reg1),
    .ex_reg2(ex_reg2),
    .ex_wd(ex_reg_waddr_i),
    .ex_wreg(ex_wreg_i),
    .ex_inst_pc(ex_inst_pc_i),
    .ex_inst_valid(ex_inst_valid_i),
    .ex_link_address(ex_link_address)
);


wire ex_inst_valid_o;
wire [`InstAddrBus] ex_inst_pc_o;

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
    .link_addr_i(link_addr),

    .wd_o(ex_reg_waddr_o),
    .wreg_o(ex_wreg_o),
    .wdata_o(ex_reg_wdata),
    .inst_valid_o(ex_inst_valid_o),
    .inst_pc_o(ex_inst_pc_o)
);


wire mem_wreg_i;
wire[`RegAddrBus] mem_reg_waddr_i;
wire[`RegBus] mem_reg_wdata_i;

wire mem_inst_valid;
wire[`InstAddrBus] mem_inst_pc;
wire[`InstBus] mem_inst;

ex_mem u_ex_mem(
    .clk(clk       ),
    .rst(rst       ),

    .ex_wd     (ex_reg_waddr_o    ),
    .ex_wreg   (ex_wreg_o   ),
    .ex_wdata  (ex_reg_wdata  ),
    .ex_inst_pc(ex_inst_pc_o),
    .ex_inst(),
    .ex_inst_valid(ex_inst_valid_o),

    .mem_wd(mem_reg_waddr_i    ),
    .mem_wreg(mem_wreg_i  ),
    .mem_wdata(mem_reg_wdata_i ),
    .mem_inst_valid(mem_inst_valid),
    .mem_inst(mem_inst),
    .mem_inst_pc(mem_inst_pc)
         );



mem u_mem(
    .rst     (rst     ),

    .wd_i    (mem_reg_waddr_i    ),
    .wreg_i  (mem_wreg_i  ),
    .wdata_i (mem_reg_wdata_i),

    .wd_o    (mem_reg_waddr_o),
    .wreg_o  (mem_wreg_o ),
    .wdata_o (mem_reg_wdata_o )
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
    .mem_instr          (mem_inst          ),
    .mem_inst_valid     (mem_inst_valid     ),

    .wb_wd(wb_reg_waddr),
    .wb_wreg(wb_wreg),
    .wb_wdata(wb_reg_wdata),

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
    
endmodule