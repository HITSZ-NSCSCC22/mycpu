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
    input commit_map_t [COMMIT_WIDTH-1:0] backend_commit_i,

    output rename_map_out_t [RENAME_WIDTH-1:0] rename_result
);

    logic [$clog2(PHYREG)-1:0] rename_maping_table_bank[31:0];

    logic [$clog2(PHYREG)-1:0] commit_maping_table_bank[31:0];

    logic [  RENAME_WIDTH-1:0] inst_wen;

    assign inst_wen[0] = rename_req_i[0].wen;
    assign inst_wen[1] = rename_req_i[1].wen;
    assign inst_wen[2] = rename_req_i[2].wen;
    assign inst_wen[3] = rename_req_i[3].wen;

    assign rename_result[0].prs1 = rename_maping_table_bank[rename_req_i[0].rs1];
    assign rename_result[0].prs2 = rename_maping_table_bank[rename_req_i[0].rs1];

    assign rename_result[1].prs1 = (inst_wen[0] && rename_req_i[0].rd == rename_req_i[1].rs1) ?
                                    rename_req_i[0].prd : rename_maping_table_bank[rename_req_i[1].rs1];
    assign rename_result[1].prs2 = (inst_wen[0] && rename_req_i[0].rd == rename_req_i[1].rs2) ?
                                    rename_req_i[0].prd : rename_maping_table_bank[rename_req_i[1].rs2];


    assign rename_result[2].prs1 = (inst_wen[1] && rename_req_i[1].rd == rename_req_i[2].rs1) ?
                                    rename_req_i[1].prd : (inst_wen[0] && rename_req_i[0].rd == rename_req_i[2].rs1) ?
                                    rename_req_i[0].prd : rename_maping_table_bank[rename_req_i[2].rs1];

    assign rename_result[2].prs2 = (inst_wen[1] && rename_req_i[1].rd == rename_req_i[2].rs2) ?
                                    rename_req_i[1].prd : (inst_wen[0] && rename_req_i[0].rd == rename_req_i[2].rs2) ?
                                    rename_req_i[0].prd : rename_maping_table_bank[rename_req_i[2].rs2];

    assign rename_result[3].prs1 = (inst_wen[2] && rename_req_i[2].rd == rename_req_i[3].rs1) ?
                                    rename_req_i[2].prd : (inst_wen[2] && rename_req_i[2].rd == rename_req_i[3].rs1) ?
                                    rename_req_i[1].prd : (inst_wen[1] && rename_req_i[1].rd == rename_req_i[3].rs1) ?
                                    rename_req_i[0].prd : rename_maping_table_bank[rename_req_i[3].rs1];

    assign rename_result[3].prs2 = (inst_wen[2] && rename_req_i[2].rd == rename_req_i[3].rs2) ?
                                    rename_req_i[2].prd : (inst_wen[1] && rename_req_i[1].rd == rename_req_i[3].rs2) ?
                                    rename_req_i[1].prd : (inst_wen[0] && rename_req_i[0].rd == rename_req_i[3].rs2) ?
                                    rename_req_i[0].prd : rename_maping_table_bank[rename_req_i[3].rs2];


    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer i = 0; i < 32; i++) begin
                rename_maping_table_bank[i] <= 0;
            end
        end else if (recover) begin
            for (integer i = 0; i < 32; i++) begin
                rename_maping_table_bank[i] <= commit_maping_table_bank[i];
            end
        end else begin
            for (integer i = 0; i < RENAME_WIDTH; i++) begin
                if (inst_wen[i]) begin
                    rename_maping_table_bank[rename_req_i[i].rd] <= rename_req_i[i].prd;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer i = 0; i < 32; i++) begin
                commit_maping_table_bank[i] <= 0;
            end
        end else begin
            for (integer i = 0; i < COMMIT_WIDTH; i++) begin
                if (backend_commit_i[i].valid && backend_commit_i[i].wen) begin
                    commit_maping_table_bank[backend_commit_i[i].rd] <= backend_commit_i[i].prd;
                end
            end
        end
    end

endmodule
