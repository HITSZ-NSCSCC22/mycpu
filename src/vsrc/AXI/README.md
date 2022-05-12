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
    input wire inst_cpu_ce_i,
    input wire [`Data]inst_cpu_data_i,
    input wire inst_cpu_we_i ,
    input wire [3:0]inst_cpu_sel_i, 
    input wire inst_stall_i,
    input wire inst_flush_i,
    output reg [`Data]inst_cpu_data_o,
    output wire inst_stallreq,
    input wire [3:0]inst_id,//决定是读数据还是取指令,默认4’b0000
   //icache 读请求的类型，3’b100表示一次性读取1个cache行(一个cache行默认4*32bit的数据,inst[addr],inst[addr+4],inst[addr+8],inst[addr+12]);其他值表示一次读取1*32bit数据
    input wire [2:0]icache_rd_type_i,



    //dcache/MEM
    input wire [`ADDR]data_cpu_addr_i,
    input wire data_cpu_ce_i,
    input wire [`Data]data_cpu_data_i,
    input wire data_cpu_we_i ,
    input wire [3:0]data_cpu_sel_i, 
    input wire data_stall_i,
    input wire data_flush_i,
    output reg [`Data]data_cpu_data_o,
    output wire data_stallreq,
    input wire [3:0]data_id,//决定是读数据还是取指令,默认4'b0001
    // 同icache_rd_type_i
    input wire [2:0]dcache_rd_type_i,
    //表示一次性写入的数据，3'b100表示把一个cache行写入连续的4*32bit空间,Mem[addr]=dcache_wr_data[31:0],...Mem[addr+12]=dcache_wr_data[127:96];其他数值表示只写入dcache[31:0]
    input wire [2:0]dcache_wr_type_i,//decache write type
    //4*32bit的写入数据，如果只想写一个数据，只需要保证31:0是正确的写入数据即可
    input wire [`BurstData]dcache_wr_data,//data from dcache

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

## 使用说明
1. 把axi_Master主机接口放到cpuTop中实例化     
   * 实现仲裁的axi接口(不支持同种请求的连续发送和突发传输，支持同时送取指和取数)，取值id接口`4’b0000`,取数id接口`4'b0001`
   * 支持写操作，读指令和读数据。若同时发出取指和取数，会并行执行(指同时发送两种请求，若先取指后取数或先取数后取指都无法并行)
   * 如果连续发送两次读请求，则会等待第一个读请求结束在处理第二个读请求
   * 先写后读，写请求结束后才会处理读请求
   * 所有的请求在请求结束前，都需要保证来自cpu的输入信号不变
   * dcache/icache_rd/wr_type_i表示一次性读或写的数据量。`3'b100`表示一次性读/写连续四个地址的数据；其他值表示只读/写一个数据，推荐直接写0
   * 即使没有cache。icache和dcache开头的信号都要接
   * 下面的说明，不适用突发传输，icache/dcache_rd/wr_type_i照着抄就好，不需要改。需要注意的是dcache_wr_data需要是128bit的数据，如果只想写一个的话，需要再前面添加96个0，例如写data[31:0]，则dcache_wr_data({{96{1'b0}}},data[31:0])
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
            .inst_cpu_ce_i(inst_chip_enable),
            .inst_cpu_we_i(0) ,
            .inst_cpu_sel_i(4'b1111), 
            .inst_flush_i(0),
            .inst_cpu_data_o(inst_data_from_axi),
            .inst_stallreq(stallreq_from_if),
            .inst_id(4'b0000),//决定是读数据还是取指令
            .icache_rd_type_i(0),//3'b100开启连续读4个数据;0只读一个数据
     
     //dacache/MEM
            .data_cpu_addr_i(data_pc),
            .data_cpu_ce_i(data_chip_enable),
            .data_cpu_we_i(data_we) ,
            .data_cpu_sel_i(4'b1111), 
            .data_flush_i(0),
            .data_cpu_data_o(mem_data_from_axi),
            .data_stallreq(stallreq_from_mem),
            .data_id(4'b0001),//决定是读数据还是取指令
            .dcache_rd_type_i(0),//同icache
            .dcache_wr_type_i(0),//写的数据量，3'b100表示连续写四个数据至相邻的地址；0表示只写一个数据
            .dcache_wr_data({{96{1'b0}},data[31:0]}),//128bit的写入数据，如果只想写一个那么只需要保证31:0正确
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

4. stallreq_if和stallreq_mem为暂停请求，因为AXI直接面向CPU，所以，在AXI进行读写数据时，CPU必须暂停，等到AXI完成读写数据的操作。连接到CTRL中。详情看具体的文件。注意stallreq_mem一定要在stallreq_if之前，不然取指和访存同时生效时，访存没法被暂停。
