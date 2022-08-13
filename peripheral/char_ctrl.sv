//字符绘制模块,用来绘制字符
`define X_START 0
`define X_END   23
`define Y_START 0
`define Y_END   39
`define BACK_COLOR 16'hffff
`define CHAR_COLOR 16'h0000
module char_ctrl (
        input logic pclk,
        input logic rst_n,

        //from lcd_ctrl
        input logic [31:0]cpu_code,
        input logic char_work,
        input logic write_ok,

        //to lcd_ctrl
        output logic [15:0]data_o,
        output logic color_ok,
        output logic write_str_end,

        //debug
        output logic [31:0]debug_col,
        output logic debug_char_req,
        output logic [`X_END:0]debug_char_douta,
        output logic debug_char_data_ok,
        output logic debug_char_finish,
        output logic [5:0]debug_x,
        output logic [5:0]debug_y,
        output logic [31:0]debug_char_ctrl_state

    );
    //to char_lib

    logic [7:0]ascii_code;
    logic [7:0]chinese_code;
    logic is_en;
    logic char_req;

    //from char_lib
    logic data_ok;
    logic [`X_END:0]douta;
    logic finish;
    logic [31:0]col;

    //get data from library
    char_lib  u_char_lib(
                  .pclk(pclk),
                  .rst_n(rst_n),

                  //from char_ctrl
                  .ascii_code(ascii_code),
                  .chinese_code(chinese_code),
                  .is_en(is_en),
                  .char_req(char_req),

                  //to char_ctrl
                  .data_ok(data_ok),
                  .douta(douta),
                  .finish(finish),
                  .col(col)
              );
    //计算点阵的坐标
    logic [5:0]x;
    logic [5:0]y;
    enum int{
             SET_IDLE,
             SET_XY,
             SET_OK
         } xy_state;

    enum int{
             IDLE,
             GET_DATA,
             WRITE_COLOR
         } state;
    logic flag;
    logic str_end;
    logic start;
    //监视像素点绘制的坐标,从而判断字符串的绘制情况
    always_ff @(posedge pclk) begin
        if(~rst_n) begin
            x<=0;
            y<=0;
            xy_state<=SET_IDLE;
            flag<=0;
            str_end<=0;
            start<=0;
        end
        else if(state==WRITE_COLOR) begin
            case(xy_state)
                SET_IDLE: begin
                    if(write_ok&&~start) begin
                        x<=0;
                        y<=0;
                        str_end<=0;
                        xy_state<=SET_XY;
                        flag<=1;
                        start<=1;
                    end
                    else if(write_ok&&start) begin
                        if(x<`X_END) begin
                            x<=x+1;
                            flag<=1;
                        end
                        else if(y<`Y_END) begin
                            x<=0;
                            y<=y+1;
                            flag<=1;
                        end
                        else begin
                            x<=0;
                            y<=0;
                            str_end<=1;
                            flag<=0;
                        end
                        xy_state<=SET_XY;
                    end
                end
                //update x and y
                SET_XY: begin
                    flag<=0;
                    xy_state<=SET_OK;
                end
                SET_OK: begin
                    flag<=0;
                    xy_state<=SET_IDLE;
                end
                default: begin
                    start<=0;
                    x<=0;
                    y<=0;
                    xy_state<=SET_IDLE;
                    flag<=0;
                    str_end<=0;
                end
            endcase
        end
        else begin
            x<=0;
            y<=0;
            xy_state<=SET_IDLE;
            flag<=0;
            str_end<=0;
            start<=0;
        end
    end

    logic [`X_END:0]char_buffer[0:`Y_END];
    logic [31:0]cpu_code_buffer;
    always_ff @(posedge pclk) begin
        if(~rst_n) begin
            state<=IDLE;
            data_o<=0;
            color_ok<=0;
            cpu_code_buffer<=0;
            write_str_end<=0;
        end
        else begin
            case(state)
                IDLE: begin
                    //char_work只会拉高一个周期
                    if(char_work) begin
                        state<=GET_DATA;
                        cpu_code_buffer<=cpu_code;
                    end
                    write_str_end<=0;
                    data_o<=0;
                    color_ok<=0;
                end
                //get data from library
                GET_DATA: begin
                    if(finish)
                        state<=WRITE_COLOR;
                end
                //send color data to lcd
                WRITE_COLOR: begin
                    if(~str_end) begin
                        if(flag) begin
                            color_ok<=1;
                            if(char_buffer[y][`X_END-x])
                                data_o <= `CHAR_COLOR;    //显示字符
                            else
                                data_o <= `BACK_COLOR;    //显示字符区域的背景色
                        end
                        else begin
                            color_ok<=0;
                        end
                    end
                    else begin
                        write_str_end<=1;
                        state<=IDLE;
                        data_o<=0;
                        color_ok<=0;
                        cpu_code_buffer<=0;
                    end
                end
                default: begin
                    write_str_end<=0;
                    state<=IDLE;
                    data_o<=0;
                    color_ok<=0;
                    cpu_code_buffer<=0;
                end
            endcase
        end
    end

    //store the char data into register
    //对lcd_ctrl的指令译码
    always_ff @(posedge pclk) begin
        if(~rst_n)  begin
            for(integer i=0;i<=`Y_END;i++) begin
                char_buffer[i]<=0;
            end
            ascii_code<=0;
            chinese_code<=0;
            is_en<=0;
            char_req<=0;
        end
        else if(char_work&&state==IDLE) begin
            ascii_code<=0;
            chinese_code<=0;
            is_en<=0;
            char_req<=1;
            for(integer i=0;i<=`Y_END;i++) begin
                char_buffer[i]<=0;
            end
        end
        else  if(state==GET_DATA) begin
            ascii_code<=0;
            chinese_code<=0;
            is_en<=0;
            char_req<=0;
            if(data_ok) begin
                char_buffer[col]<=douta;
            end
        end
    end

    //debug
    assign debug_col=col;
    assign debug_char_req=char_req;
    assign debug_char_douta=douta;
    assign debug_char_data_ok=data_ok;
    assign debug_char_finish=finish;
    assign debug_x=x;
    assign debug_y=y;
    assign debug_char_ctrl_state=state;
endmodule
