`ifndef LCD_TYPES_SV
`define LCD_TYPES_SV 

package lcd_types;
    typedef struct packed {
        //from lcd_id
        logic id_we;  //write enable
        logic id_wr;  //0:read lcd 1:write lcd,distinguish inst kind
        logic id_lcd_rs;
        logic [15:0] id_data;
        logic id_fm;
        logic id_read_color;
        //to lcd_id
        logic busy;
        logic write_color_ok;  //write one color
    } id_mux_struct;

    typedef struct packed {
        //from lcd_init
        logic [15:0] init_data;
        logic init_we;
        logic init_wr;
        logic init_rs;
        logic init_work;
        logic init_finish;
        //to lcd_init
        logic init_write_ok;
    } init_mux_struct;

    typedef struct packed {
        //from lcd_interface
        logic init_write_ok;
        logic busy;
        logic write_color_ok;  //write one color
        //to lcd_interface 
        logic [15:0] data;
        logic we;
        logic wr;
        logic lcd_rs;  //distinguish inst or data
        logic id_fm;  //distinguish read id or read fm,0:id,1:fm
        logic read_color;  //if read color ,reading time is at least 2

    } interface_mux_struct;

endpackage
`endif
