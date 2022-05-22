`include "frontend/frontend_defines.sv"
`include "instr_info.sv"


module ifu #(
    parameter FETCH_WIDTH = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter CACHELINE_WIDTH = 128  // FETCH_WIDTH and CACHELINE_WIDTH must match
) (
    input logic clk,
    input logic rst,

    // <-> Fetch Target Queue
    input ftq_ifu_t ftq_i,
    output logic ftq_accept_o,  // In current cycle


    // <-> Frontend <-> ICache
    output logic [1:0] icache_rreq_o,
    output logic [1:0][ADDR_WIDTH-1:0] icache_raddr_o,
    input logic [1:0] icache_rvalid_i,
    input logic [1:0][CACHELINE_WIDTH-1:0] icache_rdata_i,


    // <-> Frontend <-> Instruction Buffer
    input logic stallreq_i,
    output instr_buffer_info_t instr_buffer_o[FETCH_WIDTH]
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    logic accept_ftq_input;
    assign ftq_accept_o = accept_ftq_input;

    // P0
    logic ftq_input_valid = ftq_i.valid;
    // Send addr to ICache
    always_comb begin
        if (ftq_input_valid) begin
            icache_rreq_o[0] = 1;
            icache_rreq_o[1] = ftq_i.is_cross_cacheline ? 1 : 0;
            icache_raddr_o[0] = ftq_i.start_pc;
            icache_raddr_o[1] = ftq_i.is_cross_cacheline ? ftq_i.start_pc + 16 : 0; // TODO: remove magic number
        end else begin
            icache_rreq_o  = 0;
            icache_raddr_o = 0;
        end
    end


    // P1 
    // Cacheline returned
    logic [FETCH_WIDTH-1:0][DATA_WIDTH-1:0] cacheline_0, cacheline_1;
    assign cacheline_0 = icache_rdata_i[0];
    assign cacheline_1 = icache_rdata_i[1];
    logic icache_result_valid;
    always_comb begin
        if (ftq_i.is_cross_cacheline) icache_result_valid = icache_rvalid_i[0] & icache_rvalid_i[1];
        else icache_result_valid = icache_rvalid_i[0];
    end

    // FTQ input 
    ftq_ifu_t current_fetch_block;
    logic [ADDR_WIDTH-1:0] debug_p1_pc = current_fetch_block.start_pc;  // DEBUG
    logic [ADDR_WIDTH-1:0] debug_p0_pc = ftq_i.start_pc;  // DEBUG
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_fetch_block <= 0;
        end else begin
            current_fetch_block <= ftq_i;
        end
    end
    // If last req to icache is valid, then accept another ftq input
    assign accept_ftq_input = icache_result_valid;

    // P2
    // Send instr info to IB
    always_ff @(posedge clk or negedge rst_n) begin
        for (integer i = 0; i < FETCH_WIDTH; i++) begin
            if (i < current_fetch_block.length && ~stallreq_i && icache_result_valid) begin
                instr_buffer_o[i].valid <= 1;
                instr_buffer_o[i].pc <= current_fetch_block.start_pc + i * 4;  // Instr is 4 bytes long
                instr_buffer_o[i].instr <= cacheline_0[current_fetch_block.start_pc[3:2]+i];
            end else begin
                instr_buffer_o[i] <= 0;
            end
        end
    end

endmodule
