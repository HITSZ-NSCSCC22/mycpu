//lcd top to connect lcd to cpu
`include "axi_defines.sv"
`include "lcd_types.sv"
module lcd_top
    import lcd_types::*;
(
    //rst and clk,clk is lower than cpu
    input logic pclk,
    input logic rst_n,

    /** from AXI **/
`ifdef AXI
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
`endif

    /**display LCD**/
    output logic lcd_rst,
    output logic lcd_cs,
    output logic lcd_rs,
    output logic lcd_wr,
    output logic lcd_rd,
    inout wire [15:0] lcd_data_io,  //from/to lcd data
    output lcd_bl_ctr,

    /**touch LCD**/
    inout  wire  lcd_ct_int,  //触摸屏中断信号
    inout  wire  lcd_ct_sda,
    output logic lcd_ct_scl,
    output logic lcd_ct_rstn, //lcd触摸屏幕复位信号

    /**VGA**/
    output logic vga_wen,
    output logic [3:0] vga_wrow,
    output logic [3:0] vga_wcol,
    output logic [11:0] vga_wcolor

);
    //default signal
    assign lcd_ct_int  = 1'bz;
    assign lcd_ct_sda  = 1'bz;
    assign lcd_ct_scl  = 1;
    assign lcd_ct_rstn = rst_n;

    //top <-> lcd_ctrl
    logic [31:0] lcd_input_data;

    // top <-> lcd_interface
    logic [15:0] lcd_data_i;
    logic [15:0] lcd_data_o;
    logic lcd_write_data_ctrl;
    logic [31:0] data_reg;
    assign lcd_data_i  = lcd_data_io;
    assign lcd_data_io = lcd_write_data_ctrl ? lcd_data_o : 16'bz;

    id_mux_struct id_mux_signal;
    init_mux_struct init_mux_signal;
    interface_mux_struct inter_mux_signal;

    lcd_mux u_lcd_mux (
        .pclk(pclk),
        .rst_n(rst_n),
        //from lcd_id
        .id_we(id_mux_signal.id_we),  //write enable
        .id_wr(id_mux_signal.id_wr),  //0:read lcd 1:write lcd,distinguish inst kind
        .id_lcd_rs(id_mux_signal.id_lcd_rs),
        .id_data_o(id_mux_signal.id_data),
        .id_fm_i(id_mux_signal.id_fm),
        .id_read_color_o(id_mux_signal.id_read_color),
        //to lcd_id
        .busy_o(id_mux_signal.busy),
        .write_color_ok_o(id_mux_signal.write_color_ok),  //write one color

        //from lcd_init
        .init_data(init_mux_signal.init_data),
        .init_we(init_mux_signal.init_we),
        .init_wr(init_mux_signal.init_wr),
        .init_rs(init_mux_signal.init_rs),
        .init_work(init_mux_signal.init_work),
        .init_finish(init_mux_signal.init_finish),
        //to lcd_init
        .init_write_ok_o(init_mux_signal.init_write_ok),

        //from lcd_interface
        .init_write_ok_i(inter_mux_signal.init_write_ok),
        .busy_i(inter_mux_signal.busy),
        .write_color_ok_i(inter_mux_signal.write_color_ok),  //write one color
        //to lcd_interface 
        .data_o(inter_mux_signal.data),
        .we_o(inter_mux_signal.we),
        .wr_o(inter_mux_signal.wr),
        .lcd_rs_o(inter_mux_signal.lcd_rs),  //distinguish inst or data
        .id_fm_o(inter_mux_signal.id_fm),  //distinguish read id or read fm,0:id,1:fm
        .read_color_o(inter_mux_signal.read_color)  //if read color ,reading time is at least 2
    );


    lcd_interface u_lcd_interface (
        .pclk (pclk),  //cycle time 20ns,50Mhz
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
        .lcd_bl_ctr(lcd_bl_ctr),

        //to lcd top
        .lcd_write_data_ctrl(lcd_write_data_ctrl),  //写控制信号，用于决定顶层的lcd_data_io
        .data_reg(data_reg),

        //from lcd_id
        .data_i(inter_mux_signal.data),
        .we(inter_mux_signal.we),
        .wr(inter_mux_signal.wr),
        .lcd_rs_i(inter_mux_signal.lcd_rs),  //distinguish inst or data
        .id_fm(inter_mux_signal.id_fm),  //distinguish read id or read fm,0:id,1:fm
        .read_color(inter_mux_signal.read_color),  //if read color ,reading time is at least 2

        //to lcd_id
        .busy(inter_mux_signal.busy),
        .write_color_ok(inter_mux_signal.write_color_ok),
        .init_write_ok(inter_mux_signal.init_write_ok)

    );

    //lcd_id <->lcd_ctrl
    logic ctrl_write_lcd_id;
    logic [31:0] ctrl_addr_id;
    logic [31:0] ctrl_data_id;
    logic write_ok;
    logic [31:0] ctrl_buffer_data_id;
    logic [31:0] ctrl_buffer_addr_id;
    logic data_valid;
    logic [31:0] graph_size;

    lcd_id u_lcd_id (
        .pclk(pclk),
        .rst_n(rst_n),
        //from lcd ctrl
        .write_lcd_i(data_valid),
        .lcd_addr_i(ctrl_buffer_addr_id),
        .lcd_data_i(ctrl_buffer_data_id),

        //speeder
        .buffer_addr_i(ctrl_buffer_addr_id),
        .buffer_data_i(ctrl_buffer_data_id),
        .data_valid(data_valid),
        .graph_size_i(graph_size),


        //to lcd ctrl
        .write_ok(write_ok),

        //to lcd interface
        .we(id_mux_signal.id_we),  //write enable
        .wr(id_mux_signal.id_wr),  //0:read lcd 1:write lcd,distinguish inst kind
        .lcd_rs(id_mux_signal.id_lcd_rs),
        .data_o(id_mux_signal.id_data),
        .id_fm(id_mux_signal.id_fm),
        .read_color_o(id_mux_signal.id_read_color),

        //from lcd inteface
        .busy(id_mux_signal.busy),
        .write_color_ok(id_mux_signal.write_color_ok)
    );
`ifdef AXI
    lcd_ctrl u_lcd_ctrl (
        //rst and clk,clk is lower than cpu
        .pclk (pclk),
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

        //speeder
        .buffer_data(ctrl_buffer_data_id),  //speeder
        .buffer_addr(ctrl_buffer_addr_id),  //speeder
        .data_valid(data_valid),  //tell lcd_id can write
        .graph_size(graph_size),

        //from lcd_interface
        //TODO
        .lcd_input_data(0),  //data form lcd input

        //from lcd_id
        .write_ok(write_ok)  //数据和指令写出去后才能继续写
    );
`else
    lcd_test_ctrl u_lcd_ctrl (
        //rst and clk,clk is lower than cpu
        .pclk(pclk),
        .rst_n(rst_n),
        //speeder
        .buffer_data(ctrl_buffer_data_id),  //speeder
        .buffer_addr(ctrl_buffer_addr_id),  //speeder
        .data_valid(data_valid),  //tell lcd_id
        .graph_size(graph_size),

        //from lcd_interface
        //TODO
        .lcd_input_data(0),  //data form lcd input

        //from lcd_id
        .write_ok(write_ok)  //æ•°ï¿½?ï¿½å’ŒæŒ‡ä»¤å†™å‡ºåŽ»ï¿½?ï¿½ï¿½?èƒ½ç»§ç»­å†™
    );
`endif

    lcd_init u_lcd_init (
        .pclk(pclk),
        .rst_n(rst_n),
        .init_write_ok(init_mux_signal.init_write_ok),
        .init_data(init_mux_signal.init_data),
        .we(init_mux_signal.init_we),
        .wr(init_mux_signal.init_wr),
        .rs(init_mux_signal.init_rs),
        .init_work(init_mux_signal.init_work),
        .init_finish(init_mux_signal.init_finish)
    );

    ila_0 lcd_top_debug (
        .clk(pclk),  // input wire clk


        .probe0(rst_n),  // input wire [0:0]  probe0  
        .probe1(lcd_cs),  // input wire [0:0]  probe1 
        .probe2(lcd_rs),  // input wire [0:0]  probe2 
        .probe3(lcd_wr),  // input wire [0:0]  probe3 
        .probe4(lcd_rd),  // input wire [0:0]  probe4 
        .probe5(lcd_data_io),  // input wire [15:0]  probe5 
        .probe6(lcd_rst),  // input wire [0:0]  probe6 
        .probe7(lcd_write_data_ctrl),  // input wire [0:0]  probe7 
        .probe8(count),  // input wire [31:0]  probe8 
        .probe9(0),  // input wire [31:0]  probe9 
        .probe10(lcd_data_o),  // input wire [15:0]  probe10 
        .probe11(0),  // input wire [31:0]  probe11 
        .probe12(graph_size),  // input wire [31:0]  probe12 
        .probe13(lcd_data_i),  // input wire [15:0]  probe13 
        .probe14(data_i),  // input wire [15:0]  probe14 
        .probe15(0),  // input wire [0:0]  probe15 
        .probe16(0),  // input wire [0:0]  probe16 
        .probe17(0),  // input wire [0:0]  probe17 
        .probe18(0),  // input wire [0:0]  probe18 
        .probe19(0),  // input wire [0:0]  probe19 
        .probe20(0),  // input wire [0:0]  probe20 
        .probe21(0),  // input wire [0:0]  probe21 
        .probe22(0),  // input wire [0:0]  probe22 
        .probe23(0),  // input wire [0:0]  probe23 
        .probe24(0),  // input wire [0:0]  probe24 
        .probe25(0),  // input wire [0:0]  probe25 
        .probe26(0),  // input wire [0:0]  probe26 
        .probe27(0),  // input wire [0:0]  probe27 
        .probe28(0),  // input wire [0:0]  probe28 
        .probe29(0)  // input wire [0:0]  probe29
    );
endmodule
