`include "core_config.sv"
`include "rename_types.sv"

module register_rename
    import rename_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,

    input logic recover,
    input rename_req_t [RENAME_WIDTH-1:0] rename_req_i,
    input commit_map_t [COMMIT_WIDTH-1:0] backend_commit_i,

    output rename_map_out_t [RENAME_WIDTH-1:0] rename_result

);
    logic [RENAME_WIDTH-1:0] free_list_req;
    logic [RENAME_WIDTH-1:0][$clog2(PHYREG)-1:0] prf;
    rename_map_t [RENAME_WIDTH-1:0] rename_map_i;

    assign free_list_req[0] = rename_req_i[0].wen;
    assign free_list_req[1] = rename_req_i[1].wen;
    assign free_list_req[2] = rename_req_i[2].wen;
    assign free_list_req[3] = rename_req_i[3].wen;

    free_list u_free_list (
        .clk(clk),
        .rst(rst),
        .recover(recover),

        .rename_req(free_list_req),
        .prf(prf),

        .commit_info(backend_commit_i),

        .stallreq_o()
    );

    assign rename_map_i[0] = {rename_req_i[0], prf[0]};
    assign rename_map_i[1] = {rename_req_i[1], prf[1]};
    assign rename_map_i[2] = {rename_req_i[2], prf[2]};
    assign rename_map_i[3] = {rename_req_i[3], prf[3]};

    map_table u_map_table (
        .clk(clk),
        .rst(rst),

        .recover(recover),

        .rename_req_i(rename_map_i),
        .backend_commit_i(backend_commit_i),

        .rename_result(rename_result)
    );

endmodule
