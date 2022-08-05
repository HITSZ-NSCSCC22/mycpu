`define END1 32'd384018
`define COLOR 32'd19
module lcd_refresh (
        input logic pclk,
        input logic rst_n,
        //from lcd_ctrl
        input logic enable,
        input logic [6:0]refresh_req,//to choose the background
        output logic [15:0]refresh_data,
        output logic refresh_rs,
        output logic data_ok,
        output logic refresh_ok//refresh is over
    );
    logic [31:0]addra;
    logic [15:0]info;//the refresh bram information
    always_ff @(posedge pclk) begin
        if(~rst_n)
            info<=0;
        else if(addra==0)
            info<=refresh_data;
        else
            info<=info;
    end

    //get data grom refresh_bram
    enum int{
             IDLE,
             ADDR,
             DATA
         } state;
    logic white;//write the default background
    logic start;//read from bram start
    always_ff @(posedge pclk) begin
        if(~rst_n) begin
            addra<=0;
            data_ok<=0;
            refresh_ok<=0;
            state<=IDLE;
            refresh_rs<=0;
            white<=0;
            start<=0;
        end
        else begin
            case(state)
                IDLE: begin
                    refresh_rs<=0;
                    if(enable&&(addra==0)&&(~start)) begin
                        state<=ADDR;
                        start<=1;
                    end
                    else if(enable) begin
                        state<=ADDR;
                        addra<=addra+1;
                        start<=1;
                    end
                end
                ADDR: begin
                    state<=DATA;
                    data_ok<=1;
                    if(addra>=`COLOR)
                        refresh_rs<=1;
                    else if(addra[0]==0)
                        refresh_rs<=0;
                    else if(addra[0]==1)
                        refresh_rs<=1;

                    if(addra==`END1&&((refresh_req==7'b000_00000)||refresh_req[0]))
                        refresh_ok<=1;
                    else
                        refresh_ok<=0;

                    //如果时绘制默认背景那么颜色不需要从bram中取，这样能够节约资源
                    if(addra>=`COLOR&&((refresh_req==7'b000_00000)||refresh_req[0]))
                        white<=1;
                    else
                        white<=0;
                end
                DATA: begin
                    state<=IDLE;
                    data_ok<=0;
                    refresh_ok<=0;
                    if(refresh_ok) begin
                        addra<=0;
                        white<=0;
                        start<=0;
                    end
                    refresh_rs<=0;

                end
                default: begin
                    addra<=0;
                    data_ok<=0;
                    refresh_ok<=0;
                    state<=IDLE;
                    white<=0;
                    refresh_rs<=0;
                end
            endcase
        end
    end

    //data to lcd_ctrl
    logic [15:0]data1_o;
    always_comb begin
        refresh_data=0;
        case(refresh_req)
            7'b000_0000,7'b000_0001:
                refresh_data=white?16'hffff:data1_o;
            default:
                refresh_data=0;
        endcase
    end

    refresh1_bram u_refresh1_bram (
                      .clka(pclk),    // input wire clka
                      .ena(1),      // input wire ena
                      .wea(0),      // input wire [0 : 0] wea
                      .addra(addra[4:0]),  // input wire [4 : 0] addra
                      .dina(0),    // input wire [15 : 0] dina
                      .douta(data1_o)  // output wire [15 : 0] douta
                  );


endmodule
