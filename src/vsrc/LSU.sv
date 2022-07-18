module LSU #(
    parameter FE_ADDR_W   = 32,       //Address width - width of the Master's entire access address (including the LSBs that are discarded, but discarding the Controller's)
    parameter FE_DATA_W = 32,
    parameter FE_NBYTES = FE_DATA_W / 8
) (
    input logic clk,
    input logic rst,

    input logic cpu_valid,
    input logic [FE_ADDR_W-1:0] cpu_addr,
    input logic [FE_DATA_W-1:0] cpu_wdata,
    input logic [FE_NBYTES-1:0] cpu_wstrb,
    output logic cpu_ready,

    // next cycle
    output logic [FE_DATA_W-1:0] cpu_rdata,
    output logic cpu_data_valid,

    // from wb
    input logic cpu_flush,
    input logic cpu_store_commit,

    output logic dcache_valid,
    output logic [FE_ADDR_W-1:0] dcache_addr,
    output logic [FE_DATA_W-1:0] dcache_wdata,
    output logic [FE_NBYTES-1:0] dcache_wstrb,
    input logic [FE_DATA_W-1:0] dcache_rdata,
    input logic dcache_ready

);
    logic cpu_store;

    // P1 signal
    logic p1_valid_reg;
    logic p1_cpu_store;
    logic [FE_ADDR_W-1:0] p1_addr_reg;
    logic [FE_DATA_W-1:0] p1_wdata_reg;
    logic [FE_NBYTES-1:0] p1_wstrb_reg;


    enum integer {
        IDLE,
        STORE_COMMIT_WAIT,
        STORE_REQ_SEND,
        STORE_REQ_WAIT
    }
        state, next_state;
    // State machine
    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end
    always_comb begin
        case (state)
            IDLE: begin
                if (cpu_store & ~cpu_flush) next_state = STORE_COMMIT_WAIT;
                else next_state = IDLE;
            end
            STORE_COMMIT_WAIT: begin
                if (cpu_flush) next_state = IDLE;
                else if (cpu_store_commit) next_state = STORE_REQ_SEND;
                else next_state = STORE_COMMIT_WAIT;
            end
            STORE_REQ_SEND: begin
                if (dcache_ready) next_state = IDLE;
                else next_state = STORE_REQ_SEND;
            end
            STORE_REQ_WAIT: begin
                if (dcache_ready) next_state = IDLE;
                else next_state = STORE_REQ_WAIT;
            end
            default: next_state = IDLE;
        endcase
    end

    assign cpu_store = cpu_wstrb != 0 && cpu_valid;

    // DCache handshake
    always_comb begin
        // Default
        dcache_valid = 0;
        dcache_addr  = 0;
        dcache_wdata = 0;
        dcache_wstrb = 0;
        case (state)
            IDLE: begin
                if (~cpu_store) begin  // Read
                    dcache_valid = cpu_valid;
                    dcache_addr  = cpu_addr;
                end
            end
            STORE_REQ_SEND: begin
                dcache_valid = 1;
                dcache_addr  = p1_addr_reg;
                dcache_wdata = p1_wdata_reg;
                dcache_wstrb = p1_wstrb_reg;
            end
            STORE_REQ_WAIT: begin
                if (~dcache_ready) begin
                    dcache_valid = 1;
                    dcache_addr  = p1_addr_reg;
                    dcache_wdata = p1_wdata_reg;
                    dcache_wstrb = p1_wstrb_reg;
                end
            end
            default: begin
            end
        endcase
    end

    // P1 signal
    always_ff @(posedge clk) begin
        if (cpu_flush & state == STORE_COMMIT_WAIT) begin
            p1_cpu_store <= 0;
            p1_valid_reg <= 0;
            p1_addr_reg  <= 0;
            p1_wdata_reg <= 0;
            p1_wstrb_reg <= 0;
        end else if (cpu_valid & ~cpu_flush) begin
            p1_cpu_store <= cpu_store;
            p1_valid_reg <= cpu_valid;
            p1_addr_reg  <= cpu_addr;
            p1_wdata_reg <= cpu_wdata;
            p1_wstrb_reg <= cpu_wstrb;
        end else if (dcache_ready) begin
            p1_cpu_store <= 0;
            p1_valid_reg <= 0;
            p1_addr_reg  <= 0;
            p1_wdata_reg <= 0;
            p1_wstrb_reg <= 0;
        end
    end

    assign cpu_ready = state == IDLE & (~p1_valid_reg | dcache_ready);
    assign cpu_rdata = dcache_rdata;
    assign cpu_data_valid = dcache_ready;

endmodule
