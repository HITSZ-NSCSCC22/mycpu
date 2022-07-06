`include "core_config.sv"
`include "tlb_types.sv"
`include "utils/bram.sv"
`include "utils/lfsr.sv"


module dcache_test
    import core_config::*;
    import tlb_types::*;
(
    input logic clk,
    input logic rst,

    //cache与CPU流水线的交互接
    input logic valid,  //表明请求有效
    input logic op,  // 1:write 0: read
    input logic uncache,  //标志uncache指令，高位有效
    input logic [7:0] index,  // 地址的index域(addr[11:4])
    input logic [19:0] tag,  //从TLB查到的pfn形成的tag
    input logic [3:0] offset,  //地址的offset域addr[3:0]
    input logic [3:0] wstrb,  //写字节使能信号
    input logic [31:0] wdata,  //写数据
    input logic [2:0] rd_type_i, //读请求类型：3'b000: 字节；3'b001: 半字；3'b010: 字；3'b100：Cache行
    input logic [2:0] wr_type_i,
    input logic flush_i, // 冲刷信号，如果出于某种原因需要取消写事务，CPU拉高此信号
    output logic addr_ok,             //该次请求的地址传输OK，读：地址被接收；写：地址和数据被接收
    output logic data_ok,             //该次请求的数据传输Ok，读：数据返回；写：数据写入完成
    output logic [31:0] rdata,  //读Cache的结果

    //cache与AXI总线的交互接口
    output logic rd_req,  //读请求有效信号。高电平有效
    output logic [2:0] rd_type,              //读请求类型：3'b000: 字节；3'b001: 半字；3'b010: 字；3'b100：Cache行
    output logic [31:0] rd_addr,  //读请求起始地址
    input logic rd_rdy,  //读请求能否被接收的握手信号。高电平有效
    input logic ret_valid,  //返回数据有效。高电平有效。
    input logic ret_last,  //返回数据是一次读请求对应的最后一个返回数据
    input logic [127:0] ret_data,  //读返回数据
    output logic wr_req,  //写请求有效信号。高电平有效
    output logic [2:0] wr_type,              //写请求类型：3'b000: 字节；3'b001: 半字；3'b010: 字；3'b100：Cache行
    output logic [31:0] wr_addr,  //写请求起始地址
    output logic [15:0] wr_wstrb,  //写操作的字节掩码。16bits for AXI128
    output logic [127:0] wr_data,  //写数据
    input logic wr_rdy  //写请求能否被接受的握手信号。具体见p2234.


    //还需对类SRAM-AXI转接桥模块进行调整，随后确定实现
);

    localparam NWAY = ICACHE_NWAY;
    localparam NSET = ICACHE_NSET;

    logic [NWAY-1:0][1:0][DCACHELINE_WIDTH-1:0] data_bram_rdata;
    logic [NWAY-1:0][1:0][DCACHELINE_WIDTH-1:0] data_bram_wdata;
    logic [NWAY-1:0][1:0][$clog2(NSET)-1:0] data_bram_addr;
    logic [NWAY-1:0][1:0] data_bram_we;
    logic [NWAY-1:0][1:0] data_bram_en;

    // Tag bram 
    // {1bit valid, 20bits tag}
    localparam TAG_BRAM_WIDTH = 21;
    logic [NWAY-1:0][1:0][TAG_BRAM_WIDTH-1:0] tag_bram_rdata;
    logic [NWAY-1:0][1:0][TAG_BRAM_WIDTH-1:0] tag_bram_wdata;
    logic [NWAY-1:0][1:0][$clog2(NSET)-1:0] tag_bram_addr;
    logic [NWAY-1:0][1:0] tag_bram_we;
    logic [NWAY-1:0][1:0] tag_bram_en;

    logic [1:0] hit;
    logic [NWAY-1:0][1:0] tag_hit;


    enum int {
        IDLE,
        READ_REQ,
        READ_WAIT,
        WRITE_REQ
    }
        state, next_state;

    enum int {
        WB_IDLE,
        WB_WRITE

    }
        wb_state, wb_next_state;


    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            wb_state <= WB_IDLE;
        end else begin
            state <= next_state;
            wb_state <= wb_next_state;
        end
    end


    always_comb begin : transition_comb
        case (state)
            IDLE: begin
                if (valid) begin
                    if (op) next_state = WRITE_REQ;
                    else next_state = READ_REQ;
                end else next_state = IDLE;
            end
            READ_REQ: begin
                if (rd_rdy) next_state = READ_WAIT;  // If AXI ready, send request 
                else next_state = READ_REQ;
            end
            READ_WAIT: begin
                if (ret_valid) next_state = IDLE;  // If return valid, back to IDLE
                else next_state = READ_WAIT;
            end
            WRITE_REQ: begin
                // If AXI is ready, then write req is accept this cycle, back to IDLE
                // If flushed, back to IDLE
                if (wr_rdy | flush_i) next_state = IDLE;
                else next_state = WRITE_REQ;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always_comb begin : bram_addr_gen
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
                if (valid) begin
                    for (integer i = 0; i < NWAY; i++) begin
                        tag_bram_en[i][0] = 1;
                        data_bram_en[i][0] = 1;
                        tag_bram_addr[i][0] = index;
                        data_bram_addr[i][0] = index;
                    end
                end
            end
            default: begin

            end
        endcase
    end

    // Hit signal
    always_comb begin
        for (integer i = 0; i < NWAY; i++) begin
            tag_hit[i][0] = tag_bram_rdata[i][0][19:0] == tag && tag_bram_rdata[i][0][20];
            tag_hit[i][1] = tag_bram_rdata[i][1][19:0] == tag && tag_bram_rdata[i][1][20];
        end
    end

    always_comb begin
        hit[0] = 0;
        hit[1] = 0;
        rdata  = 0;
        for (integer i = 0; i < NWAY; i++) begin
            if (tag_hit[i][0]) begin
                hit[0] = 1;
                rdata  = data_bram_rdata[i][0][offset];
            end
            if (tag_hit[i][1]) begin
                hit[1] = 1;
                rdata  = data_bram_rdata[i][1];
            end
        end
    end


















    lfsr #(
        .WIDTH(3)
    ) u_lfsr (
        .clk  (clk),
        .rst  (rst),
        .en   (1'b1),
        .value(random_r)
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
