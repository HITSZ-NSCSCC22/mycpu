module lcd_init (
    input  logic        pclk,
    input  logic        rst_n,
    input  logic        init_write_ok,
    output logic [15:0] init_data,
    output logic        we,
    output logic        wr,
    output logic        rs,
    output logic        init_work,
    output logic        init_finish
);
    enum int {
        IDLE,
        INIT,
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
        end else begin
            case (delay_state)
                WAIT_INIT: begin
                    if (init_write_ok && addra == 17'd762 && delay_counter <= 40000)
                        delay_state <= DELAY;
                end
                DELAY: begin
                    if (delay_counter <= 40000) delay_counter <= delay_counter + 1;
                    else delay_state <= WAIT_INIT;
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
        end else begin
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
                            init_state <= INIT_FINISH;
                            addra <= 0;
                            we <= 0;
                            wr <= 1;
                            rs <= 0;
                            init_work <= 1;
                            init_finish <= 0;
                        end else begin
                            addra <= addra + 1;
                            we <= 0;
                        end
                    end else if (delay_state == DELAY) begin
                        we <= 0;
                    end else begin
                        init_state <= INIT;
                        addra <= addra;
                        we <= 1;
                        wr <= 1;
                        if (addra == 17'd763) rs <= 0;
                        else if (addra[0] == 1) rs <= 1;
                        else rs <= 0;
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

    //initial code
    lcd_init_bram u_lcd_init_bram (
        .clka (pclk),      // input wire clka
        .ena  (1),         // input wire ena
        .wea  (0),         // input wire [0 : 0] wea
        .addra(addra),     // input wire [16 : 0] addra
        .dina (0),         // input wire [15 : 0] dina
        .douta(init_data)  // output wire [15 : 0] douta
    );

endmodule
