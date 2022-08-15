//to connect with CPU and translate AXI to lcd signal
`include "lcd_axi_defines.sv"
`define LCD_INPUT 32'h1fd0c000
`define TOUCH_INPUT 32'h1fd0c004
`define WRITE_GRAPH   32'h1fd0c008
`define WRITE_CHAR  32'h1fd0c00c
`define WRITE_VGA   32'h1fd0c010
`define WRITE_REFRESH 32'h1fd0c014

module lcd_ctrl (
        //rst and clk,clk is lower than cpu
        input logic pclk,
        input logic rst_n,

        //from AXI
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
        input logic [3:0] s_wstrb,  //字节选�?�位和sel差不�?
        input logic s_wlast,
        input logic s_wvalid,
        output logic s_wready,

        //b
        output logic [`ID] s_bid,
        output logic [`Resp] s_bresp,
        output logic s_bvalid,
        input logic s_bready,

        //speeder
        output logic [31:0]buffer_data,//speeder
        output logic [31:0]buffer_addr,//speeder
        output logic data_valid,//tell lcd_id can receive data
        output logic [31:0]graph_size,
        output logic refresh,
        output logic refresh_rs_o,
        output logic char_color,
        output logic char_rs,

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
        input logic write_ok,  //数据和指令写出去后才能继续写

        //from lcd_core
        input logic [31:0]touch_reg,
        input logic cpu_work,

        //to char_ctrl
        output logic [31:0]cpu_code,//选择字符
        output logic char_work,
        output logic char_write_ok,

        //from char_ctrl
        input logic [15:0]char_data_i,
        input logic char_color_ok,
        input logic write_str_end,

        //debug
        output logic [31:0]debug_buffer_state,
        output logic [31:0]debug_inst_num,
        output logic [31:0]debug_r_state,
        output logic [31:0]debug_w_state
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
             CHAR,
             DISPATCH_GRAPH,//send graph inst to lcd_id
             DISPATCH_CHAR,//send char inst to lcd_id
             DISPATCH_CHAR_COLOR,//send char color data to lcd_id,字符的绘画需要对每个像素点进行监�?
             WAITING,
             REFRESH

         } buffer_state;
    logic [31:0] addr_buffer;
    assign s_rresp = 0;

    //Read form lcd
    always_ff @(posedge pclk) begin
        if (~rst_n) begin
            r_state <= R_ADDR;
            s_rid <= 0;
            addr_buffer <= 0;
            s_arready <= 1;
            s_rdata <= 0;
            s_rlast <= 0;
            s_rvalid <= 0;
        end
        else begin
            case (r_state)
                R_ADDR: begin
                    if (s_arvalid && s_arready) begin
                        r_state <= R_DATA;
                        s_rid <= s_arid;
                        addr_buffer <= s_araddr;
                        s_arready <= 0;
                        s_rdata <= 0;
                        s_rlast <= 0;
                        s_rvalid <= 0;
                    end
                    else begin
                        r_state <= R_ADDR;
                        s_rid <= 0;
                        addr_buffer <= 0;
                        s_arready <= 1;
                        s_rdata <= 0;
                        s_rlast <= 0;
                        s_rvalid <= 0;
                    end

                end
                R_DATA: begin
                    if (s_rvalid && s_rready) begin
                        r_state <= R_ADDR;
                        s_rid <= 0;
                        addr_buffer <= 0;
                        s_arready <= 1;
                        s_rdata <= 0;
                        s_rlast <= 0;
                        s_rvalid <= 0;
                    end
                    else begin
                        //choose data by addr
                        case (addr_buffer)
                            //TODO
                            `LCD_INPUT:
                                s_rdata <= touch_reg;
                            `TOUCH_INPUT:
                                s_rdata <= 32'hffff_ffff;
                            default:
                                s_rdata <= 0;
                        endcase
                        r_state <= r_state;
                        s_rid <= s_rid;
                        addr_buffer <= addr_buffer;
                        s_arready <= 1;
                        s_rlast <= 1;
                        s_rvalid <= 1;
                    end
                end
                default: begin
                    r_state <= R_ADDR;
                    s_rid <= 0;
                    addr_buffer <= 0;
                    s_arready <= 1;
                    s_rdata <= 0;
                    s_rlast <= 0;
                    s_rvalid <= 0;
                end
            endcase
        end
    end

    assign s_bid   = 0;
    assign s_bresp = 0;
    logic buffer_ok;//when buffer is full,drawing lcd
    logic [31:0] lcd_addr_buffer; //store write reg addr
    logic [31:0] lcd_data_buffer; //store data to lcd
    logic write_lcd;  //write lcd enable signal
    //Write to lcd
    always_ff @(posedge pclk) begin
        if (~rst_n) begin
            w_state <= W_IDLE;
            s_awready <= 0;
            s_wready <= 0;
            s_bvalid <= 0;
            lcd_addr_buffer <= 0;
            lcd_data_buffer <= 0;
            write_lcd <= 0;
        end
        else begin
            case (w_state)
                W_IDLE: begin   //使用buffer时，只需要把write_ok换成!buffer_ok
                    if(!buffer_ok)// lcd is not busy,allow to write lcd now
                    begin
                        w_state <= W_ADDR;
                        s_awready <= 1;
                        s_wready <= 0;
                        s_bvalid <= 0;
                        lcd_addr_buffer <= 0;
                        lcd_data_buffer <= 0;
                        write_lcd <= 0;
                    end
                    else begin
                        w_state <= W_IDLE;
                        s_awready <= 0;
                        s_wready <= 0;
                        s_bvalid <= 0;
                        lcd_addr_buffer <= 0;
                        lcd_data_buffer <= 0;
                        write_lcd <= 0;
                    end
                end
                W_ADDR: begin
                    if (s_awvalid && s_awready) begin
                        w_state <= W_DATA;
                        s_awready <= 0;
                        s_wready <= 1;
                        s_bvalid <= 0;
                        lcd_addr_buffer <= s_awaddr;
                        lcd_data_buffer <= 0;
                        write_lcd <= 0;
                    end
                end
                W_DATA: begin
                    if (s_wvalid && s_wready&&s_wlast) begin
                        w_state <= W_RESP;
                        s_awready <= 0;
                        s_wready <= 0;
                        s_bvalid <= 0;
                        lcd_addr_buffer <= lcd_addr_buffer;
                        lcd_data_buffer <= s_wdata;
                        write_lcd <= 1&&(s_wstrb==4'b1111);
                    end
                end
                W_RESP: begin
                    if (s_bvalid && s_bready) begin
                        w_state <=  W_IDLE;
                        s_awready <= 0;
                        s_wready <= 0;
                        s_bvalid <= 0;
                        lcd_addr_buffer <= 0;
                        lcd_data_buffer <= 0;
                        write_lcd <= 0;
                    end
                    else begin
                        w_state <= W_RESP;
                        s_awready <= 0;
                        s_wready <= 0;
                        s_bvalid <= 1;
                        lcd_addr_buffer <= lcd_addr_buffer;
                        lcd_data_buffer <= lcd_data_buffer;
                        write_lcd <= write_lcd;
                    end
                end
                default: begin
                    w_state <= W_IDLE;
                    s_awready <= 0;
                    s_wready <= 0;
                    s_bvalid <= 0;
                    lcd_addr_buffer <= 0;
                    lcd_data_buffer <= 0;
                    write_lcd <= 0;
                end
            endcase
        end
    end

    /*******************************************/
    /**lcd buffer to store the wdata form AXI**/
    /*******************************************/
    logic dispatch_ok;//表示能够发射inst到lcd_id
    logic [3:0]delay_time;//匹配lcd_ctrl和lcd_id的握�?
    assign dispatch_ok=(delay_time==2)?1:0;

    logic [31:0]inst_num;
    logic [31:0]count;
    logic [31:0]graph_buffer[0:6];
    logic [31:0]graph_addr[0:6];
    logic [31:0]char_buffer[0:6];
    logic [31:0]char_addr[0:6];
    logic refresh_ok;
    /**画一次图�?�?6条连续的sw指令，所以绘图时只需要存储连续的6条sw指令即可**/
    always_ff @( posedge pclk ) begin : lcd_buffer
        if(~rst_n||~cpu_work) begin
            for(integer i=0;i<7;i++) begin
                graph_buffer[i]<=32'b0;
                graph_addr[i]<=32'b0;
                char_addr[i]<=32'b0;
                char_buffer[i]<=32'b0;
            end
            buffer_state<=IDLE;
            buffer_ok<=1;//复位状�?�下不能接受CPU的任何写请求
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
            char_color<=0;
            cpu_code<=0;
            char_work<=0;
            char_write_ok<=0;
            char_rs<=0;
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
                    graph_size<=0;
                    refresh_req<=0;
                    refresh_ok<=0;
                    refresh<=0;
                    refresh_rs_o<=0;
                    char_color<=0;
                    cpu_code<=0;
                    char_work<=0;
                    char_write_ok<=0;
                    char_rs<=0;
                    if(s_awvalid&&s_awready) begin
                        case(s_awaddr)
                            `WRITE_GRAPH: begin
                                buffer_state<=GRAPH;
                                enable<=0;
                                buffer_ok<=0;
                            end
                            `WRITE_CHAR: begin
                                buffer_state<=CHAR;
                                enable<=0;
                                buffer_ok<=0;
                            end
                            `WRITE_VGA: begin
                                buffer_state<=IDLE;
                                enable<=0;
                                buffer_ok<=0;
                            end
                            `WRITE_REFRESH:begin
                                buffer_state<=REFRESH;
                                enable<=1;
                                buffer_ok<=1;
                            end
                            default:begin
                                buffer_state<=IDLE;
                                enable<=0;
                                buffer_ok<=0;
                            end
                        endcase
                    end
                    else begin
                            buffer_ok<=0;
                            buffer_state<=IDLE;
                            enable<=0;
                    end
                end
                CHAR:begin //连续缓存6条sw
                    if(s_wvalid&&s_wready&&w_state==W_DATA&&s_wstrb==4'b1111) begin
                        case(count)
                        //3600
                            0: begin
                                char_addr[0]<=lcd_addr_buffer;
                                char_buffer[0]<=s_wdata;
                            end
                        //2a00,2a01
                            1: begin
                                char_addr[1]<=lcd_addr_buffer;
                                char_buffer[1]<=s_wdata;
                            end
                        //2a02,2a03
                            2: begin
                                char_addr[2]<=lcd_addr_buffer;
                                char_buffer[2]<=s_wdata;
                            end
                        //2b00,2b01
                            3: begin
                                char_addr[3]<=lcd_addr_buffer;
                                char_buffer[3]<=s_wdata;
                            end
                        //2b02,2b03
                            4: begin
                                char_addr[4]<=lcd_addr_buffer;
                                char_buffer[4]<=s_wdata;
                            end
                        //存储字符的信息，用来选择字符，目前只存储ASCII�?
                            5:begin
                                char_addr[5]<=lcd_addr_buffer;
                                char_buffer[5]<=s_wdata;
                            end
                            default: begin
                                char_addr<=char_addr;
                                char_buffer<=char_buffer;
                            end
                        endcase
                        count<=count+1;
                        if(count==5)  begin
                            buffer_ok<=1;//buffuer is full,AXI can't receive new wdata
                            buffer_state<=DISPATCH_CHAR;//dispatch inst to lcd_id
                        end
                    end
                end
                GRAPH: begin
                    //连续缓存7条sw
                    if(s_wvalid&&s_wready&&w_state==W_DATA&&s_wstrb==4'b1111) begin
                        case(count)
                            0: begin
                                graph_addr[0]<=lcd_addr_buffer;
                                graph_buffer[0]<=s_wdata;
                            end
                            1: begin
                                graph_addr[1]<=lcd_addr_buffer;
                                graph_buffer[1]<=s_wdata;
                            end
                            2: begin
                                graph_addr[2]<=lcd_addr_buffer;
                                graph_buffer[2]<=s_wdata;
                            end
                            3: begin
                                graph_addr[3]<=lcd_addr_buffer;
                                graph_buffer[3]<=s_wdata;
                            end
                            4: begin
                                graph_addr[4]<=lcd_addr_buffer;
                                graph_buffer[4]<=s_wdata;
                            end
                            5: begin
                                graph_addr[5]<=lcd_addr_buffer;
                                graph_buffer[5]<=s_wdata;
                            end
                            //store graph_size
                            6: begin
                                graph_addr[6]<=lcd_addr_buffer;
                                graph_buffer[6]<=s_wdata;
                            end
                            default: begin
                                graph_addr<=graph_addr;
                                graph_buffer<=graph_buffer;
                            end
                        endcase
                        count<=count+1;
                        if(count==6)  begin
                            buffer_ok<=1;//buffuer is full,AXI can't receive new wdata
                            buffer_state<=DISPATCH_GRAPH;//dispatch inst to lcd_id
                        end
                    end
                end
                //to dispatch inst to lcd_id
                DISPATCH_CHAR: begin
                    refresh<=0;
                    if(write_ok&&dispatch_ok&&inst_num<=4) begin
                        inst_num<=inst_num+1;
                        buffer_addr<=char_addr[inst_num];
                        buffer_data<=char_buffer[inst_num];
                        data_valid<=1;
                        delay_time<=0;
                    end
                    //发射完后必须要延迟两秒等待id工作，不然会捕获到上�?次的write_ok
                    else if(~dispatch_ok&&inst_num<=5) begin
                        delay_time<=delay_time+1;
                        data_valid<=0;
                    end
                    else if(write_ok&&inst_num==5) begin
                        //buffer is empty,receive new data from cpu
                        for(integer i=0;i<7;i++) begin
                            char_buffer[i]<=32'b0;
                            char_addr[i]<=32'b0;
                        end
                        buffer_state<=DISPATCH_CHAR_COLOR;
                        buffer_ok<=1;
                        char_color<=1;
                        char_rs<=0;
                        buffer_data<={{16{1'b0}},16'h2c00};
                        buffer_addr<=0;
                        inst_num<=0;
                        data_valid<=1;
                        delay_time<=0;
                        char_work<=1;
                        cpu_code<=char_buffer[5];
                        char_write_ok<=0;
                    end
                end
                //to dispatch char color data to lcd_id
                DISPATCH_CHAR_COLOR: begin
                    char_work<=0;//char_work只会保持�?个时钟周�?
                    refresh<=0;
                    if(char_color_ok) begin
                        char_write_ok<=0;
                        buffer_data<={{16{1'b0}},char_data_i};
                        buffer_addr<=0;
                        data_valid<=1;
                        delay_time<=0;
                        char_color<=1;
                        char_rs<=1;
                    end
                    else if(~dispatch_ok) begin//delay to wait lcd_id work
                        delay_time<=delay_time+1;
                        data_valid<=0;
                        char_color<=0;
                    end
                    else if(write_str_end) begin
                        buffer_state<=IDLE;
                        buffer_ok<=0;//复位状�?�下不能接受CPU的任何写请求
                        buffer_data<=0;
                        buffer_addr<=0;
                        inst_num<=0;
                        data_valid<=0;
                        delay_time<=2;
                        char_color<=0;
                        char_rs<=0;
                        cpu_code<=0;
                        char_write_ok<=0;
                    end
                    else if(write_ok) begin
                        char_write_ok<=1;
                    end
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
                end
                REFRESH: begin
                    char_color<=0;
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
                            buffer_state<=IDLE;
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
                            cpu_code<=0;
                            char_work<=0;
                            char_write_ok<=0;
                            char_rs<=0;
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
                        char_buffer[i]<=32'b0;
                        char_addr[i]<=32'b0;
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
                    char_color<=0;
                    cpu_code<=0;
                    char_work<=0;
                    char_write_ok<=0;
                    char_rs<=0;
                end
            endcase
        end
    end
    //debug
    assign debug_buffer_state=buffer_state;
    assign debug_inst_num=inst_num;
    assign debug_w_state=w_state;
    assign debug_r_state=r_state;
endmodule
