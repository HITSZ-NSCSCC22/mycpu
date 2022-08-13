//char library
//用于从字库中取出字符的点阵
`define CHAR_WIDTH 23
`define CHAR_HEIGHT 39
module char_lib (
        input      logic pclk,
        input      logic rst_n,

        //from char_ctrl
        input      logic [7:0]ascii_code,
        input      logic [7:0]chinese_code,
        input      logic is_en,
        input      logic char_req,

        //to char_ctrl
        output     logic data_ok,
        output     logic [`CHAR_WIDTH:0]douta,
        output     logic finish,
        output     logic [31:0]col
    );

    enum int{
             IDLE,
             BACK,
             ADDR,
             DATA
         } state;
    logic [31:0]count;
    logic flag;
    assign flag=(count==`CHAR_HEIGHT)?1:0;
    always_ff @(posedge pclk) begin
        if(~rst_n)
            count<=0;
        else if(state==DATA)
            count<=count+1;
        else if(state==IDLE)
            count<=0;
    end
    logic start;//read from bram start
    logic [9:0]addra;
    always_ff @(posedge pclk) begin
        if(~rst_n) begin
            addra<=0;
            data_ok<=0;
            state<=IDLE;
            start<=0;
            finish<=0;
            col<=0;
        end
        else begin
            case(state)
                IDLE: begin
                    if(char_req) begin
                        addra<=0;
                        state<=BACK;
                        start<=0;
                    end
                    finish<=0;
                    col<=0;
                end
                BACK: begin
                    state<=ADDR;
                    if(start) begin
                        addra<=addra+1;
                    end
                    else begin
                        addra<=addra;
                    end
                    start<=1;
                end
                ADDR: begin
                    state<=DATA;
                    data_ok<=1;
                    col<=count;
                    if(flag)
                        finish<=1;
                    else
                        finish<=0;
                end
                DATA: begin
                    data_ok<=0;
                    if(finish) begin
                        addra<=0;
                        state<=IDLE;
                        start<=0;
                        finish<=0;
                        col<=0;
                    end
                    else begin
                        state<=BACK;
                    end
                end
                default: begin
                    addra<=0;
                    data_ok<=0;
                    state<=IDLE;
                    start<=0;
                    finish<=0;
                    col<=0;
                end
            endcase
        end
    end

    char_library u_char_library (
                     .clka(pclk),    // input wire clka
                     .ena(1),      // input wire ena
                     .wea(0),      // input wire [0 : 0] wea
                     .addra(addra),  // input wire [9 : 0] addra
                     .dina(0),    // input wire [23 : 0] dina
                     .douta(douta)  // output wire [23 : 0] douta
                 );
endmodule //moduleName
