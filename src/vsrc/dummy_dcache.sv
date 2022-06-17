module dummy_dcache (
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

    enum int {
        IDLE,
        READ_REQ,
        READ_WAIT,
        WRITE_REQ
    }
        state, next_state;

    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end

    // State transition
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

    logic [31:0] cpu_addr;
    assign cpu_addr = {tag, index, offset};

    logic rd_req_r;
    logic [31:0] rd_addr_r;

    // Handshake with AXI
    always_ff @(posedge clk) begin
        case (state)
            READ_REQ: begin
                if (rd_rdy) begin
                    rd_req_r  <= 1;
                    rd_addr_r <= cpu_addr;
                end
            end
        endcase
    end


    assign rd_type = rd_type_i;
    assign wr_type = 3'b010;  // word
    always_comb begin
        // Default signal
        rd_addr  = 0;
        rd_req   = 0;
        wr_addr  = 0;
        wr_data  = 0;
        wr_req   = 0;
        wr_wstrb = 0;

        case (state)
            READ_REQ: begin
                if (rd_rdy) begin
                    rd_req  = 1;
                    rd_addr = cpu_addr;
                end
            end
            READ_WAIT: begin
                rd_req  = rd_req_r & ~ret_valid;
                rd_addr = rd_addr_r;
            end
            WRITE_REQ: begin
                if (flush_i) begin
                    wr_req  = 0;
                    wr_addr = 0;
                end else if (wr_rdy) begin
                    wr_req = 1;
                    wr_addr = cpu_addr;  // DO NOT align addr, 128b -> 32b translate need info from addr
                    case (cpu_addr[3:2])
                        2'b00: begin
                            wr_data  = {{96{1'b0}}, wdata};
                            wr_wstrb = {12'b0, wstrb};
                        end
                        2'b01: begin
                            wr_data  = {{64{1'b0}}, wdata, {32{1'b0}}};
                            wr_wstrb = {8'b0, wstrb, 4'b0};
                        end
                        2'b10: begin
                            wr_data  = {32'b0, wdata, {64{1'b0}}};
                            wr_wstrb = {4'b0, wstrb, 8'b0};
                        end
                        2'b11: begin
                            wr_data  = {wdata, {96{1'b0}}};
                            wr_wstrb = {wstrb, 12'b0};
                        end
                    endcase
                end
            end
        endcase
    end

    // Handshake with CPU
    always_comb begin
        addr_ok = 0;
        data_ok = 0;
        rdata   = 0;
        case (state)
            READ_WAIT: begin
                if (ret_valid) begin
                    addr_ok = 1;
                    data_ok = 1;
                    rdata   = ret_data[rd_addr_r[3:2]*32+:32];
                end
            end
            WRITE_REQ: begin
                if (wr_rdy) begin
                    addr_ok = 1;
                    data_ok = 1;
                end
            end
        endcase
    end

endmodule
