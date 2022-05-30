`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/04/21 17:24:48
// Design Name: 
// Module Name: dcache
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//cache共2组，每组4k。
//V、D、Tag、Data=1+1+20+128=150


module dcache (
    input logic  clk,
    input logic  rst,

    //cache与CPU流水线的交互接
    input logic  valid,  //表明请求有效
    input logic  op,  // 1:write 0: read
    input logic  uncache,  //标志uncache指令，高位有效
    input logic  [7:0] index,  // 地址的index域(addr[11:4])
    input logic  [19:0] tag,  //从TLB查到的pfn形成的tag
    input logic  [3:0] offset,  //地址的offset域addr[3:0]
    input logic  [3:0] wstrb,  //写字节使能信号
    input logic  [31:0] wdata,  //写数据
    output logic addr_ok,             //该次请求的地址传输OK，读：地址被接收；写：地址和数据被接收
    output logic data_ok,             //该次请求的数据传输Ok，读：数据返回；写：数据写入完成
    output logic [31:0] rdata,  //读Cache的结果

    //cache与AXI总线的交互接口
    output logic rd_req,  //读请求有效信号。高电平有效
    output logic[3:0]    rd_type,              //读请求类型：3'b000: 字节；3'b001: 半字；3'b010: 字；3'b100：Cache行
    output logic [31:0] rd_addr,  //读请求起始地址
    input logic  rd_rdy,  //读请求能否被接收的握手信号。高电平有效
    input logic  ret_valid,  //返回数据有效。高电平有效。
    input logic  ret_last,  //返回数据是一次读请求对应的最后一个返回数据
    input logic  [31:0] ret_data,  //读返回数据
    output logic wr_req,  //写请求有效信号。高电平有效
    output logic[2:0]    wr_type,              //写请求类型：3'b000: 字节；3'b001: 半字；3'b010: 字；3'b100：Cache行
    output logic [31:0] wr_addr,  //写请求起始地址
    output logic[3:0]    wr_wstrb,             //写操作的字节掩码。仅在写请求类型为：3'b000: 字节；3'b001: 半字；3'b010：字的情况下才有意义
    output logic [127:0] wr_data,  //写数据
    input logic  wr_rdy  //写请求能否被接受的握手信号。具体见p2234.


    //还需对类SRAM-AXI转接桥模块进行调整，随后确定实现
);

    //主状态机包括五个状态，
    //IDLE：Cache模块当前没有任何操作
    //LOOKUP：Cache模块当前正在执行一个操作并且得到了它的查询结果
    //MISS：Cache模块当前处理的操作Cache缺失，且正在等待AXI总线的wr_rdy信号
    //REPLACE：待替换的Cache行已经从Cache中读出，且正在等待AXI总线的rd_rdy信号
    //REFILL：Cache缺失的访存请求已发出，准备/正在将缺失的Cache行数据写入Cache中
    enum int {
        IDLE,
        LOOKUP,
        MISS,
        REPLACE,
        REFILL,
        WRITE
    }
        state, next_state;
    //Write Buffer状态机包括两个状态
    //IDLE: Write Buffer状态机当前没有待写的数据
    //WRITE: 将待写的数据写入Cache中。在主状态机处于LOOKUP状态且发现Store操作命中Cache是，触发Write Buffer状态机进入Write状态
    //同时Write Buffer会寄存Store要写入的Index、路号、offset、写使能(写32位数据里的那些字节)和写数据。


    parameter V = 149;
    parameter D = 148;
    parameter TagMSB = 147;
    parameter TagLSB = 128;
    parameter BlockMSB = 127;
    parameter BlockLSB = 0;

    logic [511:0][149:0] cache_data;
    logic [2:0] wr_state, wr_next_state;
    logic         hit;
    logic         hit1;
    logic         hit2;
    logic         way;  //若hit，则way无意义，若miss，则way表示分配的那一路
    logic         write_op;  //hit write 执行标志，高电平有效
    logic         miss_way_r;  //缺失路的写使能

    //虚地址共32位，[31:12]为Tag，[11:4]为Cache组索引index, [3:0]:offset,Cache行内偏移
    logic  [ 7:0] cpu_req_index;
    logic  [19:0] cpu_req_tag;
    logic  [ 3:0] cpu_req_offset;

    //wire cpu_req_uncache;
    logic         cpu_req_valid;
    logic         cpu_req_op;
    logic  [ 3:0] cpu_req_wstrb;
    logic  [31:0] cpu_req_wdata;

    logic         cpu_rd_rdy;
    logic         cpu_wr_rdy;
    logic         cpu_ret_valid;
    logic         cpu_ret_last;
    logic  [31:0] cpu_ret_data;

    ////虚地址共32位，[31:12]为Tag，[11:4]为Cache组索引index, [3:0]:offset,Cache行内偏移
    //logic [7:0]cpu_req_index;
    //logic [19:0]cpu_req_tag;
    //logic [3:0]cpu_req_offset;

    ////logic  cpu_req_uncache;
    //logic cpu_req_valid;
    //logic cpu_req_op;
    //logic[3:0] cpu_req_wstrb;
    //logic[31:0] cpu_req_wdata;

    //logic cpu_rd_rdy;
    //logic cpu_wr_rdy;
    //logic cpu_ret_valid;
    //logic[1:0] cpu_ret_last;
    //logic[31:0] cpu_ret_data;

    //hit write 冲突 高位有效
    logic         hit_conflict = 0;

    assign cpu_req_valid = valid;
    assign cpu_req_op = op;
    assign cpu_req_uncache = uncache;
    assign cpu_req_offset = offset;
    assign cpu_req_index = index;
    assign cpu_req_tag = tag;
    assign cpu_req_wstrb = wstrb;
    assign cpu_req_wdata = wdata;
    assign cpu_rd_rdy = rd_rdy;
    assign cpu_wr_rdy = wr_rdy;
    assign cpu_ret_valid = ret_valid;
    assign cpu_ret_last = ret_last;
    assign cpu_ret_data = ret_data;


    //读写访问Cache的执行过程
    //初始化cache
    initial begin
        for (integer i = 0; i < 512; i = i + 1) cache_data[i] = 0;
    end


    always @(posedge clk, posedge rst) begin
        if (!rst) state <= IDLE;
        else state <= next_state;
    end

    //state change
    always_comb begin
        case (state)
            IDLE: begin
                if (!cpu_req_valid || (cpu_req_valid && hit_conflict)) next_state = IDLE;
                else next_state = LOOKUP;
            end
            LOOKUP: begin
                if ((hit && !cpu_req_valid) || (hit && (cpu_req_valid && hit_conflict)))  //若hit
                    next_state = IDLE;
                else if (hit && cpu_req_valid) next_state = LOOKUP;
                else if (!hit) begin
                    next_state = MISS;
                end
            end
            MISS: begin
                if (cpu_wr_rdy == 0) next_state = MISS;
                else if (cpu_wr_rdy == 1) next_state = REPLACE;
            end
            REPLACE: begin
                if (cpu_rd_rdy == 0) next_state = REPLACE;
                else next_state = REFILL;
            end
            REFILL: begin
                if (cpu_ret_valid == 1 && cpu_ret_last == 1) next_state = IDLE;
                else next_state = REFILL;
            end
            default: next_state = IDLE;
        endcase
    end

    logic wr_buffer;
    //Write buffer state change
    always @(*) begin
        case (wr_state)
            IDLE:
            if (hit && cpu_req_op && cpu_req_valid) begin
                wr_next_state = WRITE;
            end else begin
                wr_next_state = IDLE;
            end
            WRITE:
            if ((hit) && (cpu_req_op))  //若hit
                wr_next_state = WRITE;
            else wr_next_state = IDLE;

            default: wr_next_state = IDLE;
        endcase
    end


    //Tag compare
    //hit1
    always @(*) begin
        if (state == LOOKUP)
            if(cache_data[2*cpu_req_index][V]==1'b1&&cache_data[2*cpu_req_index][TagMSB:TagLSB]==cpu_req_tag)begin
                hit1 = 1'b1;
                if (cpu_req_op == 1) begin
                    if (index == cpu_req_index && tag == cpu_req_tag) begin
                        hit_conflict = 1;
                    end
                end
            end else hit1 = 1'b0;
        else hit1 = 1'b0;
    end
    //hit2
    always @(*) begin
        if (state == LOOKUP)
            if(cache_data[2*cpu_req_index+1][V]==1'b1&&cache_data[2*cpu_req_index+1][TagMSB:TagLSB]==cpu_req_tag)begin
                hit2 = 1'b1;
                if (cpu_req_op == 1) begin
                    if (index == cpu_req_index && tag == cpu_req_tag) begin
                        hit_conflict = 1;
                    end
                end
            end else hit2 = 1'b0;
        else hit2 = 1'b0;
    end
    //hit
    always @(*) begin
        if (state == LOOKUP) begin
            hit = hit1 || hit2;
            if (hit && cpu_req_op) begin
                wr_state = WRITE;
            end
        end else hit = 1'b0;
    end


    //LOOKUP模块: Cache命中后的读写操作---Data Select
    always @(posedge clk) begin
        if (state == LOOKUP && hit)
            if( op==1'b0)                        //read hit
        begin
                addr_ok <= 1'b1;
                if (hit1) begin
                    rdata = cache_data[2*cpu_req_index][8*cpu_req_offset+:32];
                end else begin
                    rdata = cache_data[2*cpu_req_index+1][8*cpu_req_offset+:32];
                end
            end

        else if(wr_state==WRITE && hit)                                     //write hit
        begin
                addr_ok <= 1'b1;
                data_ok <= 1'b1;
                if (hit1) begin
                    cache_data[2*cpu_req_index][8*cpu_req_offset+:32] = wdata;
                    cache_data[2*cpu_req_index][D] = 1'b1;
                end else begin
                    cache_data[2*cpu_req_index+1][8*cpu_req_offset+:32] = wdata;
                    cache_data[2*cpu_req_index+1][D] = 1'b1;
                end
                if (cpu_req_op == 0) begin
                    if (cpu_req_offset[3:2] == offset[3:2]) begin
                        hit_conflict = 1;
                    end
                end
            end
    end

    //way      LFSB --Miss Buffer 
    always @(*) begin
        if (state == MISS) begin  //未命中
            case ({
                cache_data[2*cpu_req_index][V], cache_data[2*cpu_req_index+1][V]
            })
                2'b01:   way = 1'b0;  //第0路可用
                2'b10:   way = 1'b1;  //第1路可用
                2'b00:   way = 1'b0;  //第0、1路均可用
                2'b11:   way = 1'b0;  //第0、1路均不可用，默认替换第0路
                default: way = 1'b0;
            endcase
            miss_way_r = 1;
        end
    end

    logic [1:0] rt_offset;
    //对AXI接口的写操作
    always @(*) begin
        if (state == MISS) begin  // 存储要写的数据还有地址等信息		     
            //			if(cpu_req_op == 1)begin
            //			     if(cache_data[2*cpu_req_index + way][D])begin

            //			     end

            //			end
            rd_addr = {cpu_req_tag[19:0], cpu_req_index[7:0], cpu_req_offset};
            rd_type = 3'b000;
            // addr_ok = 1'b1;
            // data_ok <= 1'b1;
        end else if (state == REPLACE) begin
            //将被替换行的Cache数据写入主存中
            if (wr_rdy) begin
                if (cache_data[2*cpu_req_index+way][V:D] == 2'b11) begin
                    wr_req = 1'b1;
                    wr_addr = {
                        cache_data[2*cpu_req_index+way][TagMSB:TagLSB], cpu_req_index, 4'b0000
                    };
                    wr_wstrb = wstrb;
                    wr_data = cache_data[2*cpu_req_index+way][BlockMSB:BlockLSB];
                end
            end else begin
                wr_req = 1'b0;
            end
            rd_req = 1'b1;
        end else begin
            wr_req = 1'b0;
            rd_req = 1'b0;
        end
    end
    //Miss Buffer
    always @(*) begin
        if (state == REFILL) begin
            if (cpu_req_op == 0) begin
                cache_data[2*cpu_req_index+way][149:128] = {2'b10, cpu_req_tag};
                cache_data[2*cpu_req_index+way][rt_offset*32+:32] = ret_data;
                if (ret_last) begin
                    rt_offset = 0;
                    rd_req = 1'b0;
                    rdata = cache_data[2*cpu_req_index+way][cpu_req_index*8+:32];
                end
            end
            if (cpu_req_op == 1) begin
                cache_data[2*cpu_req_index+way][149:128] = {2'b11, cpu_req_tag};
                cache_data[2*cpu_req_index+way][rt_offset*8+:32] = ret_data;
                if (ret_last) begin
                    rt_offset = 0;
                    cache_data[2*cpu_req_index+way][cpu_req_index*8+:32] = cpu_req_wdata;
                end
            end
            rt_offset = rt_offset + 1;
        end
    end

endmodule



