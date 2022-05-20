`ifndef PIPELINE_DEFINES_SV
`define PIPELINE_DEFINES_SV
`include "defines.sv"
`include "instr_info.sv"
`include "csr_defines.sv"
`include "tlb_defines.sv"

`define DECODE_WIDTH 2
typedef struct packed {
    instr_buffer_info_t instr_info;

    // Reg read info
    logic use_imm;
    logic [`RegBus] imm;
    logic [1:0] reg_read_valid;  // Read valid for 2 regs
    logic [1:0][`RegAddrBus] reg_read_addr;  // Read addr, {reg2, reg1}
    logic [`InstBus] instr;

    logic [`AluOpBus] aluop;
    logic [`AluSelBus] alusel;
    logic [`RegAddrBus] reg_write_addr;
    logic reg_write_valid;
    logic csr_we;
    csr_write_signal csr_signal;

    logic excp;
    logic [8:0] excp_num;
    logic refetch;
} id_dispatch_struct;


typedef struct packed {
    instr_buffer_info_t instr_info;

    // Pass ID info to EX to help data forwarding
    logic [1:0][`RegAddrBus] read_reg_addr;
    logic use_imm;

    logic [`InstBus] instr;
    logic [`RegBus] oprand1;
    logic [`RegBus] oprand2;
    logic [`RegBus] imm;
    logic [`AluOpBus] aluop;
    logic [`AluSelBus] alusel;
    logic [`RegAddrBus] reg_write_addr;
    logic reg_write_valid;
    logic [5:0] branch_com_result;

    logic [`RegBus]  csr_reg_data;
    csr_write_signal csr_signal;

    logic excp;
    logic [8:0] excp_num;
    logic refetch;
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

    logic excp;
    logic [9:0] excp_num;
    logic refetch;
} ex_mem_struct;

// MEM stage data forwarding
typedef struct packed {
    logic is_load_data;
    logic write_reg;
    logic [`RegAddrBus] write_reg_addr;
    logic [`RegBus] write_reg_data;
} mem_data_forward_t;

typedef struct packed {
    instr_buffer_info_t instr_info;

    logic [`RegAddrBus] waddr;
    logic [`RegBus] wdata;
    logic wreg;
    logic [`AluOpBus] aluop;
    csr_write_signal csr_signal;

    //load store difftest
    logic [7:0] inst_ld_en;
    logic [7:0] inst_st_en;
    logic [`DataAddrBus] load_addr;
    logic [`DataAddrBus] store_addr;
    logic [`RegBus] store_data;

    logic excp;
    logic [15:0] excp_num;
    logic refetch;
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

// Difftest Commit Information
// Used to submit instr info into difftest framework
typedef struct packed {
    logic [`InstAddrBus] pc;
    logic valid;
    logic [`InstBus] instr;
    logic [7:0] inst_ld_en;
    logic [31:0] ld_paddr;
    logic [31:0] ld_vaddr;
    logic [7:0] inst_st_en;
    logic [31:0] st_paddr;
    logic [31:0] st_vaddr;
    logic [31:0] st_data;
} diff_commit;

typedef struct packed {
    logic we;
    logic value;
} wb_llbit;

typedef struct packed {
    logic valid;
    logic [`AluOpBus] aluop;
    wb_reg wb_reg_o;
    wb_llbit llbit_o;
    logic excp;
    logic [15:0] excp_num;
    logic fetch_flush;
    csr_write_signal csr_signal_o;
    diff_commit diff_commit_o;
} wb_ctrl;

typedef struct packed {
    logic csr_pg;
    logic csr_da;
    logic [`RegBus] csr_dmw0;
    logic [`RegBus] csr_dmw1;
    logic [1:0] csr_plv;
    logic [1:0] csr_datm;
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
