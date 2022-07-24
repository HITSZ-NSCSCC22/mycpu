//lcd top to connect lcd to cpu
`include "axi_defines.sv"
module lcd_top (
    //rst and clk,clk is lower than cpu
    input logic pclk,
    input logic rst_n,

    /** from AXI **/
    //ar
    input logic [`ID] s_arid,  //arbitration
    input logic [`ADDR] s_araddr,
    input logic [`Len] s_arlen,
    input logic [`Size] s_arsize,
    input logic [`Burst] s_arburst,
    input logic [`Lock] s_arlock,
    input logic [`Cache] s_arcache,
    input logic [`Prot] s_arprot,
    input logic s_arvalid,
    output logic s_arready,

    //r
    output logic [`ID] s_rid,
    output logic [31:0] s_rdata,
    output logic [`Resp] s_rresp,
    output logic s_rlast,  //the last read data
    output logic s_rvalid,
    input logic s_rready,

    //aw
    input logic [`ID] s_awid,
    input logic [`ADDR] s_awaddr,
    input logic [`Len] s_awlen,
    input logic [`Size] s_awsize,
    input logic [`Burst] s_awburst,
    input logic [`Lock] s_awlock,
    input logic [`Cache] s_awcache,
    input logic [`Prot] s_awprot,
    input logic s_awvalid,
    output logic s_awready,

    //w
    input logic [`ID] s_wid,
    input logic [31:0] s_wdata,
    input logic [3:0] s_wstrb,  //字节选通位和sel差不多
    input logic s_wlast,
    input logic s_wvalid,
    output logic s_wready,

    //b
    output logic [`ID] s_bid,
    output logic [`Resp] s_bresp,
    output logic s_bvalid,
    input logic s_bready,

    /**display LCD**/
    output logic lcd_rst,
    output logic lcd_cs,
    output logic lcd_rs,
    output logic lcd_wr,
    output logic lcd_rd,
    inout logic [15:0] lcd_data_io,  //from/to lcd data
    output lcd_bl_ctr,

    /**touch LCD**/
    inout  logic lcd_ct_int,  //触摸屏中断信号
    inout  logic lcd_ct_sda,
    output logic lcd_ct_scl,
    output logic lcd_ct_rstn, //lcd触摸屏幕复位信号

    /**VGA**/
    output logic vga_wen,
    output logic [3:0] vga_wrow,
    output logic [3:0] vga_wcol,
    output logic [11:0] vga_wcolor

);
  //top <-> lcd_ctrl
  logic [31:0]lcd_input_data;

  // top <-> lcd_interface
  logic [15:0] lcd_data_i;
  logic [15:0] lcd_data_o;
  logic lcd_write_data_ctrl;
  logic [31:0] data_reg;
  assign lcd_data_i=lcd_data_io;
  assign lcd_data_io=lcd_write_data_ctrl?lcd_data_o:16'bz;

  //lcd_id <-> lcd_interface
  logic interface_busy;
  logic [15:0]id_data_interface;
  logic we;
  logic wr;
  logic id_lcd_rs_interface;
  logic id_fm;
  logic read_color;

  lcd_interface(
    .pclk(pclk),  //cycle time 20ns,50Mhz
    .rst_n(rst_n), //low is powerful

    //to lcd 
    /**屏幕显示信号**/
    .lcd_rst(lcd_rst),  //lcd 复位键
    .lcd_cs(lcd_cs),
    .lcd_rs(lcd_rs),  //0:inst 1:data
    .lcd_wr(lcd_wr),  //write signal ,low is powerful
    .lcd_rd(lcd_rd),  //read signal,low is powerful
    .lcd_data_i(lcd_data_i),  //from lcd
    .lcd_data_o(lcd_data_o),  //to lcd
    .lcd_bl_ctr(lcd_bl_ctr),  //

    //to lcd top
    .lcd_write_data_ctrl(lcd_write_data_ctrl),  //写控制信号，用于决定顶层的lcd_data_io
    .data_reg(data_reg),

    //from lcd_id
    .data_i(id_data_interface),
    .we(we),
    .wr(wr),
    .lcd_rs_i(id_lcd_rs_interface),  //distinguish inst or data
    .id_fm(id_fm),  //distinguish read id or read fm,0:id,1:fm
    .read_color(read_color),  //if read color ,reading time is at least 2

    //to lcd_id
    .busy(interface_busy)

  );

  //lcd_id <->lcd_ctrl
  logic ctrl_write_lcd_id;
  logic [31:0]ctrl_addr_id;
  logic [31:0]ctrl_data_id;
  logic write_ok;  

  lcd_id(
    .pclk(pclk),
    .rst_n(rst_n),
    //from lcd ctrl
    .write_lcd_i(ctrl_write_lcd_id),
    .lcd_addr_i(ctrl_addr_id),
    .lcd_data_i(ctrl_data_id),

    //to lcd ctrl
    .write_ok(write_ok),

    //to lcd interface
    .we(we),  //write enable
    .wr(wr),  //0:read lcd 1:write lcd,distinguish inst kind
    .lcd_rs(id_lcd_rs_interface),
    .data_o(id_data_interface),
    .id_fm(id_fm),
    .read_color_o(read_color),

    //from lcd inteface
    .busy(interface_busy)
  );

    lcd_ctrl(
    //rst and clk,clk is lower than cpu
    .pclk(pclk),
    .rst_n(rst_n),

    //from AXI
    //ar
    .s_arid(s_arid),  //arbitration
    .s_araddr(s_araddr),
    .s_arlen(s_arlen),
    .s_arsize(s_arsize),
    .s_arburst(s_arburst),
    .s_arlock(s_arlock),
    .s_arcache(s_arcache),
    .s_arprot(s_arprot),
    .s_arvalid(s_arvalid),
    .s_arready(s_arready),

    //r
    .s_rid(s_rid),
    .s_rdata(s_rdata),
    .s_rresp(s_rresp),
    .s_rlast(s_rlast),  //the last read data
    .s_rvalid(s_rvalid),
    .s_rready(s_rready),

    //aw
    .s_awid(s_awid),
    .s_awaddr(s_awaddr),
    .s_awlen(s_awlen),
    .s_awsize(s_awsize),
    .s_awburst(s_awburst),
    .s_awlock(s_awlock),
    .s_awcache(s_awcache),
    .s_awprot(s_awprot),
    .s_awvalid(s_awvalid),
    .s_awready(s_awready),

    //w
    .s_wid(s_wid),
    .s_wdata(s_wdata),
    .s_wstrb(s_wstrb),  //字节选通位和sel差不多
    .s_wlast(s_wlast),
    .s_wvalid(s_wvalid),
    .s_wready(s_wready),

    //b
    .s_bid(s_bid),
    .s_bresp(s_bresp),
    .s_bvalid(s_bvalid),
    .s_bready(s_bready),

    //to lcd_id
    .lcd_addr_buffer(ctrl_addr_id),  //store write reg addr
    .lcd_data_buffer(ctrl_data_id),  //store data to lcd
    .write_lcd(ctrl_write_lcd_id),  //write lcd enable signal

    //from lcd_interface
    //TODO
    .lcd_input_data(),  //data form lcd input

    //from lcd_id
    .write_ok(write_ok)  //数据和指令写出去后才能继续写
    );

endmodule
