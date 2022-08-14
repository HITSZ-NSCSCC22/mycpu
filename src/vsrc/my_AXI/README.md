# AXI总线说明

## 目录结构
```
   AXI
        AXI_Master/    主机接口文件夹
            axi_Master          axi主机接口，接入cpu_top
            axi_MasterThree     失败版本，不用管
        
        AXI_Slave/       空文件夹
    
        axi_defines.v   定义了宏的文件
```

## 接口说明
```
    时钟和复位信号
    input wire aclk,
    input wire aresetn, //low is valid

    来自cpu和输出到cpu的信号，其中只有inst_cpu_data_o,data_cpu_data_o和inst_stallreq,data_stallreq是输出的。
    //icache/IF
    input wire [`ADDR]inst_cpu_addr_i,
    input wire [`Data]inst_cpu_data_i,
    input wire inst_flush_i,
    output reg [`Data]inst_cpu_data_o,
    input wire [3:0]inst_id,//决定是读数据还是取指令,默认4’b0000
   //icache 读请求的类型，3’b100表示一次性读取1个cache行(一个cache行默认4*32bit的数据,inst[addr],inst[addr+4],inst[addr+8],inst[addr+12]);其他值表示一次读取1*32bit数据
    input wire [2:0]icache_rd_type_i,
    input wire icache_rd_req_i,//读请求使能信号，高位有效
    output reg icache_rd_rdy_o,//读请求可被接受
    output reg icache_ret_valid_o,//读数据有效
    output reg [1:0]icache_ret_last_o,//最后一个读数据


    //dcache/MEM
    input wire [`ADDR]data_cpu_addr_i,
    input wire [`Data]data_cpu_data_i,
    input wire [3:0]data_cpu_sel_i, 
    input wire data_flush_i,
    output reg [`Data]data_cpu_data_o,
    input wire [3:0]data_id,//决定是读数据还是取指令,默认4'b0001
    // 同icache_rd_type_i
    input wire [2:0]dcache_rd_type_i,
    //表示一次性写入的数据，3'b100表示把一个cache行写入连续的4*32bit空间,Mem[addr]=dcache_wr_data[31:0],...Mem[addr+12]=dcache_wr_data[127:96];其他数值表示只写入dcache[31:0]
    input wire [2:0]dcache_wr_type_i,//decache write type
    //4*32bit的写入数据，如果只想写一个数据，只需要保证31:0是正确的写入数据即可
    input wire [`BurstData]dcache_wr_data,//data from dcache
    input wire [2:0]dcache_rd_type_i,
    input wire dcache_rd_req_i,
    output reg dcache_rd_rdy_o,
    output reg dcache_ret_valid_o,
    output reg [1:0]dcache_ret_last_o,
    input wire dcache_wr_req_i,//写使能，高为有效
    output reg dcache_wr_rdy,//写请求可被接受



    AXI标准信号接口，输出到从机或从从机输入，无需关心内部逻辑，照着接线就好，s是前缀。
    //Slave

    //ar
    output reg [`ID]s_arid,  //arbitration
    output reg [`ADDR]s_araddr,
    output wire [`Len]s_arlen,
    output reg [`Size]s_arsize,
    output wire [`Burst]s_arburst,
    output wire [`Lock]s_arlock,
    output wire [`Cache]s_arcache,
    output wire [`Prot]s_arprot,
    output reg s_arvalid,
    input wire s_arready,

    //r
    input wire [`ID]s_rid,
    input wire [`Data]s_rdata,
    input wire [`Resp]s_rresp,
    input wire s_rlast,//the last read data
    input wire s_rvalid,
    output reg s_rready,

    //aw
    output wire [`ID]s_awid,
    output reg [`ADDR]s_awaddr,
    output wire [`Len]s_awlen,
    output reg [`Size]s_awsize,
    output wire [`Burst]s_awburst,
    output wire [`Lock]s_awlock,
    output wire [`Cache]s_awcache,
    output wire [`Prot]s_awprot,
    output reg s_awvalid,
    input wire s_awready,

    //w
    output wire [`ID]s_wid,
    output reg [`Data]s_wdata,
    output wire [3:0]s_wstrb,//字节选通位和sel差不多
    output wire  s_wlast,
    output reg s_wvalid,
    input wire s_wready,

    //b
    input wire [`ID]s_bid,
    input wire [`Resp]s_bresp,
    input wire s_bvalid,
    output reg s_bready
```

# 本版本为面向cache的版本，面向CPU的版本，请见5.9号提交的版本。AXI对cache有特定要求务必要仔细阅读说明。

## 使用说明
1. 把axi_Master主机接口放到cpuTop中实例化     
   * 实现仲裁的axi接口(不支持同种请求的连续发送，支持同时送取指和取数核突发传送)，取值id接口`4’b0000`,取数id接口`4'b0001`
   * 支持写操作，读指令和读数据。若同时发出取指和取数，会并行执行(指同时发送两种请求，若先取指后取数或先取数后取指都无法并行)
   * 如果连续发送两次读请求，则会等待第一个读请求结束在处理第二个读请求
   * 先写后读，写请求结束后才会处理读请求
   * 所有的请求在请求结束前，都需要保证来自cpu的输入信号不变
   * dcache/icache_rd/wr_type_i表示一次性读或写的数据量。`3'b100`表示一次性读写128bit；`3'b010`，32bit；`3'b001`,16bit;`3'b000`8bit
   ```      
         
            wire aresetn=~rst;
            wire stallreq_from_if;
            wire stallreq_from_mem;
            wire [31:0]inst_data_from_axi;
            wire [31:0]mem_data_from_axi;
            wire [31:0]data;//写入的数据

            //接口实例化
            axi_Master inst_interface(
            .aclk(clk),
            .aresetn(aresetn), //low is valid
    //icache/IF
            .inst_cpu_addr_i(inst_pc),
            .inst_cpu_sel_i(4'b1111), 
            .inst_flush_i(0),
            .inst_cpu_data_o(inst_data_from_axi),
            .inst_id(4'b0000),//决定是读数据还是取指令
            .icache_rd_type_i(3'b100),//3'b100开启连续读4个数据;0只读一个数据
            .icache_rd_req_i(),//接读使能
            .icache_rd_rdy_o(),//接读请求握手信号
            .icache_ret_valid_o(),//接读有效信号
            .icache_ret_last_o(),//接最后一个读数据信号


     //dacache/MEM
            .data_cpu_addr_i(data_pc),
            .data_cpu_data_i(data),
            .data_cpu_sel_i(4'b1111), 
            .data_flush_i(0),
            .data_cpu_data_o(mem_data_from_axi),
            .data_id(4'b0001),//决定是读数据还是取指令
            .dcache_rd_type_i(),//同icache
            .dcache_wr_type_i(),//写的数据量，3'b100表示连续写四个数据至相邻的地址；0表示只写一个数据
            .dcache_wr_data(),//128bit的写入数据，如果只想写一个那么只需要保证31:0正确
            .dcache_rd_req_i(),
            .dcache_rd_rdy_o(),
            .dcache_ret_valid_o(),
            .dcache_ret_last_o(),
            .dcache_wr_data(),//data from dcache
            .dcache_wr_req_i(),//write enable signal
            .dcache_wr_rdy(),//write can receive


    //ar
            .s_arid(i_arid),  //arbitration
            .s_araddr(i_araddr),
            .s_arlen(i_arlen),
            .s_arsize(i_arsize),
            .s_arburst(i_arburst),
            .s_arlock(i_arlock),
            .s_arcache(i_arcache),
            .s_arprot(i_arprot),
            .s_arvalid(i_arvalid),
            .s_arready(i_arready),

    //r
            .s_rid(i_rid),
            .s_rdata(i_rdata),
            .s_rresp(i_rresp),
            .s_rlast(i_rlast),//the last read data
            .s_rvalid(i_rvalid),
            .s_rready(i_rready),

    //aw
            .s_awid(i_awid),
            .s_awaddr(i_awaddr),
            .s_awlen(i_awlen),
            .s_awsize(i_awsize),
            .s_awburst(i_awburst),
            .s_awlock(i_awlock),
            .s_awcache(i_awcache),
            .s_awprot(i_awprot),
            .s_awvalid(i_awvalid),
            .s_awready(i_awready),

    //w
            .s_wid(i_wid),
            .s_wdata(i_wdata),
            .s_wstrb(i_wstrb),//字节选通位和sel差不多，写32字节用4'b1111
            .s_wlast(i_wlast),
            .s_wvalid(i_wvalid),
            .s_wready(i_wready),

    //b
            .s_bid(i_bid),
            .s_bresp(i_bresp),
            .s_bvalid(i_bvalid),
            .s_bready(i_bready)

        );
   ```   


2. inst_data_from_axi，mem_data_from为从ram中取到的数据  

3. xxx_cpu_sel_i为字节选通使能，用来实现store类型。

4. 关于cache给AXI的信号。在AXI完成写或读请求前，cache的信号必须要持续的拉高。对于读指令，当ret_last拉高时，才能更新输出给AXI的信号（req，type，addr）;对于写，和wr_rdy正常握手就好，输出给AXI的信号只需要保存一个时钟周期。

5. cache何时给信号。cache只要发出读或写请求就立刻给出所有信号(req，type，addr,data)。`重点`addr，data，type，req是同时给到AXI，而不是等到cache与rdy握手后才给addr和data，这样AXI就无法接受数据。握手是指握手后接收方立刻把数据存到寄存器里。   

## size和传送字节数的关系
| rd_type(wr_type) | arzie(awsize) |字节数|
|:----:|:----:|:----:|
|3'b000|3'b000|1|
|3'b001|3'b001|2|
|3'b010|3'b010|4|
|3'b011|3'b011|8|
|3'b100|3'b100|16|