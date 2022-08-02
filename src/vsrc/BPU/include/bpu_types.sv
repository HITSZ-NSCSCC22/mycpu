`ifndef BPU_TYPES_SV
`define BPU_TYPES_SV

`include "core_config.sv"

package bpu_types;

    import core_config::*;

    typedef struct packed {
        logic valid;
        logic is_cross_cacheline;
        logic [1:0] branch_type;
        // Virtual tag, pc[1:0] is always 0, so not used in index or tag
        logic [ADDR_WIDTH-3-$clog2(FTB_NSET):0] tag;
        logic [ADDR_WIDTH-1:0] jump_target_address;
        logic [ADDR_WIDTH-1:0] fall_through_address;
    } ftb_entry_t;

    typedef struct packed {
        logic [$clog2(BPU_TAG_COMPONENT_NUM+1)-1:0] provider_id;
        logic [$clog2(BPU_TAG_COMPONENT_NUM+1)-1:0] alt_provider_id;
        logic useful;
        logic [BPU_TAG_COMPONENT_NUM:0][2:0] provider_ctr_bits;
        logic [BPU_TAG_COMPONENT_NUM-1:0][10:0] tag_predictor_query_tag;
        logic [BPU_TAG_COMPONENT_NUM-1:0][10:0] tag_predictor_origin_tag;
        logic [BPU_TAG_COMPONENT_NUM-1:0][10:0] tag_predictor_hit_index;
        logic [BPU_TAG_COMPONENT_NUM-1:0][2:0] tag_predictor_useful_bits;
    } tage_meta_t;

    typedef struct packed {
        logic valid;
        logic predict_correct;
        logic branch_taken;
        logic is_conditional;
        tage_meta_t bpu_meta;
    } tage_predictor_update_info_t;

    typedef struct packed {
        logic valid;
        logic ftb_hit;
        tage_meta_t bpu_meta;
    } bpu_ftq_meta_t;

    typedef struct packed {
        logic valid;
        logic ftb_hit;
        logic ftb_dirty;
        logic is_cross_cacheline;

        tage_meta_t bpu_meta;

        // Backend Decode Info
        logic is_branch;
        logic [1:0] branch_type;
        logic is_taken;
        logic predicted_taken;

        // FTB meta
        logic [ADDR_WIDTH-1:0] start_pc;
        logic [ADDR_WIDTH-1:0] jump_target_address;
        logic [ADDR_WIDTH-1:0] fall_through_address;
    } ftq_bpu_meta_t;

    typedef struct packed {
        logic valid;
        logic ftb_hit;
        logic ftb_dirty;

        tage_meta_t bpu_meta;

        logic [ADDR_WIDTH-1:0] jump_target_address;
        logic [ADDR_WIDTH-1:0] fall_through_address;
    } ftq_bpu_meta_entry_t;



endpackage

`endif
