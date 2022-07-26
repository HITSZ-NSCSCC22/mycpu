`include "Cache/uncache_channel.sv"

module LSU #(
    parameter FE_ADDR_W   = 32,       //Address width - width of the Master's entire access address (including the LSBs that are discarded, but discarding the Controller's)
    parameter FE_DATA_W = 32,
    parameter FE_NBYTES = FE_DATA_W / 8
) (
    input logic clk,
    input logic rst,

    input logic cpu_pre_valid,
    input logic cpu_store_req,
    input logic [FE_ADDR_W-1:0] cpu_vaddr,

    input logic cpu_valid,
    input logic cpu_uncached,
    input logic [FE_ADDR_W-1:0] cpu_instr_pc,
    input logic [2:0] cpu_req_type,
    input logic [FE_ADDR_W-1:0] cpu_addr,
    input logic [FE_DATA_W-1:0] cpu_wdata,
    input logic [FE_NBYTES-1:0] cpu_wstrb,
    output logic uncache_ready_o,
    output logic cpu_ready,

    // next cycle
    output logic [FE_DATA_W-1:0] cpu_rdata,
    output logic cpu_data_valid,

    // from wb
    input logic cpu_flush,
    input logic cpu_store_commit,

    // Cache
    output logic dcache_pre_valid,
    output logic [FE_ADDR_W-1:0] dcache_vaddr,

    output logic dcache_valid,
    output logic [FE_ADDR_W-1:0] dcache_instr_pc,
    output logic [FE_ADDR_W-1:0] dcache_addr,
    output logic [FE_DATA_W-1:0] dcache_wdata,
    output logic [FE_NBYTES-1:0] dcache_wstrb,
    input logic [FE_DATA_W-1:0] dcache_rdata,
    input logic dcache_ready,

    // Uncache AXI
    axi_interface.master uncache_axi
);
    logic cpu_store;

    // Uncache channel
    logic uncache_valid;
    logic [2:0] uncache_req_type;
    logic [FE_ADDR_W-1:0] uncache_addr;
    logic [FE_DATA_W-1:0] uncache_wdata;
    logic [FE_NBYTES-1:0] uncache_wstrb;
    logic [FE_DATA_W-1:0] uncache_rdata;
    logic uncache_ready;
    logic uncache_data_ok;

    // P1 signal
    logic p1_valid_reg;
    logic p1_cpu_store;
    logic p1_uncache;
    logic [2:0] p1_req_type;
    logic [FE_ADDR_W-1:0] p1_pc_reg;
    logic [FE_ADDR_W-1:0] p1_addr_reg;
    logic [FE_DATA_W-1:0] p1_wdata_reg;
    logic [FE_NBYTES-1:0] p1_wstrb_reg;


    enum integer {
        IDLE,
        REFILL_WAIT,
        UNCACHE_REQ_SEND,
        UNCACHE_REQ_WAIT
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
                if (cpu_flush) next_state = IDLE;
                else if (p1_valid_reg & ~p1_uncache & ~dcache_ready) next_state = REFILL_WAIT;
                else if (cpu_valid & cpu_uncached) next_state = UNCACHE_REQ_SEND;
                else next_state = IDLE;
            end
            REFILL_WAIT: begin
                if (dcache_ready) next_state = IDLE;
                else next_state = REFILL_WAIT;
            end
            UNCACHE_REQ_SEND: begin
                if (uncache_ready) next_state = UNCACHE_REQ_WAIT;
                else next_state = UNCACHE_REQ_SEND;
            end
            UNCACHE_REQ_WAIT: begin
                if (uncache_data_ok) next_state = IDLE;
                else next_state = UNCACHE_REQ_WAIT;
            end
            default: next_state = IDLE;
        endcase
    end

    assign cpu_store = cpu_store_req;

    // DCache handshake
    always_comb begin
        // Default
        dcache_pre_valid = 0;
        dcache_vaddr = 0;
        dcache_valid = 0;
        dcache_instr_pc = 0;
        dcache_addr = 0;
        dcache_wdata = 0;
        dcache_wstrb = 0;
        case (state)
            IDLE: begin
                if (cpu_pre_valid & ~cpu_flush) begin
                    dcache_pre_valid = cpu_pre_valid;
                    dcache_vaddr = cpu_vaddr;
                end
                // store will be block at ex
                if (cpu_valid & ~cpu_uncached & ~cpu_flush) begin  // Read
                    dcache_valid = cpu_valid;
                    dcache_instr_pc = cpu_instr_pc;
                    dcache_addr = cpu_addr;
                    dcache_wstrb = cpu_wstrb;
                    dcache_wdata = cpu_wdata;
                end else if (~dcache_ready) begin
                    dcache_valid = p1_valid_reg;
                    dcache_instr_pc = p1_pc_reg;
                    dcache_addr = p1_addr_reg;
                    dcache_wstrb = p1_wstrb_reg;
                    dcache_wdata = p1_wdata_reg;
                end
            end
            REFILL_WAIT: begin
                dcache_valid = p1_valid_reg;
                dcache_addr  = p1_addr_reg;
            end
            default: begin
            end
        endcase
    end
    // Uncache handshake
    always_comb begin
        uncache_valid = 0;
        uncache_addr = 0;
        uncache_wdata = 0;
        uncache_wstrb = 0;
        uncache_req_type = 0;
        case (state)
            UNCACHE_REQ_SEND: begin
                uncache_valid = 1;
                uncache_addr = p1_addr_reg;
                uncache_wdata = p1_wdata_reg;
                uncache_wstrb = p1_wstrb_reg;
                uncache_req_type = p1_req_type;
            end
            UNCACHE_REQ_WAIT: begin
                if (~uncache_data_ok) begin
                    uncache_valid = 1;
                    uncache_addr = p1_addr_reg;
                    uncache_wdata = p1_wdata_reg;
                    uncache_wstrb = p1_wstrb_reg;
                    uncache_req_type = p1_req_type;
                end
            end
        endcase
    end

    // P1 signal
    always_ff @(posedge clk) begin
        if (cpu_flush) begin
            p1_req_type  <= 0;
            p1_cpu_store <= 0;
            p1_uncache   <= 0;
            p1_valid_reg <= 0;
            p1_pc_reg    <= 0;
            p1_addr_reg  <= 0;
            p1_wdata_reg <= 0;
            p1_wstrb_reg <= 0;
        end else if (cpu_valid & ~cpu_flush) begin
            p1_req_type  <= cpu_req_type;
            p1_cpu_store <= cpu_store;
            p1_uncache   <= cpu_uncached;
            p1_valid_reg <= cpu_valid;
            p1_pc_reg    <= cpu_instr_pc;
            p1_addr_reg  <= cpu_addr;
            p1_wdata_reg <= cpu_wdata;
            p1_wstrb_reg <= cpu_wstrb;
        end else if (dcache_ready | uncache_data_ok) begin
            p1_req_type  <= 0;
            p1_cpu_store <= 0;
            p1_uncache   <= 0;
            p1_valid_reg <= 0;
            p1_pc_reg    <= 0;
            p1_addr_reg  <= 0;
            p1_wdata_reg <= 0;
            p1_wstrb_reg <= 0;
        end
    end

    assign cpu_ready = state == IDLE & (~p1_valid_reg | dcache_ready);
    assign uncache_ready_o = ~p1_uncache & uncache_ready;
    // CPU handshake
    always_comb begin
        cpu_rdata = 0;
        cpu_data_valid = 0;
        case (state)
            IDLE: begin
                cpu_rdata = dcache_rdata;
                cpu_data_valid = dcache_ready;
            end
            REFILL_WAIT: begin
                cpu_rdata = dcache_rdata;
                cpu_data_valid = dcache_ready;
            end
            UNCACHE_REQ_WAIT: begin
                cpu_rdata = uncache_rdata;
                cpu_data_valid = uncache_data_ok;
            end
        endcase
    end


    uncache_channel u_uncache_channel (
        .clk        (clk),
        .rst        (rst),
        .valid      (uncache_valid),
        .addr       (uncache_addr),
        .req_type   (uncache_req_type),
        .wstrb      (uncache_wstrb),
        .wdata      (uncache_wdata),
        .rdata      (uncache_rdata),
        .cache_ready(uncache_ready),
        .data_ok    (uncache_data_ok),
        .m_axi      (uncache_axi)
    );


endmodule
