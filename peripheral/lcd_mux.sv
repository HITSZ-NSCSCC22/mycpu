module lcd_mux (
        input  logic        pclk,
        input  logic        rst_n,
        //from lcd_core
        input logic cpu_draw,
        //from lcd_id
        input  logic        id_we,             //write enable
        input  logic        id_wr,             //0:read lcd 1:write lcd,distinguish inst kind
        input  logic        id_lcd_rs,
        input  logic [15:0] id_data_o,
        input  logic        id_fm_i,
        input  logic        id_read_color_o,
        //from lcd_init
        input  logic [15:0] init_data,
        input  logic        init_we,
        input  logic        init_wr,
        input  logic        init_rs,
        input  logic        init_work,
        input  logic        init_finish,
        //from lcd_interface
        input  logic        init_write_ok_i,
        input  logic        busy_i,
        input  logic        write_color_ok_i,  //write one color
        //to lcd_id
        output logic        busy_o,
        output logic        write_color_ok_o,  //write one color

        //to lcd_init
        output logic init_write_ok_o,

        //to lcd_interface
        output logic [15:0] data_o,
        output logic we_o,
        output logic wr_o,
        output logic lcd_rs_o,  //distinguish inst or data
        output logic id_fm_o,  //distinguish read id or read fm,0:id,1:fm
        output logic read_color_o  //if read color ,reading time is at least 2
    );
    //to lcd_interface
    assign data_o = init_finish ? id_data_o : init_data;
    assign we_o = init_finish ? id_we : init_we;
    assign wr_o = init_finish ? id_wr : init_wr;
    assign lcd_rs_o = init_finish ? id_lcd_rs : init_rs;
    assign id_fm_o = init_finish ? id_fm_i : 0;
    assign read_color_o = init_finish ? id_read_color_o : 0;

    //to lcd_init
    assign init_write_ok_o = init_finish ? 0 : init_write_ok_i;

    logic delay;
    always_ff @(posedge pclk) begin
        if (~rst_n)
            delay <= 1;
        else if (init_finish)
            delay <= 0;
        else
            delay <= delay;
    end

    //to lcd_id
    assign busy_o = init_finish ? (delay ? 1 : busy_i) : 1;
    assign write_color_ok_o = init_finish ? write_color_ok_i : 0;
endmodule
