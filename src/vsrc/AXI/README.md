# AXI总线说明

## 目录结构
```
   AXI/                         # 本目录
        axi_master              # axi主机接口，接入cpu_top
        axi_defines.v           # 定义了宏的文件
```

## 接口说明
```
    时钟和复位信号
    input wire aclk,
    input wire aresetn, //low is valid

    来自cpu和输出到cpu的信号，其中只有cpu_data_o和stallreq是输出的。
    //CPU
    input wire [`ADDR]cpu_addr_i,
    input wire cpu_ce_i,
    input wire [`Data]cpu_data_i,
    input wire cpu_we_i ,
    input wire [3:0]cpu_sel_i, 
    input wire stall_i,
    input wire flush_i,
    output reg [`Data]cpu_data_o,//指令
    output wire stallreq,//暂停信号
    input wire [3:0]id,//决定是读数据还是取指令
    

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
   * 仅验证读功能的axi接口，取值id接口`4’b0000`,取数id接口`4'b0001`
   ```      
          //AXI Master interface for fetch instruction channel
            wire aresetn=~rst;
            wire axi_stall=&stall;
            wire stallreq_from_if;
            wire [31:0]inst_data_from_axi;

            //接口实例化
            axi_Master inst_interface(
            .aclk(clk),
            .aresetn(aresetn), //low is valid
    
    //CPU
            .cpu_addr_i(pc),
            .cpu_ce_i(chip_enable),
            .cpu_data_i(0),
            .cpu_we_i(0) ,
            .cpu_sel_i(4'b1111), 
            .stall_i(axi_stall),
            .flush_i(0),
            .cpu_data_o(inst_data_from_axi),
            .stallreq(stallreq_from_if),
            .id(4'b0000),//决定是读数据还是取指令

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
            .s_wstrb(i_wstrb),//字节选通位和sel差不多
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


2. inst_data_from_axi为从ram中取到的数据，建议直接放到if_buffer中，以实现pc和inst的对齐。stallreq_if为暂停请求，连接到CTRL中。ctrl和if_buffer的暂停逻辑重写。详情看具体的文件。
* [ctrl文件](../vsrc/ctrl.v)
* [if_buffer](../vsrc/if_buffer.v)
