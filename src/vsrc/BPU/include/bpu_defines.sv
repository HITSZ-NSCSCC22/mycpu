`ifndef BPU_DEFINES_SV
`define BPU_DEFINES_SV

// BTB parameters
`define BTB_DEPTH 64
`define BTB_DEPTH_LOG2 6
`define BTB_TAG_LENGTH 12
`define BTB_ENTRY_LENGTH `BTB_TAG_LENGTH + 30 // tag[], target[30]
`define BTB_ENTRY_BUS `BTB_ENTRY_LENGTH-1:0



// GHR parameters (Global History Register)
`define GHR_DEPTH 200
`define GHR_BUS `GHR_DEPTH-1:0
`define MAX_GHT_LENGTH 512
`define MAX_GHT_LENGTH_LOG2 9

typedef struct packed {
    logic valid;
    logic predict_correct;
    logic branch_taken;
    logic is_conditional;
    logic [31:0] pc;  // TODO: hard-coded for now
    logic [31:0] target_addr;
    logic [4:0] provider_id;
    logic [14:0] provider_entry_id;
    logic [2:0] provider_ctr_bits;
    logic [2:0] provider_useful_bits;
} branch_update_info_t;

`endif
