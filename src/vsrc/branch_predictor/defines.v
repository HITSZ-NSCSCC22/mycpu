`ifndef DEFINES_V

// BTB parameters
`define BTB_DEPTH 64
`define BTB_DEPTH_LOG2 6
`define BTB_TAG_LENGTH 12
`define BTB_ENTRY_LENGTH `BTB_TAG_LENGTH + 30 // tag[], target[30]
`define BTB_ENTRY_BUS `BTB_ENTRY_LENGTH-1:0

// PHT parameters (Pattern History Table)
`define PHT_DEPTH 65536
`define PHT_DEPTH_LOG2 16
`define PHT_TAG_WIDTH 8


// GHR parameters (Global History Register)
`define GHR_DEPTH 200
`define GHR_BUS `GHR_DEPTH-1:0
`define MAX_GHT_LENGTH 512
`define MAX_GHT_LENGTH_LOG2 9

// Parameters
`define FEEDBACK_LATENCY 4

`endif
