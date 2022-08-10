module lcd_interface #(
        parameter RD_ID_H = 5,
        parameter RD_ID_L = 3,
        parameter RD_FM_H = 13,
        parameter RD_FM_L = 8
    ) (
        input logic pclk,  //cycle time 20ns,50Mhz
        input logic rst_n, //low is powerful

        //to lcd
        /**屏幕显示信号**/
        output logic lcd_rst,  //lcd 复位键
        output logic lcd_cs,
        output logic lcd_rs,  //0:inst 1:data
        output logic lcd_wr,  //write signal ,low is powerful
        output logic lcd_rd,  //read signal,low is powerful
        input logic [15:0] lcd_data_i,  //from lcd
        output logic [15:0] lcd_data_o,  //to lcd
        output logic lcd_bl_ctr,  //
        //to lcd top
        output logic lcd_write_data_ctrl,  //写控制信号，用于决定顶层的lcd_data_io
        output logic [31:0] data_reg,
        //from lcd_id
        input logic [15:0] data_i,
        input logic we,
        input logic wr,
        input logic lcd_rs_i,  //distinguish inst or data
        input logic id_fm,  //distinguish read id or read fm,0:id,1:fm
        input logic read_color,  //if read color ,reading time is at least 2
        //to lcd_id
        output logic busy,
        output logic write_color_ok,  //write one color
        //to lcd_init
        output logic init_write_ok

    );
    always_ff @(posedge pclk) begin
        if (~rst_n)
            lcd_bl_ctr <= 0;
        else
            lcd_bl_ctr <= 1;
    end


    assign lcd_rst = rst_n;
    //DFA
    enum int {
             IDLE,
             SETUP_READ,
             READING,
             SETUP_WRITE,
             WRITING,
             WRITE_DELAY
         }
         current_state, next_state;

    //write delay to miss the data from lcd,so that we can write the correct data to lcd
    //rather than the input data from lcd_data_io
    // logic write_delay;
    // always_ff @(posedge pclk) begin
    //     if(~rst_n)
    //         write_delay<=0;
    //     else if(next_state==SETUP_WRITE&&current_state==IDLE)
    //         write_delay<=1;
    //     else
    //         write_delay<=0;
    // end

    //read delay
    logic [31:0] time_counter;  //延迟的时钟周期数
    logic [31:0] delay_time;  //需要延迟的时钟周期数
    logic [31:0] read_counter;  //读的次数
    logic [31:0] read_number;  //需要读的次数

    //read delay time
    always_ff @(posedge pclk) begin
        if (~rst_n)
            delay_time <= 0;
        else begin
            case (next_state)
                IDLE, WRITE_DELAY,SETUP_WRITE, WRITING:
                    delay_time <= 0;
                SETUP_READ: begin
                    if (id_fm)
                        delay_time <= RD_FM_L;
                    else
                        delay_time <= RD_ID_L;
                end
                READING: begin
                    if (id_fm)
                        delay_time <= RD_FM_H;
                    else
                        delay_time <= RD_ID_H;
                end
                default:
                    delay_time <= 0;
            endcase
        end
    end

    // time counter
    //the counter should delay one cycle,don't start until delay_time is set
    always_ff @(posedge pclk) begin
        if (~rst_n)
            time_counter <= 0;
        else begin
            case (current_state)
                IDLE, WRITE_DELAY,SETUP_WRITE, WRITING:
                    time_counter <= 0;
                SETUP_READ, READING: begin
                    if (time_counter == delay_time)
                        time_counter <= 0;
                    else
                        time_counter <= time_counter + 1;
                end
                default:
                    time_counter <= 0;
            endcase
        end
    end

    //read time,read_number就是读的次数
    always_ff @(posedge pclk) begin
        if (~rst_n)
            read_number <= 0;
        else begin
            case (next_state)
                IDLE, WRITE_DELAY,SETUP_WRITE, WRITING:
                    read_number <= 0;
                SETUP_READ: begin
                    if (read_color)
                        read_number <= 2;
                    else
                        read_number <= 1;
                end
                READING:
                    read_number <= read_number;

                default:
                    read_number <= 0;
            endcase
        end
    end

    // read counter
    always_ff @(posedge pclk) begin
        if (~rst_n)
            read_counter <= 0;
        else begin
            case (next_state)
                IDLE, WRITE_DELAY,SETUP_WRITE, WRITING:
                    read_counter <= 0;
                SETUP_READ:
                    read_counter <= read_counter;  //不能为0，因为连续读会多次到达SETUP_READ状态
                READING: begin
                    if (read_counter == read_number)
                        read_counter <= 0;
                    else if (current_state == SETUP_READ)
                        read_counter <= read_counter + 1;  //只有从SETUP_READ到READING时才会加1
                    else
                        read_counter <= read_counter;
                end
            endcase
        end
    end

    //DFA
    always_ff @(posedge pclk) begin
        if (~rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        //state transition
        case (current_state)
            IDLE: begin
                if (we) begin
                    // next_state = SETUP_WRITE;
                    next_state=WRITE_DELAY;
                end
                else begin
                    next_state = IDLE;
                end
            end
            WRITE_DELAY: begin
                next_state=SETUP_WRITE;
            end
            SETUP_WRITE: begin
                // if(~write_delay) begin
                next_state = WRITING;
                // end
                // else
                //     next_state=SETUP_WRITE;
            end
            WRITING: begin
                if (wr) begin
                    next_state = IDLE;
                end
                else begin
                    next_state = SETUP_READ;
                end
            end
            SETUP_READ: begin
                if (time_counter == delay_time)
                    next_state = READING;
                else
                    next_state = SETUP_READ;
            end
            READING: begin
                if (time_counter == delay_time) begin
                    if (read_counter == read_number) begin
                        next_state = IDLE;
                    end
                    else begin
                        next_state = SETUP_READ;
                    end
                end
                else begin
                    next_state = READING;
                end
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge pclk) begin
        if (~rst_n) begin
            lcd_cs <= 1;
            lcd_rs <= 0;
            lcd_wr <= 1;
            lcd_rd <= 1;
            lcd_data_o <= 16'bz;
            lcd_write_data_ctrl <= 0;
            data_reg <= 32'b0;
            busy <= 0;
            write_color_ok <= 0;
            init_write_ok <= 0;
        end
        else begin
            case (next_state)
                //Waiting
                IDLE: begin
                    lcd_cs <= 1;
                    lcd_rs <= 0;
                    lcd_wr <= 1;
                    lcd_rd <= 1;
                    lcd_data_o <= 16'bz;
                    lcd_write_data_ctrl <= 0;
                    data_reg <= 0;
                    busy <= 0;
                    write_color_ok <= 0;
                    init_write_ok <= 0;
                end
                //WRITE DELAY to miss wrong data
                WRITE_DELAY: begin
                    lcd_cs <= 0;
                    lcd_rs <= lcd_rs_i;
                    lcd_wr <= 1;
                    lcd_rd <= 1;
                    lcd_data_o <= data_i;
                    lcd_write_data_ctrl <= 1;
                    busy <= 1;
                    write_color_ok <= 0;
                    init_write_ok <= 0;
                end
                //Write Preparation
                SETUP_WRITE: begin
                    lcd_cs <= 0;
                    // lcd_rs <= lcd_rs_i;
                    lcd_rs<=lcd_rs;
                    lcd_wr <= 0;
                    lcd_rd <= 1;
                    // lcd_data_o <= data_i;
                    lcd_data_o<=lcd_data_o;
                    lcd_write_data_ctrl <= 1;
                    busy <= 1;
                    write_color_ok <= 1;
                    init_write_ok <= 0;
                end
                //Write lcd
                WRITING: begin
                    lcd_cs <= 0;
                    lcd_rs <= lcd_rs;
                    lcd_wr <= 1;
                    lcd_rd <= 1;
                    lcd_data_o <= lcd_data_o;
                    lcd_write_data_ctrl <= 1;
                    init_write_ok <= 1;
                    if (wr) begin
                        busy <= 0;
                    end
                    else begin
                        busy <= 1;
                    end

                    write_color_ok <= 0;

                end
                //Read Preparation
                SETUP_READ: begin
                    lcd_cs <= 0;
                    lcd_rs <= 1;
                    lcd_wr <= 1;
                    lcd_rd <= 0;
                    lcd_data_o <= 16'bz;
                    lcd_write_data_ctrl <= 0;
                    //data_reg <= {data_reg[31:16], lcd_data_i};
                    busy <= 1;
                    write_color_ok <= 0;
                    init_write_ok <= 0;
                end
                //Read lcd
                READING: begin
                    lcd_cs <= 0;
                    lcd_rs <= 1;
                    lcd_wr <= 1;
                    lcd_rd <= 1;
                    lcd_data_o <= 16'bz;
                    lcd_write_data_ctrl <= 0;
                    //data_reg <= data_reg;
                    data_reg <= {data_reg[15:0], lcd_data_i};
                    busy <= 1;
                    write_color_ok <= 0;
                    init_write_ok <= 0;
                end
                default: begin
                    lcd_cs <= 1;
                    lcd_rs <= 0;
                    lcd_wr <= 1;
                    lcd_rd <= 1;
                    lcd_data_o <= 16'bz;
                    lcd_write_data_ctrl <= 0;
                    data_reg <= 32'b0;
                    busy <= 0;
                    write_color_ok <= 0;
                    init_write_ok <= 0;
                end
            endcase
        end

    end

    ila_1 lcd_interface_debug (
              .clk(pclk), // input wire clk
              .probe0(lcd_data_i), // input wire [14:0]  probe0
              .probe1(lcd_data_o), // input wire [14:0]  probe1
              .probe2(0), // input wire [14:0]  probe2
              .probe3(current_state), // input wire [31:0]  probe3
              .probe4(next_state), // input wire [31:0]  probe4
              .probe5(write_color_ok), // input wire [0:0]  probe5
              .probe6(init_write_ok), // input wire [0:0]  probe6
              .probe7(we), // input wire [0:0]  probe7
              .probe8(lcd_rs_i), // input wire [0:0]  probe8
              .probe9(0), // input wire [0:0]  probe9
              .probe10(0), // input wire [0:0]  probe10
              .probe11(0) // input wire [0:0]  probe11
          );

endmodule
