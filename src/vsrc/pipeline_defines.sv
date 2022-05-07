`ifndef PIPELINE_DEFINES_SV
`define PIPELINE_DEFINES_SV
`include "defines.sv"
`include "instr_info.sv"
`include "csr_defines.sv"

`define DECODE_WIDTH 2
typedef struct packed {
    logic [`AluOpBus] aluop;
    logic [`AluSelBus] alusel;
    logic [`RegAddrBus] reg_write_addr;
    logic reg_write_valid;
    logic instr_valid;
    instr_buffer_info_t instr_info;
    logic csr_we;
    csr_write_signal csr_signal;
} id_dispatch_struct;

`endif
