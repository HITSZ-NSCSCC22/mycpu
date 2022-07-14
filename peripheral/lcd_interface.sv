module lcd_interface (
    input logic pclk,  //cycle time 20ns,50Mhz
    input logic rst_n, //low is powerful

    //to lcd 
    /**屏幕显示信号**/
    output logic lcd_rst,  //lcd 复位键
    output logic lcd_cs,
    output logic lcd_rs,  //0:inst 1:data
    output logic lcd_wr,  //write signal ,low is powerful
    output logic lcd_rd,  //read signal,low is powerful
    //inout logic [15:0] lcd_data_io,  //16位808并口,双向数据线
    input logic [15:0] lcd_data_i,  //from lcd
    output logic [15:0] lcd_data_o,  //to lcd
    output logic lcd_bl_ctr,  //

    /**触摸屏幕信号**/
    // inout logic lcd_ct_int,
    // inout logic lcd_ct_sda,
    // output logic lcd_ct_scl,
    // output logic lcd_rstn  //lcd触摸屏幕复位信号

    //from lcd ctrl
    input logic [31:0] lcd_addr_buffer,  //store write reg addr
    input logic [31:0] lcd_data_buffer,  //store data to lcd
    input logic write_lcd,  //write lcd enable signal    

    //to lcd top
    output logic lcd_write_data_ctrl,  //写控制信号，用于决定顶层的lcd_data_io

    //from lcd_id
    input logic [15:0] data_i,
    input logic we,
    input logic wr,
    input logic lcd_rs_i,  //distinguish inst or data

    //to lcd_id
    output logic busy

);
  always @(posedge pclk) begin
    if (~rst_n) lcd_bl_ctr <= 0;
    else lcd_bl_ctr <= 1;
  end

  always @(posedge pclk) begin
    if (~rst_n) lcd_cs <= 1;
    else lcd_cs <= 0;
  end

  assign lcd_rst = rst_n;
  //DFA
  enum int {
    IDLE,
    SETUP_READ,
    READING,
    SETUP_WRITE,
    WRITING
  } state;
  logic work;
  //stall lcd_id one cycle
  logic stall;
  assign stall = we && (state == IDLE);

  //read delay
  logic [31:0] time_counter;  //延迟的时钟周期数
  logic [31:0] delay_time;  //需要延迟的时钟周期数
  logic [31:0] read_counter;  //读的次数
  logic [31:0] read_number;  //需要读的次数


  always_ff @(posedge pclk) begin
    if (~rst_n) begin
      state <= IDLE;
      lcd_rs <= 0;
      lcd_wr <= 1;
      lcd_rd <= 1;
      lcd_data_o <= 0;
      lcd_write_data_ctrl <= 0;
      work <= 0;
    end else begin
      case (state)
        IDLE: begin
          if (we) begin
            state <= SETUP_WRITE;
            lcd_rs <= lcd_rs_i;
            lcd_wr <= 0;
            lcd_rd <= 1;
            lcd_data_o <= data_i;
            lcd_write_data_ctrl <= 1;
            work <= 1;
          end else begin
            state <= IDLE;
            lcd_rs <= 0;
            lcd_wr <= 1;
            lcd_rd <= 1;
            lcd_data_o <= 0;
            lcd_write_data_ctrl <= 0;
            work <= 0;
          end
        end

        //WRITE PREPARATION
        SETUP_WRITE: begin
          state <= WRITING;
          lcd_rs <= lcd_rs_i;
          lcd_wr <= 1;
          lcd_rd <= 1;
          lcd_data_o <= data_i;
          lcd_write_data_ctrl <= 1;
          work <= wr ? 0 : 1;//读指令则lcd继续工作，写指令lcd进入空闲状态不工作
        end

        //WRITING
        WRITING: begin
          if (wr) begin
            state <= IDLE;
            lcd_rs <= 0;
            lcd_wr <= 1;
            lcd_rd <= 1;
            lcd_data_o <= 0;
            lcd_write_data_ctrl <= 0;
            work <= 0;
          end else begin
            state <= SETUP_READ;
            lcd_rs <= 1;
            lcd_wr <= 1;
            lcd_rd <= 0;
            lcd_data_o <= 0;
            lcd_write_data_ctrl <= 0;
            work <= 1;
          end
        end

        //READ PREPARATION
        SETUP_READ: begin
          if (time_counter == delay_time) begin
            state <= READING;
            lcd_rs <= 1;
            lcd_wr <= 1;
            lcd_rd <= 1;
            lcd_data_o <= 0;
            lcd_write_data_ctrl <= 0;
            work <= 1;
          end else begin
            state <= SETUP_READ;
            lcd_rs <= 1;
            lcd_wr <= 1;
            lcd_rd <= 0;
            lcd_data_o <= 0;
            lcd_write_data_ctrl <= 0;
            work <= 1;
          end
        end
        //TODO 有问题
        //READING
        READING: begin
          if (read_counter == read_number && time_counter == delay_time) begin
            state <= IDLE;
            lcd_rs <= 0;
            lcd_wr <= 1;
            lcd_rd <= 1;
            lcd_data_o <= 0;
            lcd_write_data_ctrl <= 0;
            work <= 0;
          end else begin
            state <= READING;
            lcd_rs <= 1;
            lcd_wr <= 1;
            lcd_rd <= 1;
            lcd_data_o <= 0;
            lcd_write_data_ctrl <= 0;
            work <= 1;
          end
        end

      endcase
    end
  end


endmodule
