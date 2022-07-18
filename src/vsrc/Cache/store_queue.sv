`include "core_types.sv"
`include "core_config.sv"

module store_queue
    import core_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,
    input store_req_t store_req_i,

    input logic [$clog2(LSU_STORE_QUEU_SIZE)-1:0] commit_id_i,

    output store_req_t store_req_o

);

    localparam QUEUE_SIZE = LSU_STORE_QUEU_SIZE;

    store_req_t [QUEUE_SIZE-1:0] queue;
    logic [$clog2(QUEUE_SIZE)-1:0] write_ptr, read_ptr;


endmodule
