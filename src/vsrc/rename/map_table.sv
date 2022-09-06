`include "core_config.sv"
`include "rename_types.sv"

module map_table
    import rename_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,

    input logic recover,

    input rename_map_t [RENAME_WIDTH-1:0] rename_req_i,
    input commit_map_t [COMMIT_WIDTH-1:0] backend_commit_i
);
endmodule
