//lcd instruction decoder,to decode wdata to lcd inst and data
/**opcode**/
`define ID1 8'hDA
`define ID2 8'hDB
`define ID3 8'hDC
`define SCAN 8'h36
`define SC_EC 8'h2A
`define SP_EP 8'h2B
`define W_COLOR 8'h2C
`define R_COLOR 8'h2E
module lcd_id (
        input logic pclk,
        input logic rst_n,
        //from lcd ctrl
        input logic write_lcd_i,
        input logic [31:0] lcd_addr_i,
        input logic [31:0] lcd_data_i,
        input logic refresh_i,
        input logic refresh_rs_i,

        //speeder
        input logic [31:0] buffer_data_i,
        input logic [31:0] buffer_addr_i,
        input logic data_valid,
        input logic [31:0] graph_size_i,
        input logic char_color_i,
        input logic char_rs_i,
        //to lcd ctrl
        output logic write_ok,

        //to lcd interface
        output logic we,  //write enable
        output logic wr,  //0:read lcd 1:write lcd,distinguish inst kind
        output logic lcd_rs,
        output logic [15:0] data_o,
        output logic id_fm,
        output logic read_color_o,

        //from lcd inteface
        input logic busy,
        input logic write_color_ok,

        //from lcd_core
        input logic cpu_work,
        //debug
        output [31:0]debug_current_state,
        output [31:0]debug_next_state
    );
    enum int {
             IDLE,
             READ_ID,
             SCAN_INST,
             SCAN_DATA,
             SC_INST1,    //写sc高16bit
             SC_DATA1,
             SC_INST2,    //写sc低16bit
             SC_DATA2,
             EC_INST1,
             EC_DATA1,
             EC_INST2,
             EC_DATA2,
             SP_INST1,
             SP_DATA1,
             SP_INST2,
             SP_DATA2,
             EP_INST1,
             EP_DATA1,
             EP_INST2,
             EP_DATA2,
             COLOR_INST,
             COLOR_DATA,
             READ_COLOR,
             REFRESH,
             CHAR
         }
         current_state, next_state;

    logic [31:0] graph_size;
    logic [31:0] lcd_data;
    logic [31:0] lcd_addr;
    logic write_lcd;
    logic delay;  //delay one cycle when come to a new state
    logic refresh;
    logic refresh_rs;
    logic char_rs;
    logic char_color;
    always_ff @(posedge pclk) begin//进入新状态后必须要暂停一拍
        if (~rst_n||~cpu_work)
            delay <= 0;
        else if (current_state != next_state)
            delay <= 1;
        else
            delay <= 0;
    end
    //buffer
    always_ff @(posedge pclk) begin
        if (~rst_n||~cpu_work) begin
            lcd_data   <= 0;
            lcd_addr   <= 0;
            graph_size <= 0;
            refresh_rs<=0;
            char_rs<=0;
        end
        else if (write_lcd_i) begin
            lcd_data   <= lcd_data_i;
            lcd_addr   <= lcd_addr_i;
            graph_size <= graph_size_i;
            refresh_rs<=refresh_rs_i;
            char_rs<=char_rs_i;
        end
        else begin
            lcd_data   <= lcd_data;
            lcd_addr   <= lcd_addr;
            graph_size <= graph_size;
            refresh_rs<=refresh_rs;
            char_rs<=char_rs;
        end
    end

    //delay one cycle for write_lcd_i
    always_ff @(posedge pclk) begin
        if (~rst_n||~cpu_work) begin
            write_lcd <= 0;
            refresh<=0;
            char_color<=0;
        end
        else begin
            write_lcd <= write_lcd_i;
            refresh<=refresh_i;
            char_color<=char_color_i;
        end
    end

    /*****
    般的指令格式:wdata=8bit opcode+ 8bit func + 16bit 参数

    入颜色的指令:wdata=8bit opcode+ 8bit func + 5 bit red + 6bit green +5 bit blue
    *****/
    logic [7:0] opcode;
    assign opcode = lcd_data[31:24];
    logic [7:0] op1;
    assign op1 = lcd_data[23:16];
    logic [15:0] data;
    assign data = lcd_data[15:0];
    logic [7:0] coordinate_h;
    assign coordinate_h = lcd_data[15:8];  //sc,ec,sp,ep的高8bit
    logic [7:0] coordinate_l;
    assign coordinate_l = lcd_data[7:0];  //sc,ec,sp,ep的低8bit

    logic [31:0] draw_counter;
    //draw counter
    always_ff @(posedge pclk) begin
        if (~rst_n||~cpu_work)
            draw_counter <= 0;
        else if (next_state == IDLE)
            draw_counter <= 0;
        else if (next_state == COLOR_DATA && write_color_ok)
            draw_counter <= draw_counter + 1;
        else
            draw_counter <= draw_counter;
    end

    /*****DFA*****/
    always_ff @(posedge pclk) begin
        if (~rst_n||~cpu_work)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        //state transition
        case (current_state)

            IDLE: begin
                if (write_lcd&&(~refresh)&&(~char_color)) begin
                    case (opcode)
                        `ID1, `ID2, `ID3:
                            next_state = READ_ID;
                        `SCAN:
                            next_state = SCAN_INST;
                        `SC_EC: begin
                            if (op1 == 8'h00)
                                next_state = SC_INST1;
                            else if (op1 == 8'h02)
                                next_state = EC_INST1;
                            else
                                next_state = IDLE;
                        end
                        `SP_EP: begin
                            if (op1 == 8'h00)
                                next_state = SP_INST1;
                            else if (op1 == 8'h02)
                                next_state = EP_INST1;
                            else
                                next_state = IDLE;
                        end
                        `W_COLOR:
                            next_state = COLOR_INST;
                        `R_COLOR:
                            next_state = READ_COLOR;
                        default:
                            next_state = IDLE;
                    endcase
                end
                else if(write_lcd&&refresh) begin
                    next_state=REFRESH;
                end
                else if(write_lcd&&char_color)
                    next_state=CHAR;
                else
                    next_state = IDLE;
            end

            //read ID
            READ_ID: begin
                if (busy || delay)
                    next_state = READ_ID;
                else
                    next_state = IDLE;
            end

            //set scan direction
            SCAN_INST: begin
                if (busy || delay)
                    next_state = SCAN_INST;
                else
                    next_state = SCAN_DATA;
            end

            SCAN_DATA: begin
                if (busy || delay)
                    next_state = SCAN_DATA;
                else
                    next_state = IDLE;
            end

            //set SC
            SC_INST1: begin
                if (busy || delay)
                    next_state = SC_INST1;
                else
                    next_state = SC_DATA1;
            end

            SC_DATA1: begin
                if (busy || delay)
                    next_state = SC_DATA1;
                else
                    next_state = SC_INST2;
            end

            SC_INST2: begin
                if (busy || delay)
                    next_state = SC_INST2;
                else
                    next_state = SC_DATA2;
            end

            SC_DATA2: begin
                if (busy || delay)
                    next_state = SC_DATA2;
                else
                    next_state = IDLE;
            end

            //set EC
            EC_INST1: begin
                if (busy || delay)
                    next_state = EC_INST1;
                else
                    next_state = EC_DATA1;
            end

            EC_DATA1: begin
                if (busy || delay)
                    next_state = EC_DATA1;
                else
                    next_state = EC_INST2;
            end

            EC_INST2: begin
                if (busy || delay)
                    next_state = EC_INST2;
                else
                    next_state = EC_DATA2;
            end

            EC_DATA2: begin
                if (busy || delay)
                    next_state = EC_DATA2;
                else
                    next_state = IDLE;
            end

            //set SP
            SP_INST1: begin
                if (busy || delay)
                    next_state = SP_INST1;
                else
                    next_state = SP_DATA1;
            end

            SP_DATA1: begin
                if (busy || delay)
                    next_state = SP_DATA1;
                else
                    next_state = SP_INST2;
            end

            SP_INST2: begin
                if (busy || delay)
                    next_state = SP_INST2;
                else
                    next_state = SP_DATA2;
            end

            SP_DATA2: begin
                if (busy || delay)
                    next_state = SP_DATA2;
                else
                    next_state = IDLE;
            end

            //set EP
            EP_INST1: begin
                if (busy || delay)
                    next_state = EP_INST1;
                else
                    next_state = EP_DATA1;
            end

            EP_DATA1: begin
                if (busy || delay)
                    next_state = EP_DATA1;
                else
                    next_state = EP_INST2;
            end

            EP_INST2: begin
                if (busy || delay)
                    next_state = EP_INST2;
                else
                    next_state = EP_DATA2;
            end

            EP_DATA2: begin
                if (busy || delay)
                    next_state = EP_DATA2;
                else
                    next_state = IDLE;
            end

            //set color
            COLOR_INST: begin
                if (busy || delay)
                    next_state = COLOR_INST;
                else
                    next_state = COLOR_DATA;
            end

            COLOR_DATA: begin
                if (busy || delay)
                    next_state = COLOR_DATA;
                else if (draw_counter < graph_size)
                    next_state = COLOR_DATA;
                else
                    next_state = IDLE;
            end

            //read color
            READ_COLOR: begin
                if (busy || delay)
                    next_state = READ_COLOR;
                else
                    next_state = IDLE;
            end

            //refresh
            REFRESH: begin
                if (busy || delay)
                    next_state = REFRESH;
                else
                    next_state = IDLE;
            end
            CHAR: begin
                if (busy || delay)
                    next_state = CHAR;
                else
                    next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge pclk) begin
        if (~rst_n||~cpu_work) begin
            write_ok <= 1;
            we <= 0;
            wr <= 0;
            lcd_rs <= 0;
            data_o <= 0;
            id_fm <= 0;
            read_color_o <= 0;
        end
        else begin
            case (next_state)
                IDLE: begin
                    write_ok <= 1;
                    we <= 0;
                    wr <= 0;
                    lcd_rs <= 0;
                    data_o <= 0;
                    id_fm <= 0;
                    read_color_o <= 0;
                end

                READ_ID: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 0;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8{1'b0}}};
                    id_fm <= 0;
                    read_color_o <= 0;
                end

                //set scan direction
                SCAN_INST: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8{1'b0}}};
                end

                SCAN_DATA: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 1;
                    data_o <= data;
                end
                //set SC
                SC_INST1: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8{1'b0}}};
                end

                SC_DATA1: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 1;
                    data_o <= {{8{1'b0}}, coordinate_h};
                end

                SC_INST2: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8'h01}};
                end

                SC_DATA2: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 1;
                    data_o <= {{8'h00}, coordinate_l};
                end

                //set EC
                EC_INST1: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8'h02}};
                end

                EC_DATA1: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 1;
                    data_o <= {{8{1'b0}}, coordinate_h};
                end

                EC_INST2: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8'h03}};
                end

                EC_DATA2: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 1;
                    data_o <= {{8'h00}, coordinate_l};
                end

                //set SP
                SP_INST1: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8{1'b0}}};
                end

                SP_DATA1: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 1;
                    data_o <= {{8{1'b0}}, coordinate_h};
                end

                SP_INST2: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8'h01}};
                end

                SP_DATA2: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 1;
                    data_o <= {{8'h00}, coordinate_l};
                end

                //set EP
                EP_INST1: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8'h02}};
                end

                EP_DATA1: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 1;
                    data_o <= {{8{1'b0}}, coordinate_h};
                end

                EP_INST2: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8'h03}};
                end

                EP_DATA2: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 1;
                    data_o <= {{8'h00}, coordinate_l};
                end

                //set color
                COLOR_INST: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8'h00}};
                end

                COLOR_DATA: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= 1;
                    data_o <= data;
                end

                //read color
                READ_COLOR: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 0;
                    lcd_rs <= 0;
                    data_o <= {opcode, {8'h00}};
                    id_fm <= 1;
                    read_color_o <= 1;
                end
                //refresh lcd
                REFRESH: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= refresh_rs;
                    data_o <= lcd_data[15:0];
                end
                //write string color
                CHAR: begin
                    write_ok <= 0;
                    we <= 1;
                    wr <= 1;
                    lcd_rs <= char_rs;
                    data_o <= lcd_data[15:0];
                end
                default: begin
                    write_ok <= 1;
                    we <= 0;
                    wr <= 0;
                    lcd_rs <= 0;
                    data_o <= 0;
                    id_fm <= 0;
                    read_color_o <= 0;
                end
            endcase
        end
    end

    //debug
    assign debug_current_state=current_state;
    assign debug_next_state=next_state;
endmodule
