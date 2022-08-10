//字符绘制模块,用来绘制字符
`define X_START 0
`define X_END   15
`define Y_START 0
`define Y_END   31
`define BACK_COLOR 16'h5555
`define CHAR_COLOR 16'h0000
module char_ctrl (
        input logic pclk,
        input logic rst_n,

        //from lcd_ctrl
        input logic [31:0]cpu_code,
        input logic char_work,
        input logic write_ok,

        //to lcd_ctrl
        output logic [31:0]data_o
        output logic color_ok
    );
    //to char_lib
    logic [7:0]ascii_code;
    logic [7:0]chinese_code;
    logic is_en;
    logic char_req;

    //from char_lib
    logic data_ok;
    logic [15:0]douta;
    logic finish;
    logic col;

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
    always_ff @(posedge pclk)begin
        if(~rst_n)begin
            x<=0;
            y<=0;
            xy_state<=SET_IDLE;
            flag<=0;
            str_end<=0;
        end
        else if(state==WRITE_COLOR)begin
            case(xy_state)
                SET_IDLE:begin
                    x<=0;
                    y<=0;
                    xy_state<=SET_XY;
                    flag<=1;
                    str_end<=0;
                end
                SET_XY:begin
                    if(write_ok) begin
                        if(x<X_END)begin
                            x<=x+1;
                            flag<=1;
                        end 
                        else if(y<Y_END)begin
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
                        xy_state<=SET_OK;
                    end
                    else begin
                        flag<=0;
                    end     
                end
                SET_OK:begin
                    flag<=0;
                    xy_state<=SET_XY;
                end
                default:begin
                    x<=0;
                    y<=0;
                    xy_state<=SET_XY;
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
        end
    end

    logic [15:0]char [31:0];
    logic [31:0]cpu_code_buffer;
    always_ff @(posedge pclk) begin
        if(~rst_n) begin
            state<=IDLE;
            data_o<=0;
            color_ok<=0;
            cpu_code_buffer<=0;
        end
        else begin
            case(state)
                IDLE: begin
                    if(char_work) begin
                        state<=GET_DATA;
                        cpu_code_buffer<=cpu_code;
                    end
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
                        if(char[y][x])
                            pixel_data <= `CHAR_COLOR;    //显示字符
                        else
                            pixel_data <= `BACK_COLOR;    //显示字符区域的背景色
                     end
                     else begin
                        state<=IDLE;
                        data_o<=0;
                        color_ok<=0;
                        cpu_code_buffer<=0;
                     end
                end
                default:
                begin
                    state<=IDLE;
                    data_o<=0;
                    color_ok<=0;
                    cpu_code_buffer<=0;
                end
            endcase
        end
    end

    //store the char data into register
    always_ff @(posedge pclk) begin
        if(~rst_n)  begin
            for(integer i=0;i<=15:i++) begin
                char[i]<=32'b0;
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
            for(integer i=0;i<=15:i++) begin
                char[i]<=32'b0;
            end
        end
        else  if(state==GET_DATA) begin
            ascii_code<=0;
            chinese_code<=0;
            is_en<=0;
            char_req<=0;
            if(data_ok) begin
                char[col]<=douta;
            end
        end
    end


endmodule
