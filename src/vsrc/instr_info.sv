// Instruction info define
`ifndef INSTR_INFO_SV
`define INSTR_INFO_SV
`include "defines.sv"

typedef struct packed {
    bit valid;
    bit is_last_in_block;  // Mark the last instruction in basic block
    bit [`InstAddrBus] pc;
    bit [`InstBus] instr;

    // BPU info
    bit bpu_predicted_taken;
    bit [2:0] bpu_useful_bits;
    bit [2:0] bpu_ctr_bits;
    bit [2:0] bpu_provider_id;
    bit [13:0] bpu_provider_query_index;
} instr_buffer_info_t;

typedef struct packed {
    bit valid;
    bit [`InstAddrBus] pc;
    bit taken;

    // BPU info
    bit [2:0]  bpu_useful_bits;
    bit [2:0]  bpu_ctr_bits;
    bit [2:0]  bpu_provider_id;
    bit [13:0] bpu_provider_query_index;
} branch_update_info_t;

`endif
