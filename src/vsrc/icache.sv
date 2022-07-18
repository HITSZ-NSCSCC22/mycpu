`include "core_config.sv"
`include "TLB/tlb_types.sv"
`include "utils/bram.sv"
`include "utils/lfsr.sv"
`include "axi/axi_interface.sv"
`include "axi/axi_master.sv"

// 1 as valid

module icache
    import core_config::*;
    import tlb_types::*;
(
    input logic clk,
    input logic rst,

    // Read port 1
    input logic rreq_1_i,
    input logic rreq_1_uncached_i,
    input logic [ADDR_WIDTH-1:0] raddr_1_i,
    output logic rreq_1_ack_o,
    output logic rvalid_1_o,
    output logic [ICACHELINE_WIDTH-1:0] rdata_1_o,

    // Read port 2
    input logic rreq_2_i,
    input logic rreq_2_uncached_i,
    input logic [ADDR_WIDTH-1:0] raddr_2_i,
    output logic rreq_2_ack_o,
    output logic rvalid_2_o,
    output logic [ICACHELINE_WIDTH-1:0] rdata_2_o,

    // Frontend Uncache
    input logic invalid_i,  // For some reason, frontend want to reset whole ICache

    // <-> AXI Abitrary
    axi_interface.master m_axi,

    // CACOP
    input logic cacop_i,
    input logic [1:0] cacop_mode_i,
    input logic [ADDR_WIDTH-1:0] cacop_addr_i,
    output cacop_ack_o
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;
    // Parameters
    localparam NWAY = ICACHE_NWAY;
    localparam NSET = ICACHE_NSET;
    localparam OFFSET_WIDTH = $clog2(ICACHELINE_WIDTH / 8);
    localparam NSET_WIDTH = $clog2(NSET);
    localparam NWAY_WIDTH = $clog2(NWAY);
    localparam TAG_WIDTH = ADDR_WIDTH - NSET_WIDTH - OFFSET_WIDTH;

    // AXI
    logic [ADDR_WIDTH-1:0] axi_addr_o;
    logic axi_rreq_o;
    logic axi_rdy_i;
    logic axi_rvalid_i;
    logic axi_rlast_i;
    logic axi_uncached_o;
    assign axi_rlast_i = axi_rvalid_i;
    logic [AXI_DATA_WIDTH-1:0] axi_data_i;

    // States
    enum int {
        IDLE,
        REFILL_1_REQ,
        REFILL_1_WAIT,
        REFILL_2_REQ,
        REFILL_2_WAIT,
        INVALID,  // Reset all tag ram to 0
        CACOP_INVALID_1,
        CACOP_INVALID_2
    }
        state, next_state;

    // Invalid controls
    logic [$clog2(NSET)-1:0] invalid_cnt;
    logic invalid_done;

    // Random number generator
    // Use 16bits to ensure randomness
    logic [15:0] random_r;

    // BRAM signals
    logic [NWAY-1:0][1:0][ICACHELINE_WIDTH-1:0] data_bram_rdata;
    logic [NWAY-1:0][1:0][ICACHELINE_WIDTH-1:0] data_bram_wdata;
    logic [NWAY-1:0][1:0][$clog2(NSET)-1:0] data_bram_addr;
    logic [NWAY-1:0][1:0] data_bram_we;
    logic [NWAY-1:0][1:0] data_bram_en;

    // Tag bram 
    // {1bit valid, 20bits tag}
    localparam TAG_BRAM_WIDTH = TAG_WIDTH + 1;
    logic [NWAY-1:0][1:0][TAG_BRAM_WIDTH-1:0] tag_bram_rdata;
    logic [NWAY-1:0][1:0][TAG_BRAM_WIDTH-1:0] tag_bram_wdata;
    logic [NWAY-1:0][1:0][$clog2(NSET)-1:0] tag_bram_addr;
    logic [NWAY-1:0][1:0] tag_bram_we;
    logic [NWAY-1:0][1:0] tag_bram_en;

    // P1 signal
    logic miss_1_pulse, miss_2_pulse, miss_1_r, miss_2_r, miss_1, miss_2;  // miss signal
    logic p1_rreq_1, p1_rreq_2, p1_rreq_1_uncached, p1_rreq_2_uncached;  // P1 rreq reg
    logic [ADDR_WIDTH-1:0] p1_raddr_1, p1_raddr_2;  // P1 raddr reg
    logic [1:0] hit;
    logic [NWAY-1:0][1:0] tag_hit;  // P1 hit signal
    logic axi_rvalid_delay_1;
    logic [2:0][32-1:0] axi_data_buffer;
    logic [ICACHELINE_WIDTH-1:0] cacheline;
    logic [1:0] axi_burst_cnt;

    // CACOP
    logic cacop_op_mode0, cacop_op_mode1, cacop_op_mode2;
    logic [NWAY_WIDTH-1:0] cacop_way;
    logic [NSET_WIDTH-1:0] cacop_index;

    // AXI rvalid delay
    always_ff @(posedge clk) begin
        axi_rvalid_delay_1 <= axi_rvalid_i;
    end
    // Invalid control
    assign invalid_done = invalid_cnt == {$clog2(NSET) {1'b1}};
    always_ff @(posedge clk) begin
        if (rst) invalid_cnt <= 0;
        else if (state == IDLE) invalid_cnt <= 0;
        else if (state == INVALID) invalid_cnt <= invalid_cnt + 1;
    end

    // CACOP control
    assign cacop_ack_o = state == CACOP_INVALID_2;
    assign cacop_op_mode0 = cacop_i & cacop_mode_i == 2'b00;
    assign cacop_op_mode1 = cacop_i & cacop_mode_i == 2'b01;
    assign cacop_op_mode2 = cacop_i & cacop_mode_i == 2'b10;
    assign cacop_way = cacop_addr_i[$clog2(NWAY)-1:0];
    assign cacop_index = cacop_addr_i[$clog2(
        ICACHELINE_WIDTH/8
    )+$clog2(
        NSET
    )-1:$clog2(
        ICACHELINE_WIDTH/8
    )];




    // State machine
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= INVALID;  // Reset into invalid
        end else begin
            state <= next_state;
        end
    end

    always_comb begin : transition_comb
        case (state)
            IDLE: begin
                if (invalid_i) next_state = INVALID;
                else if (cacop_i) next_state = CACOP_INVALID_1;
                else if (miss_1) next_state = REFILL_1_REQ;
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
                if (axi_rvalid_i & axi_rlast_i) begin
                    if (miss_2) next_state = REFILL_2_REQ;
                    else next_state = IDLE;
                end else next_state = REFILL_1_WAIT;
            end
            REFILL_2_WAIT: begin
                if (axi_rvalid_i & axi_rlast_i) next_state = IDLE;
                else next_state = REFILL_2_WAIT;
            end
            INVALID: begin
                if (invalid_done) next_state = IDLE;
                else next_state = INVALID;
            end
            CACOP_INVALID_1: next_state = CACOP_INVALID_2;
            CACOP_INVALID_2: next_state = IDLE;
            default: begin
                next_state = IDLE;
            end
        endcase
    end


    /////////////////////////////////////////////////
    // PO, query BRAM
    ////////////////////////////////////////////////


    // RREQ ack
    // hit or next_state is REQ
    // if next_state is not REQ, means something important is going on, do not accept rreq
    assign rreq_1_ack_o = state == IDLE & rreq_1_i & (~miss_1 | next_state == REFILL_1_REQ);
    assign rreq_2_ack_o = state == IDLE & rreq_2_i & (~miss_2 | next_state == REFILL_2_REQ);

    // BRAM input signals
    // Addr & EN
    always_comb begin : bram_addr_gen
        // Default all 0
        for (integer i = 0; i < NWAY; i++) begin
            tag_bram_addr[i][0] = 0;
            data_bram_addr[i][0] = 0;
            tag_bram_addr[i][1] = 0;
            data_bram_addr[i][1] = 0;
            tag_bram_en[i] = 0;
            data_bram_en[i] = 0;
        end
        case (state)
            IDLE: begin
                for (integer i = 0; i < NWAY; i++) begin
                    // Port 1
                    if (rreq_1_i) begin
                        tag_bram_en[i][0] = 1;
                        data_bram_en[i][0] = 1;
                        tag_bram_addr[i][0] = raddr_1_i[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                        data_bram_addr[i][0] = raddr_1_i[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                    end else if (miss_1) begin
                        tag_bram_addr[i][0]  = p1_raddr_1[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                        data_bram_addr[i][0] = p1_raddr_1[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                    end
                    // Port 2
                    if (rreq_2_i) begin
                        tag_bram_en[i][1] = 1;
                        data_bram_en[i][1] = 1;
                        tag_bram_addr[i][1] = raddr_2_i[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                        data_bram_addr[i][1] = raddr_2_i[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                    end else if (miss_2) begin
                        tag_bram_addr[i][1]  = p1_raddr_2[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                        data_bram_addr[i][1] = p1_raddr_2[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                    end
                end
            end
            REFILL_1_REQ, REFILL_2_REQ, REFILL_1_WAIT, REFILL_2_WAIT: begin
                for (integer i = 0; i < NWAY; i++) begin
                    tag_bram_en[i][0]  = axi_rvalid_i & axi_rlast_i;
                    tag_bram_en[i][1]  = axi_rvalid_i & axi_rlast_i;
                    data_bram_en[i][0] = axi_rvalid_i & axi_rlast_i;
                    data_bram_en[i][1] = axi_rvalid_i & axi_rlast_i;
                    // Port 1
                    if (miss_1) begin
                        tag_bram_addr[i][0]  = p1_raddr_1[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                        data_bram_addr[i][0] = p1_raddr_1[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                    end else begin
                        tag_bram_addr[i][0]  = raddr_1_i[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                        data_bram_addr[i][0] = raddr_1_i[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                    end
                    // Port 2
                    if (miss_2) begin
                        tag_bram_addr[i][1]  = p1_raddr_2[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                        data_bram_addr[i][1] = p1_raddr_2[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                    end else begin
                        tag_bram_addr[i][1]  = raddr_2_i[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                        data_bram_addr[i][1] = raddr_2_i[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                    end
                end
            end
            CACOP_INVALID_1: begin
                for (integer i = 0; i < NWAY; i++) begin
                    tag_bram_en[i][0]  = 0;
                    tag_bram_en[i][1]  = 0;
                    data_bram_en[i][0] = 0;
                    data_bram_en[i][1] = 0;
                    if (cacop_way == i[$clog2(NWAY)-1:0] | cacop_op_mode2) begin
                        tag_bram_addr[i][1] = cacop_index;
                        tag_bram_en[i][1]   = 1;
                    end
                end
            end
            INVALID: begin
                for (integer i = 0; i < NWAY; i++) begin
                    tag_bram_en[i][1]   = 0;
                    data_bram_en[i][0]  = 0;
                    data_bram_en[i][1]  = 0;
                    tag_bram_addr[i][0] = invalid_cnt;
                    tag_bram_en[i][0]   = 1;
                end
            end
            default: begin
            end
        endcase
    end

    // Data 
    always_comb begin : bram_data_gen
        for (integer i = 0; i < NWAY; i++) begin
            tag_bram_we[i] = 0;
            tag_bram_wdata[i] = 0;
            data_bram_we[i] = 0;
            data_bram_wdata[i] = 0;
        end
        case (state)
            REFILL_1_WAIT: begin
                for (integer i = 0; i < NWAY; i++) begin
                    if (i[0] == random_r[0]) begin
                        if (axi_rvalid_i & axi_rlast_i & ~p1_rreq_1_uncached) begin
                            tag_bram_we[i][0] = 1;
                            tag_bram_wdata[i][0] = {
                                1'b1, p1_raddr_1[ADDR_WIDTH-1:ADDR_WIDTH-TAG_WIDTH]
                            };
                            data_bram_we[i][0] = 1;
                            data_bram_wdata[i][0] = cacheline;
                        end
                    end
                end
            end
            REFILL_2_WAIT: begin
                for (integer i = 0; i < NWAY; i++) begin
                    if (i[0] == random_r[0]) begin
                        if (axi_rvalid_i & axi_rlast_i & ~p1_rreq_2_uncached) begin
                            tag_bram_we[i][1] = 1;
                            tag_bram_wdata[i][1] = {
                                1'b1, p1_raddr_2[ADDR_WIDTH-1:ADDR_WIDTH-TAG_WIDTH]
                            };
                            data_bram_we[i][1] = 1;
                            data_bram_wdata[i][1] = cacheline;
                        end
                    end
                end
            end
            CACOP_INVALID_1: begin
                for (integer i = 0; i < NWAY; i++) begin
                    if (cacop_way == i[$clog2(NWAY)-1:0] | cacop_op_mode2) begin
                        tag_bram_we[i][1] = 1;
                        tag_bram_wdata[i][1] = 0;
                    end
                end
            end
            INVALID: begin
                for (integer i = 0; i < NWAY; i++) begin
                    tag_bram_we[i][0] = 1;
                    tag_bram_wdata[i][0] = 0;
                end
            end
        endcase

    end



    ////////////////////////////////////////////////////
    // P1
    ///////////////////////////////////////////////////

    // Miss signal
    assign miss_1_pulse = p1_rreq_1 & ~hit[0] & (state == IDLE);
    assign miss_2_pulse = p1_rreq_2 & ~hit[1] & (state == IDLE);
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
                    if (axi_rvalid_i & axi_rlast_i) miss_1_r <= 0;
                end
                REFILL_2_WAIT: begin
                    if (axi_rvalid_i & axi_rlast_i) miss_2_r <= 0;
                end
                CACOP_INVALID_1, CACOP_INVALID_2: begin
                    miss_1_r <= 0;
                    miss_2_r <= 0;
                end
                default: begin
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (rvalid_1_o) begin
            p1_rreq_1 <= 0;
            p1_rreq_1_uncached <= 0;
            p1_raddr_1 <= 0;
        end else if (rreq_1_ack_o) begin
            p1_rreq_1 <= rreq_1_i;
            p1_rreq_1_uncached <= rreq_1_uncached_i;
            p1_raddr_1 <= raddr_1_i;
        end
        if (rvalid_2_o) begin
            p1_rreq_2 <= 0;
            p1_rreq_2_uncached <= 0;
            p1_raddr_2 <= 0;
        end else if (rreq_2_ack_o) begin
            p1_rreq_2 <= rreq_2_i;
            p1_rreq_2_uncached <= rreq_2_uncached_i;
            p1_raddr_2 <= raddr_2_i;
        end
    end

    // Hit signal
    always_comb begin
        for (integer i = 0; i < NWAY; i++) begin
            tag_hit[i][0] = tag_bram_rdata[i][0][TAG_WIDTH-1:0] == p1_raddr_1[ADDR_WIDTH-1:ADDR_WIDTH-TAG_WIDTH] && tag_bram_rdata[i][0][TAG_WIDTH];
            tag_hit[i][1] = tag_bram_rdata[i][1][TAG_WIDTH-1:0] == p1_raddr_2[ADDR_WIDTH-1:ADDR_WIDTH-TAG_WIDTH] && tag_bram_rdata[i][1][TAG_WIDTH];
        end
    end

    // IDLE & WAIT can return rvalid_o, but REQ must not return rvalid_o
    assign rvalid_1_o = (p1_rreq_1 && (state == REFILL_1_WAIT && axi_rvalid_i && axi_rlast_i) | (state == IDLE && hit[0]));
    assign rvalid_2_o = (p1_rreq_2 && (state == REFILL_2_WAIT && axi_rvalid_i && axi_rlast_i) | (state == IDLE && hit[1]));
    // Generate read output
    always_comb begin
        hit[0] = 0;
        rdata_1_o = cacheline;
        hit[1] = 0;
        rdata_2_o = cacheline;
        for (integer i = 0; i < NWAY; i++) begin
            if (tag_hit[i][0]) begin
                hit[0] = 1;
                rdata_1_o = data_bram_rdata[i][0];
            end
            if (tag_hit[i][1]) begin
                hit[1] = 1;
                rdata_2_o = data_bram_rdata[i][1];
            end
        end
    end

    // AXI handshake
    // Read request to AXI Controller
    assign cacheline = axi_data_i;
    // always_ff @(posedge clk) begin
    //     if (rst) axi_burst_cnt <= 0;
    //     else if (axi_rvalid_i & axi_rlast_i) axi_burst_cnt <= 0;
    //     else if (axi_rvalid_i) axi_burst_cnt <= axi_burst_cnt + 1;
    // end
    // always_ff @(posedge clk) begin
    //     if (rst) axi_data_buffer <= 0;
    //     else if (axi_rvalid_i & axi_rlast_i) axi_data_buffer <= 0;
    //     else if (axi_rvalid_i) axi_data_buffer[axi_burst_cnt] <= axi_data_i;
    // end
    always_comb begin
        case (state)
            REFILL_1_REQ: begin
                axi_rreq_o = miss_1;
                axi_addr_o = miss_1 ? p1_raddr_1 : 0;
                axi_uncached_o = miss_1 ? p1_rreq_1_uncached : 0;
            end
            REFILL_2_REQ: begin
                axi_rreq_o = miss_2;
                axi_addr_o = miss_2 ? p1_raddr_2 : 0;
                axi_uncached_o = miss_2 ? p1_rreq_2_uncached : 0;
            end
            default: begin
                axi_rreq_o = 0;
                axi_addr_o = 0;
                axi_uncached_o = 0;
            end
        endcase
    end

    // LSFR
    lfsr #(
        .WIDTH(16)
    ) u_lfsr (
        .clk  (clk),
        .rst  (rst),
        .en   (1'b1),
        .value(random_r)
    );

    axi_master #(
        .ID(1)
    ) u_axi_master (
        .clk        (clk),
        .rst        (rst),
        .m_axi      (m_axi),
        .new_request(axi_rreq_o),
        .uncached   (axi_uncached_o),
        .we         (1'b0),
        .addr       (axi_addr_o),
        .size       (3'b100),
        .data_in    (0),
        .wstrb      (0),
        .ready_out  (axi_rdy_i),
        .valid_out  (axi_rvalid_i),
        .data_out   (axi_data_i)
    );


    // BRAM instantiation
    generate
        for (genvar i = 0; i < NWAY; i++) begin : bram_ip
`ifdef BRAM_IP
            bram_icache_tag_ram u_tag_bram (
                .clka (clk),
                .clkb (clk),
                .ena  (tag_bram_en[i][0]),
                .enb  (tag_bram_en[i][1]),
                .wea  (tag_bram_we[i][0]),
                .web  (tag_bram_we[i][1]),
                .dina (tag_bram_wdata[i][0]),
                .addra(tag_bram_addr[i][0]),
                .douta(tag_bram_rdata[i][0]),
                .dinb (tag_bram_wdata[i][1]),
                .addrb(tag_bram_addr[i][1]),
                .doutb(tag_bram_rdata[i][1])
            );
            bram_icache_data_ram u_data_bram (
                .clka (clk),
                .clkb (clk),
                .ena  (data_bram_en[i][0]),
                .enb  (data_bram_en[i][1]),
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
                .DATA_WIDTH     (TAG_BRAM_WIDTH),
                .DATA_DEPTH_EXP2($clog2(NSET))
            ) u_tag_bram (
                .clk  (clk),
                .ena  (tag_bram_en[i][0]),
                .enb  (tag_bram_en[i][1]),
                .wea  (tag_bram_we[i][0]),
                .web  (tag_bram_we[i][1]),
                .dina (tag_bram_wdata[i][0]),
                .addra(tag_bram_addr[i][0]),
                .douta(tag_bram_rdata[i][0]),
                .dinb (tag_bram_wdata[i][1]),
                .addrb(tag_bram_addr[i][1]),
                .doutb(tag_bram_rdata[i][1])
            );
            bram #(
                .DATA_WIDTH     (ICACHELINE_WIDTH),
                .DATA_DEPTH_EXP2($clog2(NSET))
            ) u_data_bram (
                .clk  (clk),
                .ena  (data_bram_en[i][0]),
                .enb  (data_bram_en[i][1]),
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

endmodule
