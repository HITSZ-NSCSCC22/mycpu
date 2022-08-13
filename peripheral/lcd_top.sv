//lcd top to connect lcd to cpu
`include "axi_defines.sv"
`include "lcd_types.sv"
module lcd_top
import lcd_types::*;
    (
        //rst and clk,clk is lower than cpu
        input logic clk,//100Mhz
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
        output logic lcd_ct_rstn //lcd触摸屏幕复位信号

        // /**VGA**/
        // output logic vga_wen,
        // output logic [3:0] vga_wrow,
        // output logic [3:0] vga_wcol,
        // output logic [11:0] vga_wcolor

    );
    //debug signal
    logic [31:0]debug_buffer_state;
    logic [31:0]debug_inst_num;
    logic [31:0]debug_current_state;
    logic [31:0]debug_next_state;
    logic [9:0]debug_refresh_addra;
    logic [15:0]debug_refresh_data;
    logic debug_refresh_flag;
    logic debug_is_main;
    logic [31:0]debug_w_state;
    logic [31:0]debug_r_state;

    logic pclk;
    logic ts_clk;
    clk_wiz_0 clk_pll
              (
                  // Clock out ports
                  .clk_out1(ts_clk),     // 10Mhz
                  .clk_out2(pclk),     // 50Mhz
                  // Clock in ports
                  .clk_in1(clk));      // input clk_in1

    //core <-> *
    logic touch_flag;
    logic release_flag;
    logic [31:0]coordinate;
    logic core_enable;
    logic cpu_draw;
    logic [31:0]touch_reg;
    logic init_main_core;
    logic init_finish_core;
    logic cpu_work;
    lcd_core u_lcd_core(
                 .pclk(pclk),
                 .rst_n(rst_n),

                 //from lcd_init
                 .init_finish(init_finish_core),
                 //to lcd_init
                 .init_main(init_main_core),

                 //to lcd_ctrl
                 .touch_reg(touch_reg),
                 .cpu_work(cpu_work),
                 //to lcd_mux
                 .cpu_draw(cpu_draw),

                 //from lcd_touch_scanner
                 .touch_flag(touch_flag),//1表示碰到触碰点
                 .release_flag(release_flag), //it would be set as 1 when the coordinate is ready，1表示手松开
                 .coordinate(coordinate),  //{x_low,x_high,y_low,y_high}
                 //to lcd_touch_scanner
                 .enable(core_enable)//触摸屏开始工作

             );


    lcd_touch_scanner u_lcd_touch_scanner(
                          .ts_clk(ts_clk),//10Mhz
                          .resetn(rst_n),
                          .touch_flag(touch_flag),//1表示触碰点有效
                          .release_flag(release_flag), //it would be set as 1 when the coordinate is ready
                          .coordinate(coordinate),  //{x_low,x_high,y_low,y_high}
                          .enable(core_enable),//触摸屏开始工作
                          .lcd_int(lcd_ct_int),
                          .lcd_sda(lcd_ct_sda),
                          .lcd_ct_scl(lcd_ct_scl),
                          .lcd_ct_rstn(lcd_ct_rstn)
                      );


    //top <-> lcd_ctrl
    logic [31:0] lcd_input_data;

    // top <-> lcd_interface
    wire [15:0] lcd_data_i;
    wire [15:0] lcd_data_o;
    wire lcd_write_data_ctrl;
    logic [31:0] data_reg;
    assign lcd_data_i  = lcd_data_io;
    assign lcd_data_io = (lcd_write_data_ctrl==1'b1) ? lcd_data_o : 16'bz;
    logic [15:0]data_i;
    always_ff @(posedge pclk) begin
        if(~rst_n)
            data_i<=0;
        else
            data_i<=lcd_data_i;
    end
    // lcd_id ,lcd_init <-> mux <-> lcd_interface
    id_mux_struct id_mux_signal;
    init_mux_struct init_mux_signal;
    interface_mux_struct inter_mux_signal;

    lcd_mux u_lcd_mux (
                .pclk(pclk),
                .rst_n(rst_n),
                //from cpu draw
                .cpu_draw(cpu_draw),
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

                //from lcd_core
                .cpu_work(cpu_work),
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
    logic ctrl_refresh_id;
    logic ctrl_refresh_rs_id;
    logic ctrl_char_color_id;
    logic ctrl_char_rs_id;
    lcd_id u_lcd_id (
               .pclk(pclk),
               .rst_n(rst_n),
               //from lcd ctrl
               .write_lcd_i(data_valid),
               .lcd_addr_i(ctrl_buffer_addr_id),
               .lcd_data_i(ctrl_buffer_data_id),
               .refresh_i(ctrl_refresh_id),
               .refresh_rs_i(ctrl_refresh_rs_id),

               //speeder
               .buffer_addr_i(ctrl_buffer_addr_id),
               .buffer_data_i(ctrl_buffer_data_id),
               .data_valid(data_valid),
               .graph_size_i(graph_size),
               .char_color_i(ctrl_char_color_id),
               .char_rs_i(ctrl_char_rs_id),
               //from lcd_core
               .cpu_work(cpu_work),

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
               .write_color_ok(id_mux_signal.write_color_ok),

               //debug
               .debug_current_state(debug_current_state),
               .debug_next_state(debug_next_state)
           );

    //lcd_ctrl <-> lcd_refresh
    logic enable;
    logic [6:0]refresh_req;//用于决定刷新的种类，
    logic [15:0]refresh_data;
    logic data_ok;
    logic refresh_ok;//refresh is over
    logic refresh_rs;

    //lcd_ctrl <-> char_ctrl
    logic [31:0]cpu_code;
    logic char_work;
    logic char_write_ok;
    logic [15:0]char_data;
    logic char_color_ok;
    logic write_str_end;

`ifdef AXI
    //TODO
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

                 //speeder
                 .buffer_data(ctrl_buffer_data_id),  //speeder
                 .buffer_addr(ctrl_buffer_addr_id),  //speeder
                 .data_valid(data_valid),  //tell lcd_id
                 .graph_size(graph_size),
                 .refresh(ctrl_refresh_id),
                 .refresh_rs_o(ctrl_refresh_rs_id),
                 .char_color(ctrl_char_color_id),
                 .char_rs(ctrl_char_rs_id),
                 //from lcd_interface
                 //TODO
                 .lcd_input_data(0),  //data form lcd input

                //from/to lcd_refresh
                 .enable(enable),
                 .refresh_req(refresh_req),//用于决定刷新的种类，
                 .refresh_data(refresh_data),
                 .data_ok(data_ok),
                 .refresh_ok_i(refresh_ok),
                 .refresh_rs_i(refresh_rs),
                 //from lcd_core
                 .touch_reg(touch_reg),
                 .cpu_work(cpu_work),
                 //from lcd_id
                 .write_ok(write_ok),  //æ•°ï¿½?ï¿½å’ŒæŒ‡ä»¤å†™å‡ºåŽ»ï¿½?ï¿½ï¿½?èƒ½ç»§ç»­å†™
                 .debug_buffer_state(debug_buffer_state),
                 .debug_inst_num(debug_inst_num),
                 .debug_r_state(debug_r_state),
                 .debug_w_state(debug_w_state),

                 //to char_ctrl
                 .cpu_code(cpu_code),
                 .char_work(char_work),
                 .char_write_ok(char_write_ok),

                 //from char_ctrl
                 .char_data_i(char_data),
                 .char_color_ok(char_color_ok),
                 .write_str_end(write_str_end)
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
                      .refresh(ctrl_refresh_id),
                      .refresh_rs_o(ctrl_refresh_rs_id),
                      .char_color(ctrl_char_color_id),
                      .char_rs(ctrl_char_rs_id),
                      //from lcd_interface
                      //TODO
                      .lcd_input_data(0),  //data form lcd input

                      //from/to lcd_refresh
                      .enable(enable),
                      .refresh_req(refresh_req),//用于决定刷新的种类，
                      .refresh_data(refresh_data),
                      .data_ok(data_ok),
                      .refresh_ok_i(refresh_ok),
                      .refresh_rs_i(refresh_rs),
                      //from lcd_core
                      .touch_reg(touch_reg),
                      .cpu_work(cpu_work),
                      //from lcd_id
                      .write_ok(write_ok),  //æ•°ï¿½?ï¿½å’ŒæŒ‡ä»¤å†™å‡ºåŽ»ï¿½?ï¿½ï¿½?èƒ½ç»§ç»­å†™
                      .debug_buffer_state(debug_buffer_state),
                      .debug_inst_num(debug_inst_num),

                      //to char_ctrl
                      .cpu_code(cpu_code),
                      .char_work(char_work),
                      .char_write_ok(char_write_ok),

                      //from char_ctrl
                      .char_data_i(char_data),
                      .char_color_ok(char_color_ok),
                      .write_str_end(write_str_end)
                  );
`endif

    logic [31:0]debug_col;
    logic debug_char_req;
    logic [23:0]debug_char_douta;
    logic debug_char_data_ok;
    logic debug_char_finish;
    logic [5:0]debug_x;
    logic [5:0]debug_y;
    logic [31:0]debug_char_ctrl_state;
    char_ctrl u_char_ctrl(
                  .pclk(pclk),
                  .rst_n(rst_n),

                  //from lcd_ctrl
                  .cpu_code(cpu_code),
                  .char_work(char_work),
                  .write_ok(char_write_ok),

                  //to lcd_ctrl
                  .data_o(char_data),
                  .color_ok(char_color_ok),
                  .write_str_end(write_str_end),

                  //debug
                  .debug_col(debug_col),
                  .debug_char_req(debug_char_req),
                  .debug_char_douta(debug_char_douta),
                  .debug_char_data_ok(debug_char_data_ok),
                  .debug_char_finish(debug_char_finish),
                  .debug_x(debug_x),
                  .debug_y(debug_y),
                  .debug_char_ctrl_state(debug_char_ctrl_state)
              );

    lcd_refresh u_lcd_refresh(
                    .pclk(pclk),
                    .rst_n(rst_n),
                    //from lcd_ctrl
                    .enable(enable),
                    .refresh_req(refresh_req),//to choose the background
                    .refresh_data(refresh_data),
                    .refresh_rs(refresh_rs),
                    .data_ok(data_ok),
                    .refresh_ok(refresh_ok)//refresh is over
                );
    logic [17:0]addra;
    lcd_init u_lcd_init (
                 .pclk(pclk),
                 .rst_n(rst_n),
                 .init_write_ok(init_mux_signal.init_write_ok),
                 .init_data(init_mux_signal.init_data),
                 .init_addra(addra),
                 .we(init_mux_signal.init_we),
                 .wr(init_mux_signal.init_wr),
                 .rs(init_mux_signal.init_rs),
                 .init_work(init_mux_signal.init_work),
                 .init_finish(init_mux_signal.init_finish),
                 .init_main(init_main_core),

                 //debug
                 .debug_refresh_addra(debug_refresh_addra),
                 .debug_refresh_data(debug_refresh_data),
                 .debug_refresh_flag(debug_refresh_flag),
                 .debug_is_main(debug_is_main)

             );
    assign init_finish_core=init_mux_signal.init_finish;

    ila_0 lcd_top_debug (
              .clk(pclk),  // input wire clk
              .probe0(rst_n),  // input wire [0:0]  probe0
              .probe1(lcd_cs),  // input wire [0:0]  probe1
              .probe2(lcd_rs),  // input wire [0:0]  probe2
              .probe3(lcd_wr),  // input wire [0:0]  probe3
              .probe4(lcd_rd),  // input wire [0:0]  probe4
              .probe5(lcd_data_io),  // input wire [15:0]  probe5
              .probe6(lcd_rst),  // input wire [0:0]  probe6
              .probe7(s_arvalid),  // input wire [0:0]  probe7
              .probe8(debug_w_state),  // input wire [31:0]  probe8
              .probe9(debug_r_state),  // input wire [31:0]  probe9
              .probe10(lcd_data_o),  // input wire [15:0]  probe10
              .probe11(s_araddr),  // input wire [31:0]  probe11
              .probe12(graph_size),  // input wire [31:0]  probe12
              .probe13(lcd_data_i),  // input wire [15:0]  probe13
              .probe14(touch_reg),  // input wire [31:0]  probe14
              .probe15(s_wstrb),  // input wire [3:0]  probe15
              .probe16(s_awvalid),  // input wire [0:0]  probe16
              .probe17(s_awready),  // input wire [0:0]  probe17
              .probe18(s_wvalid),  // input wire [0:0]  probe18
              .probe19(refresh_ok),  // input wire [0:0]  probe19
              .probe20(s_rdata),  // input wire [31:0]  probe20
              .probe21(s_wready),  // input wire [0:0]  probe21
              .probe22(s_wlast),  // input wire [0:0]  probe22
              .probe23(s_wdata),  // input wire [31:0]  probe23
              .probe24(s_awaddr),  // input wire [31:0]  probe24
              .probe25(debug_next_state),  // input wire [31:0]  probe25
              .probe26(debug_current_state),  // input wire [31:0]  probe26
              .probe27(debug_inst_num),  // input wire [31:0]  probe27
              .probe28(debug_buffer_state),  // input wire [31:0]  probe28
              .probe29(0),  // input wire [16:0]  probe29
              .probe30(s_bvalid), // input wire [0:0]  probe30
              .probe31(s_bready), // input wire [0:0]  probe31
              .probe32(init_mux_signal.init_finish), // input wire [0:0]  probe32
              .probe33(s_arready), // input wire [0:0]  probe33
              .probe34(s_rlast), // input wire [0:0]  probe34
              .probe35(s_rvalid), // input wire [0:0]  probe35
              .probe36(s_rready), // input wire [0:0]  probe36
              .probe37(cpu_draw), // input wire [0:0]  probe37
              .probe38(0), // input wire [0:0]  probe38
              .probe39(0) // input wire [15:0]  probe39
          );

endmodule
