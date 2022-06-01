
`include "utils/bram.sv"
`include "utils/lfsr.sv"

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

    // BRAM index gen
    always_comb begin : bram_addr_gen
        for (integer i = 0; i < NWAY; i++) begin
            if (miss_1 | (state == REFILL_1_WAIT & ~rvalid_1)) begin
                tag_bram_addr[i][0]  = p1_raddr_1[11:4];
                data_bram_addr[i][0] = p1_raddr_1[11:4];
            end else if (rreq_1_i) begin
                tag_bram_addr[i][0]  = raddr_1_i[11:4];
                data_bram_addr[i][0] = raddr_1_i[11:4];
            end else begin
                tag_bram_addr[i][0]  = 0;
                data_bram_addr[i][0] = 0;
            end
        end
        for (integer i = 0; i < NWAY; i++) begin
            if (miss_2 | (state == REFILL_2_WAIT & ~rvalid_2)) begin
                tag_bram_addr[i][1]  = p1_raddr_2[11:4];
                data_bram_addr[i][1] = p1_raddr_2[11:4];
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
    logic p1_rreq_1, p1_rreq_2;
    logic [ADDR_WIDTH-1:0] p1_raddr_1, p1_raddr_2;
    always_ff @(posedge clk) begin
        if (rvalid_1_o | ~p1_rreq_1) begin
            p1_rreq_1  <= rreq_1_i;
            p1_raddr_1 <= raddr_1_i;
        end
        if (rvalid_2_o | ~p1_rreq_2) begin
            p1_rreq_2  <= rreq_2_i;
            p1_raddr_2 <= raddr_2_i;
        end
    end


    logic [NWAY-1:0][1:0] tag_hit;
    always_comb begin
        for (integer i = 0; i < NWAY; i++) begin
            tag_hit[i][0] = tag_bram_rdata[i][0][19:0] == p1_raddr_1[ADDR_WIDTH-1:ADDR_WIDTH-20] && tag_bram_rdata[i][0][20];
            tag_hit[i][1] = tag_bram_rdata[i][1][19:0] == p1_raddr_2[ADDR_WIDTH-1:ADDR_WIDTH-20] && tag_bram_rdata[i][1][20];
        end
    end

    logic rvalid_1, rvalid_2;
    assign rvalid_1_o = rvalid_1 && p1_rreq_1;
    assign rvalid_2_o = rvalid_2 && p1_rreq_2;
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
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end


    logic miss_1_pulse, miss_2_pulse, miss_1_r, miss_2_r, miss_1, miss_2;
    assign miss_1_pulse = p1_rreq_1 & ~rvalid_1 & (state == IDLE);
    assign miss_2_pulse = p1_rreq_2 & ~rvalid_2 & (state == IDLE);
    assign miss_1 = miss_1_pulse | miss_1_r;
    assign miss_2 = miss_2_pulse | miss_2_r;
    always_ff @(posedge clk) begin
        if (rst) begin
            miss_1_r <= 0;
            miss_2_r <= 0;
        end else begin
            case (state)
                IDLE: begin
                    miss_1_r <= miss_1_pulse;
                    miss_2_r <= miss_2_pulse;
                end
                REFILL_1_WAIT: begin
                    if (axi_rvalid_i) miss_1_r <= 0;
                end
                REFILL_2_WAIT: begin
                    if (axi_rvalid_i) miss_2_r <= 0;
                end
                default: begin
                end
            endcase
        end
    end



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
                    if (miss_2) next_state = REFILL_2_REQ;
                    else next_state = IDLE;
                end else next_state = REFILL_1_WAIT;
            end
            REFILL_2_WAIT: begin
                if (rvalid_2) begin
                    next_state = IDLE;
                end else next_state = REFILL_2_WAIT;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Read request to AXI Controller
    always_comb begin
        case (state)
            REFILL_1_REQ, REFILL_1_WAIT: begin
                axi_rreq_o = miss_1 ? 1 : 0;
                axi_addr_o = miss_1 ? p1_raddr_1 : 0;
            end
            REFILL_2_REQ, REFILL_2_WAIT: begin
                axi_rreq_o = miss_2 ? 1 : 0;
                axi_addr_o = miss_2 ? p1_raddr_2 : 0;
            end
            default: begin
                axi_rreq_o = 0;
                axi_addr_o = 0;
            end
        endcase
    end

    // Refill write BRAM
    logic [2:0] random_r;
    lfsr #(
        .WIDTH(3)
    ) u_lfsr (
        .clk  (clk),
        .rst  (rst),
        .en   (1'b1),
        .value(random_r)
    );
    always_comb begin
        for (integer i = 0; i < NWAY; i++) begin
            tag_bram_we[i] = 0;
            tag_bram_wdata[i] = 0;
            data_bram_we[i] = 0;
            data_bram_wdata[i] = 0;
            if (i[0] == random_r[0]) begin
                // write this way
                if (state == REFILL_1_WAIT && axi_rvalid_i) begin
                    tag_bram_we[i][0] = 1;
                    tag_bram_wdata[i][0] = {1'b1, p1_raddr_1[31:12]};
                    data_bram_we[i][0] = 1;
                    data_bram_wdata[i][0] = axi_data_i;
                end
                if (state == REFILL_2_WAIT && axi_rvalid_i) begin
                    tag_bram_we[i][1] = 1;
                    tag_bram_wdata[i][1] = {1'b1, p1_raddr_2[31:12]};
                    data_bram_we[i][1] = 1;
                    data_bram_wdata[i][1] = axi_data_i;
                end
            end
        end
    end

endmodule
