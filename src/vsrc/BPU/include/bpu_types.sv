`ifndef BPU_TYPES_SV
`define BPU_TYPES_SV

`include "core_config.sv"

package bpu_types;

    import core_config::*;

    typedef struct packed {
        logic taken;
        logic [ADDR_WIDTH-1:0] pc;
        logic [BPU_COMPONENT_CTR_WIDTH[0]-1:0] ctr_bits;
    } base_predictor_update_info_t;

endpackage

`endif
