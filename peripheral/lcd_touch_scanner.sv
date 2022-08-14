//芯片的型号GT9147
`define INT_ENABLE  1'b0
`define INT_DISABLE 1'b1
`define INST_WR     8'h28//写命令
`define INST_RD     8'h29//读命令
//register addr
`define PID_REG_H   8'h81//读取芯片的ID
`define PID_REG_L   9'h40
`define CTRL_REG_H  8'h80//控制寄存器
`define CTRL_REG_L  8'h40
`define SOFT_RST_EN 8'h02
`define SOFT_RST_DS 8'h00
`define GSTID_REG_H 8'h81//状态寄存器
`define GSTID_REG_L 8'h4e
`define TP1_REG_H   8'h81 //触点坐标寄存器
`define TP1_REG_L   8'h50
`define CFGS_REG_H  8'h80//配置寄存器
`define CFGS_REG_L  8'h47
`define CHECK_REG_H 8'h80//配置信息的校验码，0X8047~0x80FE之间字节的补码
`define CHECK_REG_L 8'hff

`define STATE_IDLE        10'd1
`define STATE_START       10'd2
`define STATE_STOP        10'd4
`define STATE_DELAY       10'd8
`define STATE_SEND_BYTE   10'd16
`define STATE_WAIT_ACK    10'd32
`define STATE_SEND_ACK    10'd64
`define STATE_SEND_NACK   10'd128
`define STATE_READ_BYTE   10'd256

`define STATEU_IDLE       3'b000
`define STATEU_DELAYMS    3'b001
`define STATEU_READ_REG   3'b010//读坐标寄存器0x8150~0x8153和状态寄存器0x814E
`define STATEU_WRITE_REG  3'b100//写状态寄存器0x814E

`define FUNC_IDLE         3'b001
`define FUNC_INIT         3'b010
`define FUNC_SCAN         3'b100

module lcd_touch_scanner(
        input wire ts_clk,
        input wire resetn,

        output   reg touch_flag,//1表示触碰点有效
        output   reg release_flag, //it would be set as 1 when the coordinate is ready
        output   wire [31:0] coordinate,  //{x_low,x_high,y_low,y_high}
        input  wire enable,//触摸屏开始工作
        inout  lcd_int,
        inout  lcd_sda,
        output reg lcd_ct_scl,
        output wire lcd_ct_rstn

    );

    reg data_o;
    reg int_o;

    reg [7:0]  wdata_buffer;
    reg [7:0]  rdata_buffer;
    reg [31:0] rword_buffer;

    reg [9:0] state;
    reg [2:0] state_u;

    //ctrl
    (* mark_debug = "true" *)reg state_finish;
    reg wr;        //1:write  0:read
    reg byte_word; //1:byte 0:word. used when read/write reg
    reg delay_sel; //1:100ms 0:10ms
    (* mark_debug = "true" *)reg [7:0] cfgs;
    reg [8:0] write_count;

    assign coordinate = rword_buffer;
    assign lcd_int = 1'bz;   //int_o;
    assign lcd_ct_rstn = resetn;
    assign lcd_sda = wr ? data_o : 1'bz ;

    ////////// init data /////////////
    wire [7:0] addra;
    wire [7:0] douta;
    wire [8:0]write_count_d6 = write_count - 6;
    assign addra = write_count_d6[8:1];

    gt9147_init init0(
                    .clka     (ts_clk),
                    .ena      (1'b1),
                    .wea      (1'h0),
                    .addra    (addra),
                    .dina     (8'd0),
                    .douta    (douta)
                );
    ///////////////////////////////////////////////
    ////////////////// TOP CTRL ///////////////////
    ///////////////////////////////////////////////
    reg[2:0] state_top;
    reg      init_finish;
    reg[4:0] top_count;
    reg      stateu_finish;
    reg[3:0] touch_count;
    reg touch;
    reg [8:0] write_time; //7-for byte   13-for word   391-for init data

    always @(posedge ts_clk) begin
        if(!enable) begin
            byte_word <= 1'b1; //1:byte 0:word. used when read/write reg
            delay_sel <= 1'b1; //1:100ms 0:10ms，need to delay twice to initial hardware before start touching
            init_finish <= 1'b0;
            top_count <= 0;
            state_u <= `STATEU_IDLE;
            state_top <= `FUNC_IDLE;
            touch_flag <= 1'b0;
            touch <= 1'b0;
            release_flag <= 1'b0;
            touch_count <= 0;
        end
        else begin
            case(state_top)
                `FUNC_IDLE: begin
                    state_u <= `STATEU_IDLE;
                    state_top <= `FUNC_INIT;
                end
                `FUNC_INIT: begin
                    case(top_count)
                        5'd0,5'd2,5'd6: begin  //delay 100ms
                            delay_sel <= 1;
                            state_u <= `STATEU_DELAYMS;
                            if(stateu_finish) begin
                                top_count <= top_count + 1;
                            end
                        end
                        5'd1: begin  //soft reset
                            byte_word <= 1'b1;
                            write_time <= 9'd7;
                            state_u <= `STATEU_WRITE_REG;
                            if(stateu_finish) begin
                                top_count <= top_count + 1;
                            end
                        end
                        5'd3: begin   //get GT_CFGS
                            byte_word <= 1'b1;
                            state_u <= `STATEU_READ_REG;
                            if(stateu_finish) begin
                                top_count <= top_count + 1;
                            end
                        end
                        5'd4: begin   //set flash
                            write_time <= 9'd373;  //184 byte
                            state_u <= `STATEU_WRITE_REG;
                            if(stateu_finish) begin
                                top_count <= top_count + 1;
                            end
                        end
                        5'd5: begin   //set conf
                            write_time <= 9'd9;   //2 byte
                            state_u <= `STATEU_WRITE_REG;
                            if(stateu_finish) begin
                                top_count <= top_count + 1;
                            end
                        end
                        5'd7: begin  //soft reset finish
                            byte_word <= 1'b1;
                            write_time <= 9'd7;
                            state_u <= `STATEU_WRITE_REG;
                            if(stateu_finish) begin
                                top_count <= top_count + 1;
                            end
                        end
                        5'd8: begin    //init finish
                            state_top <= `FUNC_SCAN;
                            init_finish <= 1'b1;
                            state_u <= `STATEU_IDLE;
                            top_count <= 0;
                        end
                        default:
                            ;
                    endcase
                end
                `FUNC_SCAN: begin
                    case(top_count)
                        5'd0: begin                //read the status reg
                            byte_word <= 1'b1;
                            state_u <= `STATEU_READ_REG;
                            release_flag <= 1'b0;
                            touch_count <= 0;
                            if(stateu_finish) begin
                                top_count <= top_count + 1;
                            end
                        end
                        5'd1: begin
                            if(rdata_buffer[7] == 1'b1 && (rdata_buffer[3:0] < 6 )) begin //touch flag
                                byte_word <= 1'b1;
                                write_time <= 9'd7;
                                touch_count <= rdata_buffer[3:0];//remember the touch number
                                state_u <= `STATEU_WRITE_REG;  //clear the touch flag
                                touch <= 1'b1;
                                if(stateu_finish) begin
                                    top_count <= 3;
                                end
                            end
                            else if(touch) begin   //touch
                                top_count <= 3;
                                state_u <= `STATEU_IDLE;
                                touch <= 1'b0;
                            end
                            else if(!touch) begin   //no touch
                                top_count <= 0;
                                state_u <= `STATEU_IDLE;
                            end
                        end
                        5'd2: begin   //delay 10 ms for anti shake
                            state_u <= `STATEU_DELAYMS;
                            delay_sel <= 0;
                            if(stateu_finish) begin
                                top_count <= 0;
                            end
                        end
                        5'd3: begin   //get coordinate
                            byte_word <= 1'b0;  //read 1 word
                            state_u <= `STATEU_READ_REG;
                            if(stateu_finish) begin
                                release_flag <= ~ touch;
                                top_count <= touch ? 2 : top_count + 1;
                                touch_flag <= touch;
                            end
                        end
                        5'd4: begin   //finish and delay 100ms
                            release_flag <= 1'b0;
                            state_u <= `STATEU_DELAYMS;
                            delay_sel <= 1;
                            if(stateu_finish) begin
                                top_count <= 0;
                            end
                        end
                        default:
                            ;
                    endcase
                end
                default:
                    ;
            endcase
        end
    end

    ////////////////////////////////////////////////
    ////////////////////////////////////////////////
    ////////////////////////////////////////////////

    //////////////// read/write ctrl ///////////////
    always@(*) begin
        int_o = `INT_DISABLE;
        if(!enable) begin
            wr = 1'b1;
        end
        else begin
            case(state)
                `STATE_READ_BYTE,`STATE_WAIT_ACK:
                    wr = 1'b0;
                default:
                    wr = 1'b1;
            endcase
        end
    end

    (* mark_debug = "true" *)reg [7:0] step_count;

    //inst cmd (this should be change later)
    always@(*) begin
        case(state_top)
            `FUNC_INIT: begin
                case(top_count)
                    5'd1: begin  //soft reset
                        case(write_count)
                            8'd0,8'd1:
                                wdata_buffer <= `INST_WR;     //inst write
                            8'd2,8'd3:
                                wdata_buffer <= `CTRL_REG_H;  //addr high
                            8'd4,8'd5:
                                wdata_buffer <= `CTRL_REG_L;  //addr low
                            8'd6,8'd7:
                                wdata_buffer <= `SOFT_RST_EN; //soft rst enable
                            default:
                                wdata_buffer <= 8'hff;
                        endcase
                    end
                    5'd3: begin //get GT_CFGS
                        case(step_count)
                            8'd0,8'd1:
                                wdata_buffer <= `INST_WR;     //inst write
                            8'd2,8'd3:
                                wdata_buffer <= `CFGS_REG_H;  //addr high
                            8'd4,8'd5:
                                wdata_buffer <= `CFGS_REG_L;  //addr low
                            8'd7,8'd8:
                                wdata_buffer <= `INST_RD;     //inst read
                            default:
                                wdata_buffer <= 8'hff;
                        endcase
                    end
                    5'd4: begin //set flash
                        case(write_count)
                            8'd0,8'd1:
                                wdata_buffer <= `INST_WR;     //inst write
                            8'd2,8'd3:
                                wdata_buffer <= `CFGS_REG_H; //addr high
                            8'd4,8'd5:
                                wdata_buffer <= `CFGS_REG_L; //addr low
                            default:
                                wdata_buffer <= douta;
                        endcase
                    end
                    5'd5: begin //set conf
                        case(write_count)
                            8'd0,8'd1:
                                wdata_buffer <= `INST_WR;      //inst write
                            8'd2,8'd3:
                                wdata_buffer <= `CHECK_REG_H;   //addr high
                            8'd4,8'd5:
                                wdata_buffer <= `CHECK_REG_L;   //addr low
                            8'd6,8'd7:
                                wdata_buffer <= 201;  //conf
                            8'd8,8'd9:
                                wdata_buffer <= 1;    //save in flash
                            default:
                                wdata_buffer <= 8'hff;
                        endcase
                    end
                    5'd7: begin //soft reset finish
                        case(write_count)
                            8'd0,8'd1:
                                wdata_buffer <= `INST_WR;      //inst write
                            8'd2,8'd3:
                                wdata_buffer <= `CTRL_REG_H;   //addr high
                            8'd4,8'd5:
                                wdata_buffer <= `CTRL_REG_L;   //addr low
                            8'd6,8'd7:
                                wdata_buffer <= `SOFT_RST_DS;  //soft rst disable
                            default:
                                wdata_buffer <= 8'hff;
                        endcase
                    end
                    default:
                        wdata_buffer <= 8'hff;
                endcase
            end
            `FUNC_SCAN: begin
                case(top_count)
                    5'd0: begin  //read status reg
                        case(step_count)
                            8'd0,8'd1:
                                wdata_buffer <= `INST_WR;     //inst write
                            8'd2,8'd3:
                                wdata_buffer <= `GSTID_REG_H; //addr high
                            8'd4,8'd5:
                                wdata_buffer <= `GSTID_REG_L; //addr low
                            8'd7,8'd8:
                                wdata_buffer <= `INST_RD;     //inst read
                            default:
                                wdata_buffer <= 8'hff;
                        endcase
                    end
                    5'd1: begin  //write status reg
                        case(write_count)
                            8'd0,8'd1:
                                wdata_buffer <= `INST_WR;     //inst write
                            8'd2,8'd3:
                                wdata_buffer <= `GSTID_REG_H; //addr high
                            8'd4,8'd5:
                                wdata_buffer <= `GSTID_REG_L; //addr low
                            8'd6,8'd7:
                                wdata_buffer <= 8'h0;         //clr touch flag
                            default:
                                wdata_buffer <= 8'hff;
                        endcase
                    end
                    5'd3: begin   //get coordinate
                        case(step_count)
                            8'd0,8'd1:
                                wdata_buffer <= `INST_WR;     //inst write
                            8'd2,8'd3:
                                wdata_buffer <= `TP1_REG_H;   //addr high
                            8'd4,8'd5:
                                wdata_buffer <= `TP1_REG_L;   //addr low
                            8'd7,8'd8:
                                wdata_buffer <= `INST_RD;     //inst read
                            default:
                                wdata_buffer <= 8'hff;
                        endcase
                    end
                    default:
                        wdata_buffer <= 8'hff;
                endcase
            end
            default:
                wdata_buffer <= 8'hff;
        endcase

        ///// delete this later ////////
        /*if(state_u == `STATEU_READ_REG)begin
            case(step_count)
                8'd1,8'd2:begin
                    wdata_buffer <= `INST_WR;
                end
                8'd3,8'd4:begin
                    wdata_buffer <= `PID_REG_H;
                end
                8'd5,8'd6:begin
                    wdata_buffer <= `PID_REG_L;
                end
                8'd8,8'd9:begin
                    wdata_buffer <= `INST_RD;
                end
                default:wdata_buffer <= 8'hff;
            endcase
        end else begin
            wdata_buffer <= 8'hff;
        end*/
        ////////////////////////////////
    end

    ////////////////// median ctrl ///////////////////

    reg [19:0] delay_ms_count;
    reg write_busy;

    always@(posedge ts_clk) begin
        if(!enable) begin
            step_count <= 0;
            state <= `STATE_IDLE;
            delay_ms_count <= 0;
            write_busy <= 1'b0;
            write_count <= 0;
        end
        else begin
            case(state_u)
                `STATEU_IDLE: begin
                    state <= `STATE_IDLE;
                    step_count <= 0;
                end
                `STATEU_READ_REG: begin
                    case(step_count)
                        8'd0: begin  //start
                            if(state_finish) begin
                                state <= `STATE_SEND_BYTE;
                                step_count <= step_count + 1;
                            end
                            else begin
                                state <= `STATE_START;
                            end
                        end
                        8'd1,8'd3,8'd5,8'd8: begin  //send addr and cmd
                            if(state_finish) begin
                                state <= `STATE_WAIT_ACK;
                                step_count <= step_count + 1;
                            end
                            else begin
                                state <= `STATE_SEND_BYTE;
                            end
                        end
                        8'd2,8'd4: begin
                            if(state_finish) begin
                                state <= `STATE_SEND_BYTE;
                                step_count <= step_count + 1;
                            end
                            else begin
                                state <= `STATE_WAIT_ACK;
                            end

                        end
                        8'd6: begin   //start reading
                            if(state_finish) begin
                                state <= `STATE_START;
                                step_count <= step_count + 1;
                            end
                            else begin
                                state <= `STATE_WAIT_ACK;
                            end
                        end
                        8'd7: begin  //send cmd reading
                            if(state_finish) begin
                                state <= `STATE_SEND_BYTE;
                                step_count <= step_count + 1;
                            end
                            else begin
                                state <= `STATE_START;
                            end
                        end
                        8'd9: begin
                            if(state_finish) begin
                                state <= `STATE_DELAY;
                                step_count <= step_count + 1;
                            end
                            else begin
                                state <= `STATE_WAIT_ACK;
                            end
                        end
                        8'd10,8'd13,8'd16,8'd19: begin  //read
                            if(state_finish) begin
                                state <= `STATE_READ_BYTE;
                                step_count <= (byte_word)? 8'd20 : step_count + 1; //Read Byte or Read Word
                            end
                            else begin
                                state <= `STATE_DELAY;
                            end
                        end
                        8'd11,8'd14,8'd17: begin  //read ack
                            if(state_finish) begin
                                state <= `STATE_SEND_ACK;
                                step_count <= step_count + 1;
                            end
                            else begin
                                state <= `STATE_READ_BYTE;
                            end
                        end
                        8'd12,8'd15,8'd18: begin //wait
                            if(state_finish) begin
                                state <= `STATE_DELAY;
                                step_count <= step_count + 1;
                            end
                            else begin
                                state <= `STATE_SEND_ACK;
                            end
                        end
                        8'd20: begin
                            if(state_finish) begin
                                state <= `STATE_SEND_NACK; //read finish
                                step_count <= step_count + 1;
                            end
                            else begin
                                state <= `STATE_READ_BYTE;
                            end
                        end
                        8'd21: begin
                            if(state_finish) begin //stop
                                state <= `STATE_STOP;
                                step_count <= step_count + 1;
                            end
                            else begin
                                state <= `STATE_SEND_NACK;
                            end
                        end
                        8'd22: begin
                            if(state_finish) begin //to idle
                                state <= `STATE_IDLE;
                                step_count <= step_count + 1;
                                stateu_finish <= 1'b1;
                            end
                            else begin
                                state <= `STATE_STOP;
                            end
                        end
                        8'd23: begin
                            step_count <= 0;
                            stateu_finish <= 0;
                            state <= `STATE_IDLE;
                        end
                        default:
                            ;
                    endcase
                end
                `STATEU_WRITE_REG: begin
                    if(write_count == 0) begin
                        if(state_finish) begin
                            write_busy <= 1'b1;
                            state <= `STATE_SEND_BYTE;
                            write_count <= write_count + 1;
                        end
                        else begin
                            state <= `STATE_START;
                        end
                    end
                    else if(write_count[0] == 1'b1 && write_busy) begin //write byte
                        if(state_finish) begin
                            state <= `STATE_WAIT_ACK;
                            write_count <= write_count + 1;
                            if(write_count == write_time) begin //break when write finish
                                write_busy <= 1'b0;
                            end
                        end
                        else begin
                            state <= `STATE_SEND_BYTE;
                        end
                    end
                    else if(write_count[0] == 1'b0 && write_busy) begin     //wait for ack
                        if(state_finish) begin
                            write_busy <= 1'b1;
                            state <= `STATE_SEND_BYTE;
                            write_count <= write_count + 1;
                        end
                        else begin
                            state <= `STATE_WAIT_ACK;
                        end
                    end
                    else if(write_count[0] == 1'b0 && !stateu_finish) begin //wait for ack
                        if(state_finish) begin
                            state <= `STATE_STOP;
                            write_count <= write_count + 1;
                        end
                        else begin
                            state <= `STATE_WAIT_ACK;
                        end
                    end
                    else if(write_count[0] == 1'b1 && !stateu_finish) begin  //stop
                        if(state_finish) begin //to idle
                            state <= `STATE_IDLE;
                            write_count <= write_count + 1;
                            stateu_finish <= 1'b1;
                        end
                        else begin
                            state <= `STATE_STOP;
                        end
                    end
                    else if(write_count[0] == 1'b0 && stateu_finish) begin  //finish
                        write_count <= 0;
                        stateu_finish <= 0;
                        state <= `STATE_IDLE;
                    end
                end
                `STATEU_DELAYMS: begin
                    state <= `STATE_IDLE;
                    if(delay_sel && delay_ms_count < 1000000) begin
                        delay_ms_count <= delay_ms_count + 1;
                    end
                    else if(delay_sel && delay_ms_count == 1000000) begin
                        delay_ms_count <= 0;
                    end

                    if(!delay_sel && delay_ms_count < 100000) begin
                        delay_ms_count <= delay_ms_count + 1;
                    end
                    else if(!delay_sel && delay_ms_count == 100000) begin
                        delay_ms_count <= 0;
                    end

                    if(delay_sel && delay_ms_count == 1000000) begin
                        stateu_finish <= 1;
                    end
                    else if(delay_sel && delay_ms_count == 0) begin
                        stateu_finish <= 0;
                    end

                    if(!delay_sel && delay_ms_count == 100000) begin
                        stateu_finish <= 1;
                    end
                    else if(!delay_sel && delay_ms_count == 0) begin
                        stateu_finish <= 0;
                    end
                end
                default:
                    ;
            endcase
        end

    end

    reg[3:0] trans_count;
    reg[15:0] delay_count;
    (*mark_debug = "true"*)reg[8:0] func_count;  //start at 1
    //reg[3:0] beat_count;
    //reg ack_reg;

    //////////////// bottom ctrl ///////////////////
    always@(posedge ts_clk) begin
        if(!enable) begin
            lcd_ct_scl <= 1'b1;
            data_o <= 1'b1;
            func_count <= 1;
            state_finish <= 1'b0;
            trans_count <= 4'd7;
            //ack_reg <= 1'b0;
            delay_count <= 0;
        end
        else begin
            case(state)
                `STATE_IDLE: begin      /////

                end
                `STATE_START: begin     /////
                    if(func_count == 0) begin
                        lcd_ct_scl <= 1'b0;
                        data_o <= 1'b0;
                        func_count <= func_count + 1;
                        state_finish <= 1'b0;
                    end
                    else if(func_count <= 10) begin
                        lcd_ct_scl <= 1'b1;
                        data_o <= 1'b1;
                        func_count <= func_count + 1;
                    end
                    else if(func_count <= 20) begin
                        lcd_ct_scl <= 1'b1;
                        data_o <= 1'b0;
                        func_count <= func_count + 1;
                    end
                    else if(func_count <= 29) begin
                        lcd_ct_scl <= 1'b0;
                        data_o <= 1'b0;
                        func_count <= func_count+1;
                    end
                    else if(func_count == 30) begin
                        lcd_ct_scl <= 1'b0;
                        data_o <= 1'b0;
                        func_count <= 0;
                        state_finish <= 1'b1;
                    end
                end
                `STATE_STOP: begin      /////
                    if(func_count == 0) begin
                        lcd_ct_scl <= 1'b1;
                        data_o <= 1'b1;
                        func_count <= func_count + 1;
                        state_finish <= 1'b0;
                    end
                    else if(func_count <= 10) begin
                        lcd_ct_scl <= 1'b0;
                        data_o <= 1'b0;
                        func_count <= func_count + 1;
                    end
                    else if(func_count <= 20) begin
                        lcd_ct_scl <= 1'b1;
                        data_o <= 1'b0;
                        func_count <= func_count + 1;
                    end
                    else if(func_count <= 49) begin
                        lcd_ct_scl <= 1'b1;
                        data_o <= 1'b1;
                        func_count <= func_count + 1;
                    end
                    else if(func_count == 50) begin
                        func_count <= 0;
                        state_finish <= 1'b1;
                    end
                end
                `STATE_DELAY: begin     /////
                    if(delay_count < 300) begin
                        delay_count <= delay_count+1;
                        state_finish <= 1'b0;
                    end
                    else if(delay_count == 300) begin
                        delay_count <= 0;
                        state_finish <= 1'b1;
                    end
                end
                `STATE_SEND_BYTE: begin /////

                    //trans count
                    if(func_count == 0) begin
                        trans_count <= 4'd7;
                    end
                    else if(func_count[4:0]==5'd0) begin
                        trans_count <= trans_count - 1;
                    end

                    //func count & finish signal
                    if(func_count == 0) begin
                        func_count <= func_count + 1;
                        state_finish <= 1'b0;
                    end
                    else if(func_count < 256) begin
                        func_count <= func_count + 1;
                    end
                    else if(func_count == 256) begin
                        func_count <= 0;
                        state_finish <= 1'b1;
                    end

                    //scl cmd
                    if(func_count == 0) begin
                        lcd_ct_scl <= 1'b0;
                    end
                    else if(func_count == 256) begin
                        lcd_ct_scl <= 1'b0;
                    end
                    else if(func_count[3:0] == 4'd8) begin
                        lcd_ct_scl <= ~lcd_ct_scl;
                    end

                    data_o <= wdata_buffer[trans_count];
                end
                `STATE_WAIT_ACK: begin /////wait for ack
                    if(func_count == 0) begin
                        lcd_ct_scl <= 1'b0;
                        state_finish <= 1'b0;
                        func_count <= func_count+1;
                    end
                    else if(func_count == 9'h1ff) begin
                        lcd_ct_scl <= 1'b0;
                        func_count <= 0;
                    end
                    else if (func_count > 16 && lcd_sda == 1'b0) begin
                        lcd_ct_scl <= 1'b0;
                        func_count <= 0;
                        state_finish <= 1'b1;
                    end
                    else begin
                        lcd_ct_scl <= 1'b1;
                        func_count <= func_count+1;
                    end
                end
                `STATE_SEND_ACK: begin  /////
                    if(func_count == 0) begin
                        func_count <= func_count + 1;
                        state_finish <= 1'b0;
                        lcd_ct_scl <= 1'b0;
                        data_o <= 1'b0;
                    end
                    else if(func_count <=20) begin  //1
                        lcd_ct_scl <= 1'b0;
                        //lcd_sda <= 1'b0;
                        func_count <= func_count + 1;
                    end
                    else if(func_count <= 40) begin //2
                        lcd_ct_scl <= 1'b0;
                        data_o <= 1'b0;
                        func_count <= func_count + 1;
                    end
                    else if(func_count <= 59) begin //3
                        lcd_ct_scl <= 1'b1;
                        data_o <= 1'b0;
                        func_count <= func_count + 1;
                    end
                    else if(func_count <= 60) begin
                        func_count <= 0;
                        state_finish <= 1'b1;
                        lcd_ct_scl <= 1'b0;
                        data_o <= 1'b0;
                    end
                end
                `STATE_SEND_NACK: begin /////
                    if(func_count == 0) begin
                        func_count <= func_count + 1;
                        state_finish <= 1'b0;
                        lcd_ct_scl <= 1'b0;
                        data_o <= 1'b1;
                    end
                    else if(func_count <=20) begin  //1
                        lcd_ct_scl <= 1'b0;
                        //lcd_sda <= 1'b0;
                        func_count <= func_count + 1;
                    end
                    else if(func_count <= 40) begin //2
                        lcd_ct_scl <= 1'b0;
                        data_o <= 1'b1;
                        func_count <= func_count + 1;
                    end
                    else if(func_count <= 59) begin //3
                        lcd_ct_scl <= 1'b1;
                        data_o <= 1'b1;
                        func_count <= func_count + 1;
                    end
                    else if(func_count <= 60) begin
                        func_count <= 0;
                        state_finish <= 1'b1;
                        lcd_ct_scl <= 1'b0;
                        data_o <= 1'b1;
                    end
                end
                `STATE_READ_BYTE: begin /////
                    //trans count
                    if(func_count == 0) begin
                        trans_count <= 4'd7;
                    end
                    else if(func_count[4:0]==5'd0) begin
                        trans_count <= trans_count - 1;
                    end

                    //func count & finish signal
                    if(func_count == 0) begin
                        func_count <= func_count + 1;
                        state_finish <= 1'b0;
                    end
                    else if(func_count < 256) begin
                        func_count <= func_count + 1;
                    end
                    else if(func_count == 256) begin
                        func_count <= 0;
                        state_finish <= 1'b1;
                    end

                    //scl cmd
                    if(func_count == 0) begin
                        lcd_ct_scl <= 1'b0;
                    end
                    else if(func_count == 256) begin
                        lcd_ct_scl <= 1'b0;
                    end
                    else if(func_count[3:0] == 4'd8) begin
                        lcd_ct_scl <= ~lcd_ct_scl;
                    end

                    //read buffer cmd
                    if(lcd_ct_scl == 1'b1) begin
                        rdata_buffer[trans_count] <= lcd_sda;
                    end
                end
                default:
                    ;
            endcase
        end
    end

    always@(posedge ts_clk) begin
        if(!enable) begin
            rword_buffer <= 32'd0;
            cfgs <= 8'd0;
        end
        else begin
            if(state_top == `FUNC_SCAN && state_u == `STATEU_READ_REG && !byte_word && state == `STATE_READ_BYTE && state_finish == 1'b1) begin
                rword_buffer <= {rword_buffer[23:0],rdata_buffer[7:0]};
            end

            if(state_top == `FUNC_INIT && state_u == `STATEU_READ_REG && byte_word && state == `STATE_READ_BYTE && state_finish == 1'b1) begin
                cfgs <= rdata_buffer[7:0];
            end
        end
    end
endmodule
