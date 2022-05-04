`include "defines.v"

/* dummy_icache
* hold output until AXI returns value
*/
module dummy_icache #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst,

    // <-> IF
    // All signals are 1 cycle valid
    // all 0 means invalid
    input logic [ADDR_WIDTH-1:0] raddr_1_i,
    input logic [ADDR_WIDTH-1:0] raddr_2_i,
    // Require IF stage not to send more instr addr
    // stallreq is pull up the next clk when queue is full
    // and pull down then next clk when queue can accept addr
    output logic stallreq_o,
    // rvalid is 1 when output is valid
    output logic rvalid_1_o,
    output logic rvalid_2_o,
    // Must return the addr as well
    output logic [ADDR_WIDTH-1:0] raddr_1_o,
    output logic [ADDR_WIDTH-1:0] raddr_2_o,
    output logic [DATA_WIDTH-1:0] rdata_1_o,
    output logic [DATA_WIDTH-1:0] rdata_2_o,

    // <-> AXI Controller
    output logic [ADDR_WIDTH-1:0] axi_addr_o,

    // Assume busy is pull down the same cycle when data is ready
    input logic [DATA_WIDTH-1:0] axi_data_i,
    input logic axi_busy_i
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    logic [ADDR_WIDTH-1:0] raddrs[2];  // Accept two addr

    // States
    enum int unsigned {
        ACCEPT_ADDR = 0,
        IN_TRANSACTION_1 = 1,
        IN_TRANSACTION_2 = 2
    }
        state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin : state_ff
        if (!rst_n) begin
            state <= ACCEPT_ADDR;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin : transition_comb
        case (state)
            ACCEPT_ADDR: begin
                if (raddr_1_i != 0 || raddr_2_i != 0) begin
                    next_state = IN_TRANSACTION_1;
                end else begin
                    next_state = ACCEPT_ADDR;
                end
            end
            IN_TRANSACTION_1: begin
                if (axi_busy_i == 0) begin
                    next_state = IN_TRANSACTION_2;
                end else begin
                    next_state = IN_TRANSACTION_1;
                end
            end
            IN_TRANSACTION_2: begin
                if (axi_busy_i == 0) begin
                    next_state = ACCEPT_ADDR;
                end else begin
                    next_state = IN_TRANSACTION_2;
                end
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin : raddrs_ff
        if (!rst_n) begin
            raddrs[0] <= 0;
            raddrs[1] <= 0;
        end else begin
            case (state)
                ACCEPT_ADDR: begin
                    raddrs[0] <= raddr_1_i;
                    raddrs[1] <= raddr_2_i;
                end
                IN_TRANSACTION_1, IN_TRANSACTION_2: begin
                    // Do nothing
                end
            endcase
        end
    end

    assign stallreq_o = ~(state == ACCEPT_ADDR);

    always_ff @(posedge clk or negedge rst_n) begin : axi_ff
        if (!rst_n) begin
            axi_addr_o <= 0;
        end else begin
            case (state)
                ACCEPT_ADDR: begin
                    if (raddr_1_i != 0) axi_addr_o <= raddr_1_i;
                end
                IN_TRANSACTION_1: begin
                    if (raddrs[1] != 0) axi_addr_o <= raddrs[1];
                end
                IN_TRANSACTION_2: begin
                    axi_addr_o <= 0;
                end
            endcase
        end
    end

    // Output logic
    always_comb begin : output_comb
        rvalid_1_o = 0;
        rvalid_2_o = 0;
        raddr_1_o  = 0;
        raddr_2_o  = 0;
        rdata_1_o  = 0;
        rdata_2_o  = 0;
        case (state)
            ACCEPT_ADDR: begin
            end
            IN_TRANSACTION_1: begin
                rvalid_1_o = ~axi_busy_i;
                rdata_1_o  = axi_busy_i ? 0 : axi_data_i;
            end
            IN_TRANSACTION_2: begin
                rvalid_2_o = ~axi_busy_i;
                rdata_2_o  = axi_busy_i ? 0 : axi_data_i;
            end
        endcase
    end

endmodule
