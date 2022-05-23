
`include "utils/bram.sv"

module icache #(
    parameter NSET = 256,
    parameter NWAY = 2,
    parameter CACHELINE_WIDTH = 128,
    parameter ADDR_WIDTH = 32
) (
    input logic clk,
    input logic rst,

    // Read port 1
    input logic rreq_1_i,
    input logic [ADDR_WIDTH-1:0] raddr_1_i,
    output logic rvalid_1_o,
    output logic [CACHELINE_WIDTH-1:0] rdata_1_o,

    // Read port 2
    input logic rreq_2_i,
    input logic [ADDR_WIDTH-1:0] raddr_2_i,
    output logic rvalid_2_o,
    output logic [CACHELINE_WIDTH-1:0] rdata_2_o,

    // <-> AXI Controller
    output logic [ADDR_WIDTH-1:0] axi_addr_o,
    output logic axi_rreq_o,
    input logic axi_rdy_i,
    input logic axi_rvalid_i,
    input logic [1:0] axi_rlast_i,
    input logic [CACHELINE_WIDTH-1:0] axi_data_i
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;


    /////////////////////////////////////////////////
    // PO, query BRAM
    ////////////////////////////////////////////////

    logic [NWAY-1:0][1:0][CACHELINE_WIDTH-1:0] data_bram_rdata;
    logic [NWAY-1:0][1:0][CACHELINE_WIDTH-1:0] data_bram_wdata;
    logic [NWAY-1:0][1:0][$clog2(NSET)-1:0] data_bram_addr;
    logic [NWAY-1:0][1:0] data_bram_we;

    // Tag bram 
    // {1bit valid, 20bits tag}
    localparam TAG_BRAM_WIDTH = 21;
    logic [NWAY-1:0][1:0][TAG_BRAM_WIDTH-1:0] tag_bram_rdata;
    logic [NWAY-1:0][1:0][TAG_BRAM_WIDTH-1:0] tag_bram_wdata;
    logic [NWAY-1:0][1:0][$clog2(NSET)-1:0] tag_bram_addr;
    logic [NWAY-1:0][1:0] tag_bram_we;

    generate
        for (genvar i = 0; i < NWAY; i++) begin : tag_bram

`ifdef BRAM_IP
            bram_icache_tag_ram u_bram (
                .clka (clk),
                .clkb (clk),
                .wea  (tag_bram_we[i][0]),
                .web  (tag_bram_we[i][1]),
                .dina (tag_bram_wdata[i][0]),
                .addra(tag_bram_addr[i][0]),
                .douta(tag_bram_rdata[i][0]),
                .dinb (tag_bram_wdata[i][1]),
                .addrb(tag_bram_addr[i][1]),
                .doutb(tag_bram_rdata[i][1])
            );
`else

            bram #(
                .DATA_WIDTH     (TAG_BRAM_WIDTH),
                .DATA_DEPTH_EXP2(10)
            ) u_bram (
                .clk  (clk),
                .wea  (tag_bram_we[i][0]),
                .web  (tag_bram_we[i][1]),
                .dina (tag_bram_wdata[i][0]),
                .addra(tag_bram_addr[i][0]),
                .douta(tag_bram_rdata[i][0]),
                .dinb (tag_bram_wdata[i][1]),
                .addrb(tag_bram_addr[i][1]),
                .doutb(tag_bram_rdata[i][1])
            );
`endif
        end
    endgenerate
    generate
        for (genvar i = 0; i < NWAY; i++) begin : data_bram
`ifdef BRAM_IP
            bram_icache_data_ram u_bram (
                .clka (clk),
                .clkb (clk),
                .wea  (data_bram_we[i][0]),
                .web  (data_bram_we[i][1]),
                .dina (data_bram_wdata[i][0]),
                .addra(data_bram_addr[i][0]),
                .douta(data_bram_rdata[i][0]),
                .dinb (data_bram_wdata[i][1]),
                .addrb(data_bram_addr[i][1]),
                .doutb(data_bram_rdata[i][1])
            );
`else
            bram #(
                .DATA_WIDTH     (128),
                .DATA_DEPTH_EXP2(10)
            ) u_bram (
                .clk  (clk),
                .wea  (data_bram_we[i][0]),
                .web  (data_bram_we[i][1]),
                .dina (data_bram_wdata[i][0]),
                .addra(data_bram_addr[i][0]),
                .douta(data_bram_rdata[i][0]),
                .dinb (data_bram_wdata[i][1]),
                .addrb(data_bram_addr[i][1]),
                .doutb(data_bram_rdata[i][1])
            );
`endif
        end
    endgenerate

    // Cache addr 
    always_comb begin : cache_addr_gen
        for (integer i = 0; i < NWAY; i++) begin
            if (tag_bram_we[i][0]) begin
                tag_bram_addr[i][0]  = raddr_1_delay1[11:4];
                data_bram_addr[i][0] = raddr_1_delay1[11:4];
            end else if (rreq_1_i) begin
                tag_bram_addr[i][0]  = raddr_1_i[11:4];
                data_bram_addr[i][0] = raddr_1_i[11:4];
            end else begin  // TODO: write
                tag_bram_addr[i][0]  = 0;
                data_bram_addr[i][0] = 0;
            end
        end
        for (integer i = 0; i < NWAY; i++) begin
            if (tag_bram_we[i][1]) begin
                tag_bram_addr[i][1]  = raddr_2_delay1[11:4];
                data_bram_addr[i][1] = raddr_2_delay1[11:4];
            end else if (rreq_2_i) begin
                tag_bram_addr[i][1]  = raddr_2_i[11:4];
                data_bram_addr[i][1] = raddr_2_i[11:4];
            end else begin
                tag_bram_addr[i][1]  = 0;
                data_bram_addr[i][1] = 0;
            end
        end
    end



    ////////////////////////////////////////////////////
    // P1, output gen
    ///////////////////////////////////////////////////

    // Input reg
    logic rreq_1_delay1, rreq_2_delay1;
    logic [ADDR_WIDTH-1:0] raddr_1_delay1, raddr_2_delay1;
    always_ff @(posedge clk) begin
        rreq_1_delay1 <= rreq_1_i;
        rreq_2_delay1 <= rreq_2_i;
        if (rreq_1_i & (rvalid_1 | state == IDLE)) raddr_1_delay1 <= raddr_1_i;
        if (rreq_2_i & (rvalid_2 | state == IDLE)) raddr_2_delay1 <= raddr_2_i;
    end


    logic [NWAY-1:0][1:0] tag_hit;
    always_comb begin
        for (integer i = 0; i < NWAY; i++) begin
            tag_hit[i][0] = tag_bram_rdata[i][0][19:0] == raddr_1_delay1[ADDR_WIDTH-1:ADDR_WIDTH-20] && tag_bram_rdata[i][0][20];
            tag_hit[i][1] = tag_bram_rdata[i][1][19:0] == raddr_2_delay1[ADDR_WIDTH-1:ADDR_WIDTH-20] && tag_bram_rdata[i][1][20];
        end
    end

    logic rvalid_1, rvalid_2;
    assign rvalid_1_o = rvalid_1 && (rreq_1_delay1 || state == REFILL_1_WAIT);
    assign rvalid_2_o = rvalid_2 && (rreq_2_delay1 || state == REFILL_2_WAIT);
    // Generate read output
    always_comb begin
        rvalid_1  = 0;
        rdata_1_o = 0;
        rvalid_2  = 0;
        rdata_2_o = 0;
        for (integer i = 0; i < NWAY; i++) begin
            if (tag_hit[i][0]) begin
                rvalid_1  = 1;
                rdata_1_o = data_bram_rdata[i][0];
            end
            if (tag_hit[i][1]) begin
                rvalid_2  = 1;
                rdata_2_o = data_bram_rdata[i][1];
            end
        end
    end


    // Refill state machine
    enum int {
        IDLE,
        REFILL_1_REQ,
        REFILL_1_WAIT,
        REFILL_2_REQ,
        REFILL_2_WAIT
    }
        state, next_state;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end


    logic miss_1, miss_2;
    assign miss_1 = rreq_1_delay1 & ~rvalid_1_o;
    assign miss_2 = rreq_2_delay1 & ~rvalid_2_o;

    always_comb begin : transition_comb
        case (state)
            IDLE: begin
                if (miss_1) next_state = REFILL_1_REQ;
                else if (miss_2) next_state = REFILL_2_REQ;
                else next_state = IDLE;
            end
            REFILL_1_REQ: begin
                if (axi_rdy_i) next_state = REFILL_1_WAIT;
                else next_state = REFILL_1_REQ;
            end
            REFILL_2_REQ: begin
                if (axi_rdy_i) next_state = REFILL_2_WAIT;
                else next_state = REFILL_2_REQ;
            end
            REFILL_1_WAIT: begin
                if (rvalid_1) begin
                    // if (miss_2) next_state = REFILL_2_REQ;
                    // else 
                    next_state = IDLE;
                end else next_state = REFILL_1_WAIT;
            end
            REFILL_2_WAIT: begin
                if (rvalid_2) begin
                    // if (miss_1) next_state = REFILL_1_REQ;
                    // else 
                    next_state = IDLE;
                end else next_state = REFILL_2_WAIT;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // State machine output
    always_comb begin
        // Default value 
        axi_rreq_o = 0;
        axi_addr_o = 0;
        case (state)
            REFILL_1_REQ, REFILL_1_WAIT: begin
                axi_rreq_o = 1;
                axi_addr_o = raddr_1_delay1;
            end
            REFILL_2_REQ, REFILL_2_WAIT: begin
                axi_rreq_o = 1;
                axi_addr_o = raddr_2_delay1;
            end
            default: begin
            end
        endcase
    end

    // Refill write BRAM
    logic random_r;
    always_ff @(posedge clk) begin
        random_r <= ~random_r;
    end
    always_comb begin
        for (integer i = 0; i < NWAY; i++) begin
            tag_bram_we[i] = 0;
            tag_bram_wdata[i] = 0;
            data_bram_we[i] = 0;
            data_bram_wdata[i] = 0;
            if (i[0] == random_r) begin
                // write this way
                if (state == REFILL_1_WAIT && axi_rvalid_i) begin
                    tag_bram_we[i][0] = 1;
                    tag_bram_wdata[i][0] = {1'b1, raddr_1_delay1[31:12]};
                    data_bram_we[i][0] = 1;
                    data_bram_wdata[i][0] = axi_data_i;
                end
                if (state == REFILL_2_WAIT && axi_rvalid_i) begin
                    tag_bram_we[i][1] = 1;
                    tag_bram_wdata[i][1] = {1'b1, raddr_2_delay1[31:12]};
                    data_bram_we[i][1] = 1;
                    data_bram_wdata[i][1] = axi_data_i;
                end
            end
        end
    end

endmodule
