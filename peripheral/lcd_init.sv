`define COLOR_ADDR 17'd803
`define INIT_END   17'd117232
module lcd_init (
        input  logic        pclk,
        input  logic        rst_n,
        input  logic        init_write_ok,
        output logic [15:0] init_data,
        output logic [16:0] init_addra,
        output logic        we,
        output logic        wr,
        output logic        rs,
        output logic        init_work,
        output logic        init_finish
    );

    enum int {
             IDLE,
             INIT,
             CLEAR,//to refresh the lcd
             DRAW_LOGO,
             INIT_FINISH
         } init_state;
    enum int {
             WAIT_INIT,
             DELAY
         } delay_state;
    logic [16:0] addra;
    logic [31:0] delay_counter;

    always_ff @(posedge pclk) begin
        if (~rst_n) begin
            delay_state   <= WAIT_INIT;
            delay_counter <= 0;
        end
        else begin
            case (delay_state)
                WAIT_INIT: begin
                    if (init_write_ok && addra == 17'd762 && delay_counter <= 40000)
                        delay_state <= DELAY;
                end
                DELAY: begin
                    if (delay_counter <= 40000)
                        delay_counter <= delay_counter + 1;
                    else
                        delay_state <= WAIT_INIT;
                end
                default: begin
                    delay_state   <= WAIT_INIT;
                    delay_counter <= 0;
                end
            endcase
        end
    end

    always_ff @(posedge pclk) begin
        if (~rst_n) begin
            init_state <= IDLE;
            addra <= 0;
            we <= 0;
            wr <= 1;
            rs <= 0;
            init_work <= 1;
            init_finish <= 0;
        end
        else begin
            case (init_state)
                IDLE: begin
                    init_state <= INIT;
                    addra <= 0;
                    we <= 1;
                    wr <= 1;
                    rs <= 0;
                    init_work <= 1;
                    init_finish <= 0;
                end
                INIT: begin
                    if (init_write_ok) begin
                        //init finish
                        if (addra == 17'd783) begin
                            init_state <= DRAW_LOGO;
                            addra <= addra+1;
                            we <= 0;
                            wr <= 1;
                            rs <= 0;
                            init_work <= 1;
                            init_finish <= 0;
                        end
                        else begin
                            addra <= addra + 1;
                            we <= 0;
                        end
                    end
                    else if (delay_state == DELAY) begin
                        we <= 0;
                    end
                    else begin
                        init_state <= INIT;
                        addra <= addra;
                        we <= 1;
                        wr <= 1;
                        if (addra == 17'd763)
                            rs <= 0;
                        else if (addra[0] == 1)
                            rs <= 1;
                        else
                            rs <= 0;
                        init_work   <= 1;
                        init_finish <= 0;
                    end
                end
                DRAW_LOGO: begin
                    if (init_write_ok) begin
                        //init finish
                        if (addra == `INIT_END) begin
                            init_state <= INIT_FINISH;
                            addra <= 0;
                            we <= 0;
                            wr <= 1;
                            rs <= 0;
                            init_work <= 1;
                            init_finish <= 0;
                        end
                        else begin
                            addra <= addra + 1;
                            we <= 0;
                        end
                    end
                    else begin
                        init_state <= DRAW_LOGO;
                        addra <= addra;
                        we <= 1;
                        wr <= 1;
                        if (addra >=`COLOR_ADDR)
                            rs <= 1;
                        else if (addra[0] == 1)
                            rs <= 1;
                        else
                            rs <= 0;
                        init_work   <= 1;
                        init_finish <= 0;
                    end
                end
                INIT_FINISH: begin
                    init_state <= INIT_FINISH;
                    addra <= 0;
                    we <= 0;
                    wr <= 1;
                    rs <= 0;
                    init_work <= 0;
                    init_finish <= 1;
                end
                default: begin
                    init_state <= IDLE;
                    addra <= 0;
                    we <= 0;
                    wr <= 1;
                    rs <= 0;
                    init_work <= 1;
                    init_finish <= 0;
                end
            endcase
        end
    end
    assign init_addra=addra;
    //initial code
    lcd_init_bram u_lcd_init_bram (
                      .clka (pclk),      // input wire clka
                      .ena  (1),         // input wire ena
                      .wea  (0),         // input wire [0 : 0] wea
                      .addra(addra),     // input wire [16 : 0] addra
                      .dina (0),         // input wire [15 : 0] dina
                      .douta(init_data)  // output wire [15 : 0] douta
                  );

    ila_2 lcd_init_debug (
              .clk(pclk), // input wire clk


              .probe0(init_data), // input wire [15:0]  probe0
              .probe1(addra) // input wire [16:0]  probe1
          );

endmodule
