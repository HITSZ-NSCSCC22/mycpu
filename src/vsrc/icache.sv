`include "core_config.sv"
`include "TLB/tlb_types.sv"
`include "utils/bram.sv"
`include "utils/lfsr.sv"

module icache
    import core_config::*;
    import tlb_types::*;
#(
    parameter NSET = 256,
    parameter NWAY = 2
) (
    input logic clk,
    input logic rst,

    // Read port 1
    input logic rreq_1_i,
    input logic [ADDR_WIDTH-1:0] raddr_1_i,
    output logic rvalid_1_o,
    output logic [ICACHELINE_WIDTH-1:0] rdata_1_o,

    // Read port 2
    input logic rreq_2_i,
    input logic [ADDR_WIDTH-1:0] raddr_2_i,
    output logic rvalid_2_o,
    output logic [ICACHELINE_WIDTH-1:0] rdata_2_o,

    // <-> AXI Controller
    output logic [ADDR_WIDTH-1:0] axi_addr_o,
    output logic axi_rreq_o,
    input logic axi_rdy_i,
    input logic axi_rvalid_i,
    input logic [1:0] axi_rlast_i,
    input logic [ICACHELINE_WIDTH-1:0] axi_data_i,

    // CACOP
    input logic uncache_en,
    input logic icacop_op_en,
    input logic [1:0] cacop_op_mode,  
    input logic [7:0] cacop_op_addr_index, 
    input logic [19:0] cacop_op_addr_tag, 
    input logic [3:0]  cacop_op_addr_offset, 

    // TLB related
    input tlb_inst_t tlb_i,  // <- TLB
    input inst_tlb_t tlb_rreq_i  // <- IFU
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;
    // Indicates an entry is valid
    logic valid_flag;

    // Refill states
    enum int {
        IDLE,
        REFILL_1_REQ,
        REFILL_1_WAIT,
        REFILL_2_REQ,
        REFILL_2_WAIT
    }
        state, next_state;

    // P1 signal
    logic miss_1_pulse, miss_2_pulse, miss_1_r, miss_2_r, miss_1, miss_2;
    // rvalid_1 & 2 is only valid when state == IDLE or (miss_1 | (state == REFILL_1_WAIT & ~rvalid_1))
    logic rvalid_1, rvalid_2;
    // Input reg
    logic p1_rreq_1, p1_rreq_2;
    logic [ADDR_WIDTH-1:0] p1_raddr_1, p1_raddr_2;
    logic p1_tlb_miss;

    // valid flag
    always_ff @(posedge clk or negedge rst_n) begin
        // Flip valid bit if reset of receive a ICache invalid instruction
        if (!rst_n) valid_flag <= ~valid_flag;
    end

    /////////////////////////////////////////////////
    // PO, query BRAM
    ////////////////////////////////////////////////

    logic [NWAY-1:0][1:0][ICACHELINE_WIDTH-1:0] data_bram_rdata;
    logic [NWAY-1:0][1:0][ICACHELINE_WIDTH-1:0] data_bram_wdata;
    logic [NWAY-1:0][1:0][$clog2(NSET)-1:0] data_bram_addr;
    logic [NWAY-1:0][1:0] data_bram_we;

    // Tag bram 
    // {1bit valid, 20bits tag}
    localparam TAG_BRAM_WIDTH = 21;
    logic [NWAY-1:0][1:0][TAG_BRAM_WIDTH-1:0] tag_bram_rdata;
    logic [NWAY-1:0][1:0][TAG_BRAM_WIDTH-1:0] tag_bram_wdata;
    logic [NWAY-1:0][1:0][$clog2(NSET)-1:0] tag_bram_addr;
    logic [NWAY-1:0][1:0] tag_bram_we;


    logic [3:0] real_offset;
    logic [19:0] real_tag;
    logic [7:0] real_index;
    assign real_offset = icacop_op_en ? cacop_op_addr_offset : p1_tlb.offset;
    assign real_tag = icacop_op_en ? cacop_op_addr_tag : p1_tlb.tag;
    assign real_index = icacop_op_en ? cacop_op_addr_index : p1_tlb.index;

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

    // Generate miss signal
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
                    if (~p1_tlb_miss) begin
                        miss_1_r <= miss_1_pulse;
                        miss_2_r <= miss_2_pulse;
                    end
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
    // TLB miss
    inst_tlb_t p1_tlb_rreq;
    always_ff @(posedge clk) begin
        if (rreq_1_i | rreq_2_i) p1_tlb_rreq <= tlb_rreq_i;
    end
    assign p1_tlb_miss = p1_tlb_rreq.trans_en & ~p1_tlb.tlb_found;

    // Store TLB input
    tlb_inst_t p1_tlb, tlb_i_r;
    assign p1_tlb = (state == IDLE) ? tlb_i : tlb_i_r;
    always_ff @(posedge clk) begin
        if (rst) begin
            tlb_i_r <= 0;
        end else if (miss_1_pulse | miss_2_pulse) begin
            tlb_i_r <= tlb_i;
        end
    end
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
            tag_hit[i][0] = tag_bram_rdata[i][0][19:0] == p1_tlb.tag && tag_bram_rdata[i][0][20] == valid_flag;
            tag_hit[i][1] = tag_bram_rdata[i][1][19:0] == p1_tlb.tag && tag_bram_rdata[i][1][20] == valid_flag;
        end
    end

    // IDLE & WAIT can return rvalid_o, but REQ must not return rvalid_o
    assign rvalid_1_o = (rvalid_1 && p1_rreq_1 && state != REFILL_1_REQ) | (p1_tlb_miss && state == IDLE);
    assign rvalid_2_o = (rvalid_2 && p1_rreq_2 && state != REFILL_2_REQ) | (p1_tlb_miss && state == IDLE);
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
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin : transition_comb
        case (state)
            IDLE: begin
                if (p1_tlb_miss) next_state = IDLE;  // No refilling if TLB miss
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
    // Use result from TLB
    always_comb begin
        case (state)
            REFILL_1_REQ, REFILL_1_WAIT: begin
                axi_rreq_o = (miss_1 ? 1 : 0) & ~axi_rvalid_i;
                axi_addr_o = miss_1 ? {real_tag, p1_raddr_1[11:0]} : 0;
            end
            REFILL_2_REQ, REFILL_2_WAIT: begin
                axi_rreq_o = (miss_2 ? 1 : 0) & ~axi_rvalid_i;
                axi_addr_o = miss_2 ? {real_tag, p1_raddr_2[11:0]} : 0;
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
                    tag_bram_wdata[i][0] = {valid_flag, p1_tlb.tag};
                    data_bram_we[i][0] = 1;
                    data_bram_wdata[i][0] = axi_data_i;
                end
                if (state == REFILL_2_WAIT && axi_rvalid_i) begin
                    tag_bram_we[i][1] = 1;
                    tag_bram_wdata[i][1] = {valid_flag, p1_tlb.tag};
                    data_bram_we[i][1] = 1;
                    data_bram_wdata[i][1] = axi_data_i;
                end
            end
        end
    end

endmodule
