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

        //to lcd_mux
        output logic cpu_draw,

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
        end
        else begin
            case(core_state)
                IDLE:
                    core_state<=INITIAL;
                INITIAL: begin
                    if(init_finish) begin
                        enable<=1;
                        core_state<=MAIN;
                    end
                end
                MAIN: begin
                    if(release_flag&&cx>=16'h28&&cx<=16'h1B7&&cy>=16'h28&&cy<=16'h2f7) begin
                        core_state<=GAME;
                        cpu_draw<=1;
                        init_main<=1;
                    end
                end
                GAME: begin
                    core_state<=core_state;
                    init_main<=0;
                end
                default: begin
                    enable<=0;
                    init_main<=0;
                    core_state<=IDLE;
                    cpu_draw<=0;
                end
            endcase
        end
    end

endmodule
