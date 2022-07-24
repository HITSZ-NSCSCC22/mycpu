`ifndef BPU_TYPES_SV
`define BPU_TYPES_SV

`include "core_config.sv"

package bpu_types;

    import core_config::*;

    typedef struct packed {
        logic valid;
        logic is_cross_cacheline;
        logic [2:0] branch_type;
        // Virtual tag, pc[1:0] is always 0, so not used in index or tag
        logic [ADDR_WIDTH-3-$clog2(FTB_DEPTH):0] tag;
        logic [ADDR_WIDTH-1:0] jump_target_address;
        logic [ADDR_WIDTH-1:0] fall_through_address;
    } ftb_entry_t;

    typedef struct packed {
        logic valid;
        logic predict_correct;
        logic branch_taken;
        logic pred_useful;
        logic is_conditional;
        logic [$clog2(BPU_TAG_COMPONENT_NUM+1)-1:0] pred_provider_id;
        logic [$clog2(BPU_TAG_COMPONENT_NUM+1)-1:0] altpred_provider_id;
        logic [$clog2(2048)-1:0] provider_entry_id;  // TODO: hard-coded for now
        logic [2:0] provider_ctr_bits;
        logic [BPU_TAG_COMPONENT_NUM-1:0][2:0] tag_predictor_useful_bits;
    } tage_predictor_update_info_t;

    typedef struct packed {
        logic valid;
        logic ftb_hit;
        logic [$clog2(BPU_TAG_COMPONENT_NUM+1)-1:0] provider_id;
        logic [$clog2(BPU_TAG_COMPONENT_NUM+1)-1:0] alt_provider_id;
        logic useful;
        logic [$clog2(8192)-1:0] provider_entry_id;  // TODO: hard-coded
        logic [3:0] provider_useful_bits;
        logic [3:0] provider_ctr_bits;
    } bpu_ftq_meta_t;

    typedef struct packed {
        logic valid;
        logic ftb_hit;
        logic ftb_dirty;
        logic [$clog2(BPU_TAG_COMPONENT_NUM+1)-1:0] provider_id;
        logic [$clog2(BPU_TAG_COMPONENT_NUM+1)-1:0] alt_provider_id;
        logic useful;
        logic [$clog2(8192)-1:0] provider_entry_id;  // TODO: hard-coded
        logic [3:0] provider_useful_bits;
        logic [3:0] provider_ctr_bits;
        logic is_cross_cacheline;
        logic is_branch;
        logic is_conditional;
        logic is_taken;
        logic predicted_taken;  // Comes from BPU
        logic [ADDR_WIDTH-1:0] start_pc;
        logic [ADDR_WIDTH-1:0] jump_target_address;
        logic [ADDR_WIDTH-1:0] fall_through_address;
    } ftq_bpu_meta_t;

    typedef struct packed {
        logic valid;
        logic ftb_hit;
        logic ftb_dirty;
        logic [$clog2(BPU_TAG_COMPONENT_NUM+1)-1:0] provider_id;
        logic [$clog2(BPU_TAG_COMPONENT_NUM+1)-1:0] alt_provider_id;
        logic useful;
        logic [$clog2(8192)-1:0] provider_entry_id;  // TODO: hard-coded
        logic [3:0] provider_useful_bits;
        logic [3:0] provider_ctr_bits;
        logic [ADDR_WIDTH-1:0] jump_target_address;
        logic [ADDR_WIDTH-1:0] fall_through_address;
    } ftq_bpu_meta_entry_t;

endpackage

`endif
