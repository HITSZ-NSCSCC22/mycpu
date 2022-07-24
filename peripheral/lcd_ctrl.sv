//to connect with CPU and translate AXI to lcd signal
`include "axi_defines.sv"
`define LCD_INPUT 32'h1fd0c000
`define TOUCH_INPUT 32'h1fd0c004
module lcd_ctrl (
    //rst and clk,clk is lower than cpu
    input logic pclk,
    input logic rst_n,

    //from AXI
    //ar
    input logic [`ID] s_arid,  //arbitration
    input logic [`ADDR] s_araddr,
    input logic [`Len] s_arlen,
    input logic [`Size] s_arsize,
    input logic [`Burst] s_arburst,
    input logic [`Lock] s_arlock,
    input logic [`Cache] s_arcache,
    input logic [`Prot] s_arprot,
    input logic s_arvalid,
    output logic s_arready,

    //r
    output logic [`ID] s_rid,
    output logic [31:0] s_rdata,
    output logic [`Resp] s_rresp,
    output logic s_rlast,  //the last read data
    output logic s_rvalid,
    input logic s_rready,

    //aw
    input logic [`ID] s_awid,
    input logic [`ADDR] s_awaddr,
    input logic [`Len] s_awlen,
    input logic [`Size] s_awsize,
    input logic [`Burst] s_awburst,
    input logic [`Lock] s_awlock,
    input logic [`Cache] s_awcache,
    input logic [`Prot] s_awprot,
    input logic s_awvalid,
    output logic s_awready,

    //w
    input logic [`ID] s_wid,
    input logic [31:0] s_wdata,
    input logic [3:0] s_wstrb,  //字节选通位和sel差不多
    input logic s_wlast,
    input logic s_wvalid,
    output logic s_wready,

    //b
    output logic [`ID] s_bid,
    output logic [`Resp] s_bresp,
    output logic s_bvalid,
    input logic s_bready,

    //to lcd_id
    output logic [31:0] lcd_addr_buffer,  //store write reg addr
    output logic [31:0] lcd_data_buffer,  //store data to lcd
    output logic write_lcd,  //write lcd enable signal

    //from lcd_interface
    input logic [31:0] lcd_input_data,  //data form lcd input

    //from lcd_id
    input logic write_ok  //数据和指令写出去后才能继续写
);
  enum logic [2:0] {
    R_ADDR = 3'b001,
    R_DATA = 3'b010
  } r_state;
  enum logic [2:0] {
    W_IDLE = 3'b011,
    W_ADDR = 3'b100,
    W_DATA = 3'b101,
    W_RESP = 3'b110
  } w_state;
  logic [31:0] addr_buffer;
  assign s_rresp = 0;

  //Read form lcd
  always_ff @(posedge pclk) begin
    if (~rst_n) begin
      r_state <= R_ADDR;
      s_rid <= 0;
      addr_buffer <= 0;
      s_arready <= 1;
      s_rdata <= 0;
      s_rlast <= 0;
      s_rvalid <= 0;
    end else begin
      case (r_state)
        R_ADDR: begin
          if (s_arvalid && s_arready) begin
            r_state <= R_DATA;
            s_rid <= s_arid;
            addr_buffer <= s_araddr;
            s_arready <= 0;
            s_rdata <= 0;
            s_rlast <= 0;
            s_rvalid <= 0;
          end else begin
            r_state <= R_ADDR;
            s_rid <= 0;
            addr_buffer <= 0;
            s_arready <= 1;
            s_rdata <= 0;
            s_rlast <= 0;
            s_rvalid <= 0;
          end
        end
        R_DATA: begin
          if (s_rvalid && s_rready) begin
            r_state <= R_ADDR;
            s_rid <= 0;
            addr_buffer <= 0;
            s_arready <= 1;
            s_rdata <= 0;
            s_rlast <= 0;
            s_rvalid <= 0;
          end else begin
            //choose data by addr
            case (addr_buffer)
              //TODO
              `LCD_INPUT: s_rdata <= lcd_input_data;
              `TOUCH_INPUT: s_rdata <= 32'hffff_ffff;
              default: s_rdata <= 32'heeee_eeee;
            endcase
            r_state <= r_state;
            s_rid <= s_rid;
            addr_buffer <= addr_buffer;
            s_arready <= 1;
            s_rlast <= 1;
            s_rvalid <= 1;
          end
        end
        default: begin
          r_state <= R_ADDR;
          s_rid <= 0;
          addr_buffer <= 0;
          s_arready <= 1;
          s_rdata <= 0;
          s_rlast <= 0;
          s_rvalid <= 0;
        end
      endcase
    end
  end

  assign s_bid   = 0;
  assign s_bresp = 0;

  //Write to lcd
  always_ff @(posedge pclk) begin
    if (~rst_n) begin
      w_state <= W_IDLE;
      s_awready <= 0;
      s_wready <= 0;
      s_bvalid <= 0;
      lcd_addr_buffer <= 0;
      lcd_data_buffer <= 0;
      write_lcd <= 0;
    end else begin
      case (w_state)
        W_IDLE:begin
          if(write_ok)// lcd is not busy,allow to write lcd now
          begin
            w_state <= W_ADDR;
            s_awready <= 1;
            s_wready <= 0;
            s_bvalid <= 0;
            lcd_addr_buffer <= 0;
            lcd_data_buffer <= 0;
            write_lcd <= 0;
          end
          else begin
            w_state <= W_IDLE;
            s_awready <= 0;
            s_wready <= 0;
            s_bvalid <= 0;
            lcd_addr_buffer <= 0;
            lcd_data_buffer <= 0;
            write_lcd <= 0;
          end
        end
        W_ADDR: begin
          if (s_awvalid && s_wready) begin
            w_state <= W_DATA;
            s_awready <= 0;
            s_wready <= 1;
            s_bvalid <= 0;
            lcd_addr_buffer <= s_awaddr;
            lcd_data_buffer <= 0;
            write_lcd <= 0;
          end else begin
            w_state <= W_ADDR;
            s_awready <= 1;
            s_wready <= 0;
            s_bvalid <= 0;
            lcd_addr_buffer <= 0;
            lcd_data_buffer <= 0;
            write_lcd <= 0;
          end
        end
        W_DATA: begin
          if (s_wvalid && s_wready) begin
            w_state <= W_RESP;
            s_awready <= 0;
            s_wready <= 0;
            s_bvalid <= 0;
            lcd_addr_buffer <= lcd_addr_buffer;
            lcd_data_buffer <= s_wdata;
            write_lcd <= 1&&(s_wstrb==4'b1111);
          end else begin
            w_state <= W_DATA;
            s_awready <= 0;
            s_wready <= 1;
            s_bvalid <= 0;
            lcd_addr_buffer <= lcd_addr_buffer;
            lcd_data_buffer <= 0;
            write_lcd <= 0;
          end
        end
        W_RESP: begin
          if (s_bvalid && s_wready) begin
            w_state <=  W_IDLE;
            s_awready <= 0;
            s_wready <= 0;
            s_bvalid <= 0;
            lcd_addr_buffer <= 0;
            lcd_data_buffer <= 0;
            write_lcd <= 0;
          end 
          // else if (write_ok) begin//write_ok为高表示指令和数据译码结束下一周期写入lcd中
          //   w_state <= W_RESP;
          //   s_awready <= 1;
          //   s_wready <= 0;
          //   s_bvalid <= 1;
          //   lcd_addr_buffer <= lcd_addr_buffer;
          //   lcd_data_buffer <= lcd_data_buffer;
          //   write_lcd <= 0;
          // end 
          else begin
            w_state <= W_RESP;
            s_awready <= 0;
            s_wready <= 0;
            s_bvalid <= 1;
            lcd_addr_buffer <= lcd_addr_buffer;
            lcd_data_buffer <= lcd_data_buffer;
            write_lcd <= write_lcd;
          end
        end
        default: begin
          w_state <= W_IDLE;
          s_awready <= 0;
          s_wready <= 0;
          s_bvalid <= 0;
          lcd_addr_buffer <= 0;
          lcd_data_buffer <= 0;
          write_lcd <= 0;
        end
      endcase
    end
  end

endmodule
