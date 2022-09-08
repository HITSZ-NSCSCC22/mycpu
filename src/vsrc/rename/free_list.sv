`include "core_config.sv"
`include "rename_types.sv"

module free_list
    import rename_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,
    input logic recover,

    input logic [RENAME_WIDTH-1:0] rename_req,
    output logic [RENAME_WIDTH-1:0][$clog2(PHYREG)-1:0] prf,

    input commit_map_t [COMMIT_WIDTH-1:0] commit_info,

    output logic stallreq_o
);

    logic [PHYREG-1:0] free_prf_queue, next_free_prf_queue;
    logic [$clog2(PHYREG)-1:0] rename_ptr, commit_ptr;

    assign stallreq_o = rename_ptr == commit_ptr && free_prf_queue[rename_ptr];


    always_ff @(posedge clk) begin
        if (rst | recover) begin
            free_prf_queue <= 0;
        end else begin
            free_prf_queue <= next_free_prf_queue;
        end
    end


    logic [$clog2(COMMIT_WIDTH)-1:0] backend_commit_num;
    always_comb begin
        backend_commit_num = 0;
        for (integer i = 0; i < COMMIT_WIDTH; i++) begin
            backend_commit_num += commit_info[i].valid;
        end
    end
    // Popcnt of frontend_instr_i.[i].valid
    logic [$clog2(RENAME_WIDTH)-1:0] rename_num;
    always_comb begin
        rename_num = 0;
        for (integer i = 0; i < RENAME_WIDTH; i++) begin
            rename_num += rename_req[i];
        end
    end

    always_ff @(posedge clk) begin
        if (rst | recover) begin
            rename_ptr <= 0;
            commit_ptr <= 0;
        end else begin
            rename_ptr <= rename_ptr + rename_num;
            commit_ptr <= commit_ptr + backend_commit_num;
        end
    end

    always_comb begin
        for (integer i = 0; i < PHYREG; i++) begin
            next_free_prf_queue[i] = free_prf_queue[i];
        end

        for (integer i = 0; i < COMMIT_WIDTH; i++) begin
            if (i < backend_commit_num) begin
                next_free_prf_queue[commit_ptr+i[$clog2(PHYREG)-1:0]] = 0;
            end
        end

        for (integer i = 0; i < RENAME_WIDTH; i++) begin
            if (i < rename_num) begin
                next_free_prf_queue[rename_ptr+i[$clog2(PHYREG)-1:0]] = 1;
            end
        end
    end

    logic [$clog2(PHYREG)-1:0] prf_used;
    always_comb begin
        prf_used = 0;
        for (integer i = 0; i < RENAME_WIDTH; i++) begin
            prf_used = prf_used + 1;
            prf[i]   = rename_ptr + prf_used - 1;
        end
    end

endmodule
