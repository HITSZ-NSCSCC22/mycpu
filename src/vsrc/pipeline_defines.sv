`ifndef PIPELINE_DEFINES_SV
`define PIPELINE_DEFINES_SV
`include "defines.sv"
`include "instr_info.sv"
`include "csr_defines.sv"

`define DECODE_WIDTH 2
typedef struct packed {
    instr_buffer_info_t instr_info;

    // Reg read info
    logic use_imm;
    logic [`RegBus] imm;
    logic [1:0] reg_read_valid;  // Read valid for 2 regs
    logic [`RegNumLog2*2-1:0] reg_read_addr;  // Read addr, {reg2, reg1}
    logic [`InstBus] instr;

    logic [`AluOpBus] aluop;
    logic [`AluSelBus] alusel;
    logic [`RegAddrBus] reg_write_addr;
    logic reg_write_valid;
    logic csr_we;
    csr_write_signal csr_signal;
} id_dispatch_struct;


typedef struct packed {
    instr_buffer_info_t instr_info;

    logic [`InstBus] instr;
    logic [`RegBus] oprand1;
    logic [`RegBus] oprand2;
    logic [`RegBus] imm;
    logic [`AluOpBus] aluop;
    logic [`AluSelBus] alusel;
    logic [`RegAddrBus] reg_write_addr;
    logic reg_write_valid;
    logic [5:0] branch_com_result;

    logic csr_we;
    csr_write_signal csr_signal;
} dispatch_ex_struct;

typedef struct packed {
    logic reg_valid;
    logic [`RegAddrBus] reg_addr;
    logic [`RegBus] reg_data;
    logic [`AluOpBus] aluop_i;
} ex_dispatch_struct;

typedef struct packed {
    instr_buffer_info_t instr_info;

    logic wreg;
    logic [`RegAddrBus] waddr;
    logic [`AluOpBus] aluop;
    logic [`RegBus] mem_addr;
    logic [`RegBus] reg2;
    csr_write_signal csr_signal;
    logic [`RegBus] wdata;
} ex_mem_struct;

typedef struct packed {
    logic reg_valid;
    logic [`RegAddrBus] reg_addr;
    logic [`RegBus] reg_data;
} mem_dispatch_struct;

typedef struct packed {
    instr_buffer_info_t instr_info;

    logic [`RegAddrBus] waddr;
    logic wreg;
    logic [`RegBus] wdata;
    logic [`AluOpBus] aluop;
    csr_write_signal csr_signal;
} mem_wb_struct;

typedef struct packed {
    logic we;
    logic ce;
    logic [3:0] sel;
    logic [`DataAddrBus] addr;
    logic [`RegBus] data;
} mem_axi_struct;

typedef struct packed {
    logic we;
    logic [`InstAddrBus] pc;
    logic [`RegAddrBus] waddr;
    logic [`RegBus] wdata;
} wb_reg;

typedef struct packed {
    logic csr_pg;
    logic csr_da;
    logic [`RegBus] csr_dmw0;
    logic [`RegBus] csr_dmw1;
    logic [1:0] csr_plv;
    logic [1:0] csr_datf;
} csr_to_mem_struct;

typedef struct packed {
    logic data_tlb_found;
    logic [4:0] data_tlb_index;
    logic data_tlb_v;
    logic data_tlb_d;
    logic [1:0] data_tlb_mat;
    logic [1:0] data_tlb_plv;
} tlb_to_mem_struct;

`endif
