`ifndef PIPELINE_DEFINES_SV
`define PIPELINE_DEFINES_SV
`include "defines.sv"
`include "instr_info.sv"
`include "csr_defines.sv"

`define DECODE_WIDTH 2
typedef struct packed {
    logic instr_valid;
    instr_buffer_info_t instr_info;

    // Reg read info
    logic use_imm;
    logic [`RegBus] imm;
    logic [1:0] reg_read_valid;  // Read valid for 2 regs
    logic [`RegNumLog2*2-1:0] reg_read_addr;  // Read addr, {reg2, reg1}

    logic [`AluOpBus] aluop;
    logic [`AluSelBus] alusel;
    logic [`RegAddrBus] reg_write_addr;
    logic reg_write_valid;
    logic csr_we;
    csr_write_signal csr_signal;
} id_dispatch_struct;


typedef struct packed {
    logic instr_valid;
    instr_buffer_info_t instr_info;

    logic [`RegBus] oprand1;
    logic [`RegBus] oprand2;
    logic [`AluOpBus] aluop;
    logic [`AluSelBus] alusel;
    logic [`RegAddrBus] reg_write_addr;
    logic reg_write_valid;

    logic csr_we;
    csr_write_signal csr_signal;
} dispatch_ex_struct;

`endif
