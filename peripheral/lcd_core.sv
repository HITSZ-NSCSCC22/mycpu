// lcd_core to monitor the state of LCD
module lcd_core (
        input logic pclk,
        input logic rst_n,
        //from lcd_init
        input logic init_finish,
        //to lcd_init
        output logic init_main,
        //to lcd_ctrl
        output logic [31:0]touch_reg,
        output logic cpu_work,//cpu can send message to lcd
        //to lcd_mux
        output logic cpu_draw,//cpu can draw the LCD now
        //from lcd_touch_scanner
        input   logic touch_flag,//1表示碰到触碰点
        input   logic release_flag, //it would be set as 1 when the coordinate is ready，1表示手松开
        input   logic [31:0] coordinate,  //{x_low,x_high,y_low,y_high}
        //to lcd_touch_scanner
        output  logic enable//触摸屏开始工作
    );
    //monitor the coordinate
    logic [15:0] cx;
    assign cx= {coordinate[23:16],coordinate[31:24]};
    logic [15:0] cy;
    assign cy= {coordinate[7:0],coordinate[15:8]};

    assign touch_reg={release_flag|touch_flag,{11{1'b0}},cx[9:0],cy[9:0]};//touch_reg，preserve the touch information from LCD

    //消抖模块
    logic touch_valid;
    logic [31:0]count;
    always_ff @(posedge pclk) begin
        if(~rst_n)
            touch_valid<=1;
        else if(release_flag)
            touch_valid<=0;
        else if(count>=32'd1000_0000)
            touch_valid<=1;
        else
            touch_valid<=touch_valid;
    end
    logic flag;
    assign flag=(count>=32'd1000_0000)?1:0;
    always_ff @(posedge pclk) begin
        if(~rst_n)
            count<=0;
        else if(touch_valid||flag)
            count<=0;
        else if(touch_valid==0)
            count<=count+1;
        else
            count<=count;
    end

    enum int{
             IDLE,
             INITIAL,
             MAIN,
             GAME
         } core_state;
    always_ff @(posedge pclk) begin
        if(~rst_n) begin
            enable<=0;
            init_main<=0;
            core_state<=IDLE;
            cpu_draw<=0;
            cpu_work<=0;
        end
        else begin
            case(core_state)
                IDLE: begin
                    core_state<=INITIAL;
                    enable<=0;
                    init_main<=0;
                    cpu_draw<=0;
                    cpu_work<=0;
                end
                INITIAL: begin
                    if(init_finish) begin
                        enable<=1;
                        core_state<=MAIN;
                        cpu_work<=1;
                    end
                    cpu_draw<=0;
                    init_main<=0;
                end
                MAIN: begin
                    //TITLE 1
                    if(touch_valid&&release_flag&&cx>=16'h3C&&cx<=16'hD1&&cy>=16'h46&&cy<=16'h171) begin
                        core_state<=GAME;
                        cpu_draw<=1;
                        init_main<=0;
                    end
                    //TITLE 2
                    else if(touch_valid&&release_flag&&cx>=16'h10E&&cx<=16'h1A3&&cy>=16'h46&&cy<=16'h171) begin
                        core_state<=INITIAL;
                        cpu_draw<=0;
                        init_main<=1;//test yi xia
                    end
                    //TITLE 3
                    else if(touch_valid&&release_flag&&cx>=16'h3C&&cx<=16'hD1&&cy>=16'h1AE&&cy<=16'h2D9) begin
                        core_state<=GAME;
                        cpu_draw<=1;
                        init_main<=0;
                    end
                    //TITLE 4
                    else if(touch_valid&&release_flag&&cx>=16'h10E&&cx<=16'h1A3&&cy>=16'h1AE&&cy<=16'h2D9) begin
                        core_state<=GAME;
                        cpu_draw<=1;
                        init_main<=0;
                    end
                end
                GAME: begin
                    if(touch_valid&&release_flag&&cx>=16'h28&&cx<=16'h1B7&&cy>=16'h28&&cy<=16'h2f7) begin
                        core_state<=INITIAL;
                        init_main<=1;
                        cpu_draw<=0;
                        cpu_work<=0;
                    end
                    else begin
                        core_state<=core_state;
                        init_main<=0;
                    end
                end
                default: begin
                    enable<=0;
                    init_main<=0;
                    core_state<=IDLE;
                    cpu_draw<=0;
                    cpu_work<=0;
                end
            endcase
        end
    end
endmodule
