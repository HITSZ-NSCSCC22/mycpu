//to connect with CPU and translate AXI to lcd signal
`include "axi_defines.sv"
`define LCD_INPUT 32'h1fd0c000
`define TOUCH_INPUT 32'h1fd0c004
module lcd_test_ctrl (
        //rst and clk,clk is lower than cpu
        input logic pclk,
        input logic rst_n,

        //to lcd_id
        // output logic [31:0] lcd_addr_buffer,  //store write reg addr
        // output logic [31:0] lcd_data_buffer,  //store data to lcd
        // output logic write_lcd,  //write lcd enable signal

        //speeder
        output logic [31:0]buffer_data,//speeder
        output logic [31:0]buffer_addr,//speeder
        output logic data_valid,//tell lcd_id
        output logic [31:0]graph_size,
        output logic refresh,
        output logic refresh_rs_o,
        //from lcd_interface
        input logic [31:0] lcd_input_data,  //data form lcd input

        //from/to lcd_refresh
        output logic enable,
        output logic [6:0]refresh_req,//用于决定刷新的种类，
        input logic [15:0]refresh_data,
        input logic data_ok,
        input logic refresh_ok_i,
        input logic refresh_rs_i,

        //from lcd_id
        input logic write_ok,  //数�?�和指令写出去�?��?能继续写

        //from lcd_core
        input logic [31:0]touch_reg,
        input logic cpu_work,

        //debug
        output [31:0] debug_buffer_state,
        output [31:0] debug_inst_num
    );
    enum logic [2:0] {
             R_ADDR = 3'b001,
             R_DATA = 3'b010
         } r_state;
    enum logic [2:0] {
             W_IDLE = 3'b011,
             W_ADDR = 3'b100,
             W_DATA = 3'b101,
             W_RESP = 3'b110
         } w_state;
    enum int{
             IDLE,
             GRAPH,
             DISPATCH_GRAPH,//send graph inst to lcd_id
             WAITING,
             REFRESH
         } buffer_state;
    logic [31:0] addr_buffer;

    /*******************************************/
    /**lcd buffer to store the wdata form AXI**/
    /*******************************************/
    logic dispatch_ok;//表示能够�?�射inst到lcd_id
    logic [3:0]delay_time;//匹�?lcd_ctrl和lcd_id的�?�手
    assign dispatch_ok=(delay_time==2)?1:0;

    logic [31:0]inst_num;
    logic [31:0]count;
    logic [31:0]graph_buffer[0:6];
    logic [31:0]graph_addr[0:6];
    logic buffer_ok;//when buffer is full,drawing lcd
    logic refresh_ok;
    /**画一次图需�?6�?�连续的sw指令，所以绘图时�?�需�?存储连续的6�?�sw指令�?��?�**/
    always_ff @( posedge pclk ) begin : lcd_buffer
        if(~rst_n||~cpu_work) begin
            for(integer i=0;i<7;i++) begin
                graph_buffer[i]<=32'b0;
                graph_addr[i]<=32'b0;
            end
            buffer_state<=IDLE;
            buffer_ok<=0;
            count<=0;
            buffer_data<=0;
            buffer_addr<=0;
            inst_num<=0;
            data_valid<=0;
            delay_time<=2;
            graph_size<=0;
            enable<=0;
            refresh_req<=0;
            refresh_ok<=0;
            refresh<=0;
            refresh_rs_o<=0;
        end
        else begin
            case(buffer_state)
                IDLE: begin

                    count<=0;
                    buffer_addr<=0;
                    buffer_data<=0;
                    inst_num<=0;
                    data_valid<=0;
                    delay_time<=2;
                    // buffer_state<=GRAPH;
                    // enable<=0;
                    // buffer_ok<=0;
                    buffer_state<=REFRESH;
                    enable<=1;
                    buffer_ok<=1;
                    graph_size<=0;
                    refresh_req<=0;
                    refresh_ok<=0;
                    refresh<=0;
                    refresh_rs_o<=0;
                end
                GRAPH: begin
                    //连续缓存6条sw
                    graph_buffer[0]<=32'h3600_0000;
                    graph_buffer[1]<=32'h2a00_0028;
                    graph_buffer[2]<=32'h2a02_01B7;
                    graph_buffer[3]<=32'h2b00_0028;
                    graph_buffer[4]<=32'h2b02_02F7;
                    graph_buffer[5]<=32'h2c00_FF45;
                    graph_buffer[6]<=32'h0004_4175;
                    buffer_state<=DISPATCH_GRAPH;
                end
                //to dispatch inst to lcd_id
                DISPATCH_GRAPH: begin
                    if(write_ok&&dispatch_ok&&inst_num<=5) begin
                        inst_num<=inst_num+1;
                        buffer_addr<=graph_addr[inst_num];
                        buffer_data<=graph_buffer[inst_num];
                        graph_size<=graph_buffer[6];
                        data_valid<=1;
                        delay_time<=0;
                    end
                    //发射完后必须要延迟两秒等待id工作，不然会捕获到上一次的write_ok
                    else if(~dispatch_ok&&inst_num<=6) begin
                        delay_time<=delay_time+1;
                        data_valid<=0;
                    end
                    else if(write_ok&&inst_num==6) begin
                        //buffer is empty,receive new data from cpu
                        for(integer i=0;i<7;i++) begin
                            graph_buffer[i]<=32'b0;
                            graph_addr[i]<=32'b0;
                        end
                        buffer_state<=WAITING;
                        buffer_ok<=0;
                        count<=0;
                        buffer_data<=0;
                        buffer_addr<=0;
                        inst_num<=0;
                        data_valid<=0;
                        delay_time<=2;
                        graph_size<=0;
                        enable<=0;
                        refresh_req<=0;
                        refresh_ok<=0;
                        refresh<=0;
                        refresh_rs_o<=0;
                    end
                end
                WAITING: begin
                    buffer_state<=buffer_state;
                end
                REFRESH: begin
                    if(data_ok) begin
                        enable<=0;
                        buffer_data<={{16{1'b0}},refresh_data};
                        buffer_addr<=0;
                        graph_size<=0;
                        data_valid<=1;
                        delay_time<=0;
                        refresh_ok<=refresh_ok_i;
                        refresh<=1;
                        refresh_rs_o<=refresh_rs_i;
                    end
                    else if(~dispatch_ok) begin//delay to wait lcd_id work
                        delay_time<=delay_time+1;
                        data_valid<=0;
                        refresh<=0;
                        refresh_rs_o<=0;
                    end
                    else if(write_ok) begin
                        if(refresh_ok) begin
                            buffer_state<=GRAPH;
                            buffer_ok<=0;
                            count<=0;
                            buffer_data<=0;
                            buffer_addr<=0;
                            inst_num<=0;
                            data_valid<=0;
                            delay_time<=2;
                            enable<=0;
                            refresh_req<=0;
                            refresh_ok<=0;
                            refresh<=0;
                            refresh_rs_o<=0;
                        end
                        else begin
                            enable<=1;
                        end
                    end
                end
                default: begin
                    for(integer i=0;i<7;i++) begin
                        graph_buffer[i]<=32'b0;
                        graph_addr[i]<=32'b0;
                    end
                    buffer_state<=IDLE;
                    buffer_ok<=0;
                    count<=0;
                    buffer_data<=0;
                    buffer_addr<=0;
                    inst_num<=0;
                    data_valid<=0;
                    delay_time<=2;
                    graph_size<=0;
                    enable<=0;
                    refresh_req<=0;
                    refresh_ok<=0;
                    refresh<=0;
                    refresh_rs_o<=0;
                end
            endcase
        end
    end
    //debug
    assign debug_buffer_state=buffer_state;
    assign debug_inst_num=inst_num;
endmodule
