
`include "utils/bram.sv"

module icache #(
    parameter NSET = 256,
    parameter NWAY = 2,
    parameter CACHELINE_WIDTH = 128,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst,

    // Read port 1
    input logic rreq_1_i,
    input logic [ADDR_WIDTH-1:0] raddr_1_i,
    output logic rvalid_1_o,
    output logic [DATA_WIDTH-1:0] rdata_1_o,

    // Read port 2
    input logic rreq_2_i,
    input logic [ADDR_WIDTH-1:0] raddr_2_i,
    output logic rvalid_2_o,
    output logic [DATA_WIDTH-1:0] rdata_2_o,

    // <-> AXI Controller
    output logic [ADDR_WIDTH-1:0] axi_addr_o,
    output logic axi_rreq_o,
    input logic axi_busy_i,  // High effective
    input logic [DATA_WIDTH-1:0] axi_data_i
);


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
        end
    endgenerate
    generate
        for (genvar i = 0; i < NWAY; i++) begin : data_bram
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
        end
    endgenerate

    // Cache addr 
    always_comb begin : cache_addr_gen
        for (integer i = 0; i < NWAY; i++) begin
            if (rreq_1_i) begin
                tag_bram_addr[i][0]  = raddr_1_i[11:4];
                data_bram_addr[i][0] = raddr_1_i[11:4];
            end else begin  // TODO: write
                tag_bram_addr[i][0]  = 0;
                data_bram_addr[i][0] = 0;
            end
        end
        for (integer i = 0; i < NWAY; i++) begin
            if (rreq_2_i) begin
                tag_bram_addr[i][1]  = raddr_2_i[11:4];
                data_bram_addr[i][1] = raddr_2_i[11:4];
            end else begin
                tag_bram_addr[i][1]  = 0;
                data_bram_addr[i][1] = 0;
            end
        end
    end

    logic [NWAY-1:0][1:0] tag_hit;
    always_comb begin
        for (integer i = 0; i < NWAY; i++) begin
            tag_hit[i][0] = tag_bram_rdata[i][0][19:0] == raddr_1_i[ADDR_WIDTH-1:ADDR_WIDTH-20];
            tag_hit[i][1] = tag_bram_rdata[i][1][19:0] == raddr_2_i[ADDR_WIDTH-1:ADDR_WIDTH-20];
        end
    end

    // Generate read output
    logic [1:0] offset_1, offset_2;
    assign offset_1 = raddr_1_i[3:2];
    assign offset_2 = raddr_2_i[3:2];
    logic [NWAY-1:0][1:0][DATA_WIDTH-1:0] data_inside_cacheline;
    always_comb begin
        for (integer i = 0; i < NWAY; i++) begin
            case (offset_1)
                2'b00: data_inside_cacheline[i][0] = data_bram_rdata[i][0][31:0];
                2'b01: data_inside_cacheline[i][0] = data_bram_rdata[i][0][63:32];
                2'b10: data_inside_cacheline[i][0] = data_bram_rdata[i][0][95:64];
                2'b11: data_inside_cacheline[i][0] = data_bram_rdata[i][0][127:96];
            endcase
            case (offset_2)
                2'b00: data_inside_cacheline[i][1] = data_bram_rdata[i][1][31:0];
                2'b01: data_inside_cacheline[i][1] = data_bram_rdata[i][1][63:32];
                2'b10: data_inside_cacheline[i][1] = data_bram_rdata[i][1][95:64];
                2'b11: data_inside_cacheline[i][1] = data_bram_rdata[i][1][127:96];
            endcase
        end
    end
    always_comb begin
        rvalid_1_o = 0;
        rdata_1_o  = 0;
        rvalid_2_o = 0;
        rdata_2_o  = 0;
        for (integer i = 0; i < NWAY; i++) begin
            if (tag_hit[i][0]) begin
                rvalid_1_o = 1;
                rdata_1_o  = data_inside_cacheline[i][0];
            end
            if (tag_hit[i][1]) begin
                rvalid_2_o = 1;
                rdata_2_o  = data_inside_cacheline[i][1];
            end
        end
    end

endmodule
