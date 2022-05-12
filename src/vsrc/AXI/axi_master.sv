`include "AXI/axi_defines.v"
module axi_Master (
    input wire aclk,
    input wire aresetn, //low is valid
    //inst
    input wire [`ADDR]inst_cpu_addr_i,
    input wire inst_cpu_ce_i,
    input wire [`Data]inst_cpu_data_i,
    input wire inst_cpu_we_i ,
    input wire [3:0]inst_cpu_sel_i, 
    input wire inst_flush_i,
    output reg [`Data]inst_cpu_data_o,
    output wire inst_stallreq,
    input wire [3:0]inst_id,//决定是读数据还是取指令
    input wire [2:0]icache_rd_type_i,//icahce read type

    //data
    input wire [`ADDR]data_cpu_addr_i,
    input wire data_cpu_ce_i,
    input wire [`Data]data_cpu_data_i,
    input wire data_cpu_we_i ,
    input wire [3:0]data_cpu_sel_i, 
    input wire data_flush_i,
    output reg [`Data]data_cpu_data_o,
    output wire data_stallreq,
    input wire [3:0]data_id,//决定是读数据还是取指令
    input wire [2:0]dcache_rd_type_i,// dacache read type
    input wire [2:0]dcache_wr_type_i,//decache write type
    input wire [`BurstData]dcache_wr_data,//data from dcache
    
    //Slave

    //ar
    output wire [`ID]s_arid,  //arbitration
    output wire [`ADDR]s_araddr,
    output wire [`Len]s_arlen,
    output wire [`Size]s_arsize,
    output wire [`Burst]s_arburst,
    output wire [`Lock]s_arlock,
    output wire [`Cache]s_arcache,
    output wire [`Prot]s_arprot,
    output wire s_arvalid,
    input wire s_arready,

    //r
    input wire [`ID]s_rid,
    input wire [`Data]s_rdata,
    input wire [`Resp]s_rresp,
    input wire s_rlast,//the last read data
    input wire s_rvalid,
    output wire s_rready,

    //aw
    output wire [`ID]s_awid,
    output reg [`ADDR]s_awaddr,
    output wire  [`Len]s_awlen,
    output reg [`Size]s_awsize,
    output wire [`Burst]s_awburst,
    output wire [`Lock]s_awlock,
    output wire [`Cache]s_awcache,
    output wire [`Prot]s_awprot,
    output reg s_awvalid,
    input wire s_awready,

    //w
    output wire [`ID]s_wid,
    output reg [`Data]s_wdata,
    output wire [3:0]s_wstrb,//字节选通位和sel差不多
    output reg  s_wlast,
    output reg s_wvalid,
    input wire s_wready,

    //b
    input wire [`ID]s_bid,
    input wire [`Resp]s_bresp,
    input wire s_bvalid,
    output reg s_bready

);  
    reg write_wait_enable;
    //read instruction stall
    reg inst_stall_req_r;
    assign inst_stallreq=inst_stall_req_r;
    reg [31:0]inst_buffer;

    //read and write data stall
    reg stall_req_w;
    reg data_stall_req_r;
    reg [31:0]data_buffer;
    assign data_stallreq=data_stall_req_r||stall_req_w;
    
    reg [3:0]inst_r_state;
    reg [3:0]data_r_state;

    //fetch instruction before fetch data
    reg is_fetching_inst;
    reg is_fetch_inst_OK;

    //read instruction signal to slave
     reg [`ID]inst_s_arid;  //arbitration
     reg [`ADDR]inst_s_araddr;
     reg [`Size]inst_s_arsize;
     reg inst_s_arvalid;
     reg [`Len]inst_s_arlen;
    //r
     reg inst_s_rready;

    //decide arlen by rd_type
    wire [`Len]inst_real_s_arlen;
    assign inst_real_s_arlen=(icache_rd_type_i==3'b100)?8'b11:8'b0;


/**
**read state machine for fetch instruction 
**/
    //改变输出
    always @(*)
    begin
        if(!aresetn)begin
            inst_stall_req_r=0;
            inst_cpu_data_o=0;
            is_fetching_inst=0;
        end 
        else
        begin
            case(inst_r_state)
                `R_FREE:begin
                            if(inst_cpu_ce_i&&inst_cpu_we_i==0)
                            begin
                                inst_stall_req_r=1;
                                inst_cpu_data_o=0;
                                //is_fetching_inst=1;
                                is_fetching_inst=0;
                            end
                            else
                            begin
                                inst_stall_req_r=0;
                                inst_cpu_data_o=0;
                                is_fetching_inst=0;
                            end
                        end
                `R_ADDR:begin
                    inst_stall_req_r=1;
                    inst_cpu_data_o=0;
                    is_fetching_inst=1;
                    end
                `R_DATA:begin
                            if(s_rvalid&&s_rlast)
                            begin
                               inst_stall_req_r=0;
                               inst_cpu_data_o=s_rdata;
                               is_fetching_inst=0;
                            end
                            else
                            begin
                                inst_stall_req_r=1;
                                inst_cpu_data_o=s_rdata;
                                is_fetching_inst=1;
                            end       
                        end
                `STALL:begin
                            inst_stall_req_r=0;
                            inst_cpu_data_o=inst_buffer;
                            is_fetching_inst=0;
                       end
                default:begin
                        end
            endcase
        end
    end

    //read
    //state machine
    always @(posedge aclk)
    begin
        if(!aresetn)
        begin
            inst_r_state<=`R_FREE;
            inst_s_arid<=0;
            inst_s_araddr<=0;
            inst_s_arsize<=0;
            inst_buffer<=0;
            inst_s_arlen<=0;
            inst_s_rready<=0;

            inst_s_arvalid<=0;
        end
        else
        begin
            case(inst_r_state)

                `R_FREE:begin
                    if(write_wait_enable==0)
                    begin
                        if((inst_cpu_ce_i&&(inst_cpu_we_i==0))&&(!(data_cpu_ce_i&&(data_cpu_we_i==0))))//fetch inst but don't fetch data
                        begin
                            inst_r_state<=`R_ADDR;
                            inst_s_arid<=inst_id;
                            inst_s_araddr<=inst_cpu_addr_i;
                            inst_s_arsize<=3'b010;
                            inst_buffer<=0;
                            inst_s_arlen<=inst_real_s_arlen;
                            inst_s_rready<=0;

                            inst_s_arvalid<=1;
                        
                        end
                        else if((inst_cpu_ce_i&&(inst_cpu_we_i==0))&&(data_cpu_ce_i&&(data_cpu_we_i==0)))//fetch inst and fetch data
                        begin
                        //wait for fetch data request run into R_DATA state
                            if(data_r_state==`R_DATA)
                            begin
                                inst_r_state<=`R_ADDR;
                                inst_s_arid<=inst_id;
                                inst_s_araddr<=inst_cpu_addr_i;
                                inst_s_arsize<=3'b010;
                                inst_buffer<=0;
                                inst_s_arlen<=inst_real_s_arlen;
                                inst_s_rready<=0;

                                inst_s_arvalid<=1;
                            end
                            else
                            begin
                                inst_r_state<=`R_FREE;
                                inst_s_arid<=0;
                                inst_s_araddr<=0;
                                inst_s_arsize<=0;
                                inst_buffer<=0;
                                inst_s_arlen<=0;
                                inst_s_rready<=0;

                                inst_s_arvalid<=0;
                            end
                        end
                        else
                        begin
                            inst_r_state<=inst_r_state;
                            inst_s_arid<=0;
                            inst_s_araddr<=0;
                            inst_s_arsize<=0;
                            inst_buffer<=0;
                            inst_s_arlen<=0;
                            inst_s_rready<=0;

                            inst_s_arvalid<=0;
                        end
                    end
                    else
                    begin
                            inst_r_state<=`R_FREE;
                            inst_s_arid<=0;
                            inst_s_araddr<=0;
                            inst_s_arsize<=0;
                            inst_buffer<=0;
                            inst_s_arlen<=0;
                            inst_s_rready<=0;

                            inst_s_arvalid<=0;
                    end
                    
                end

                /** AR **/
                `R_ADDR:begin

                    if(s_arready&&s_arvalid)
                    begin
                                inst_r_state<=`R_DATA;
                                inst_s_arid<=0;
                                inst_s_araddr<=0;
                                inst_s_arsize<=0;
                                inst_buffer<=0;
                                inst_s_arlen<=0;
                                inst_s_rready<=1;
                                inst_s_arvalid<=0;           
                        
                    end
                    else
                    begin
                        inst_r_state<=inst_r_state;
                        inst_s_arid<=inst_s_arid;
                        inst_s_araddr<=inst_s_araddr;
                        inst_s_arsize<=inst_s_arsize;
                        inst_s_arlen<=inst_s_arlen;
                        inst_buffer<=0;
                        inst_s_rready<=inst_s_rready;

                        inst_s_arvalid<=inst_s_arvalid;

                    end

                
                end

                /** R **/
                `R_DATA:begin
                    if(s_rvalid&&s_rlast)
                    begin
                        if(!(data_cpu_ce_i&&(data_cpu_we_i==0)))
                        begin
                            inst_r_state<=`R_FREE;
                            inst_buffer<=s_rdata;
                            inst_s_rready<=0;

                            inst_s_arid<=0;
                            inst_s_araddr<=0;
                            inst_s_arsize<=0;
                            inst_s_arlen<=0;
                        end
                        else
                        begin
                            inst_r_state<=`STALL;
                            inst_buffer<=s_rdata;
                            inst_s_rready<=0;

                            inst_s_arid<=0;
                            inst_s_araddr<=0;
                            inst_s_arsize<=0;
                            inst_s_arlen<=0;
                        end

                    end
                    else
                    begin
                        inst_r_state<=inst_r_state;
                        inst_buffer<=0;
                        inst_s_rready<=inst_s_rready;

                        inst_s_arid<=inst_s_arid;
                        inst_s_araddr<=inst_s_araddr;
                        inst_s_arsize<=inst_s_arsize;
                        inst_s_arlen<=0;
                    end

                    // //set s_rready
                    // if(~s_rready)
                    // begin
                    //     s_rready<=1;
                    // end
                    // else if(s_rready&&s_rvalid)
                    // begin
                    //     s_rready<=0;
                        
                    // end
                    // else
                    // begin
                    //     s_rready<=s_rready;
                    // end
                end

                /**STALL**/
                `STALL:
                begin
                    if(data_stall_req_r==0) inst_r_state<=`R_FREE;
                    else inst_r_state<=inst_r_state;
                end

                default:
                begin
                    
                end

            endcase
        end
    end

    //read data signal to slave
     reg [`ID]data_s_arid;  //arbitration
     reg [`ADDR]data_s_araddr;
     reg [`Size]data_s_arsize;
     reg data_s_arvalid;
     reg [`Len]data_s_arlen;
    //r
     reg data_s_rready;

    //decide arlen by rd_type
    wire [`Len]data_real_s_arlen;
    assign data_real_s_arlen=(dcache_rd_type_i==3'b100)?8'b11:8'b0;
/**
**read state machine for fetch data
**/

    //改变输出
    always @(*)
    begin
        if(!aresetn)begin
            data_stall_req_r=0;
            data_cpu_data_o=0;
        end 
        else
        begin
            case(data_r_state)
                `R_FREE:begin
                            if(data_cpu_ce_i&&data_cpu_we_i==0)
                            begin
                                data_stall_req_r=1;
                                data_cpu_data_o=0;
                            end
                            else
                            begin
                                data_stall_req_r=0;
                                data_cpu_data_o=0;
                            end
                        end
                `R_ADDR:begin
                    data_stall_req_r=1;
                    data_cpu_data_o=0;
                    end
                `R_DATA:begin
                            if(s_rvalid&&s_rlast)
                            begin
                               data_stall_req_r=0;
                               data_cpu_data_o=s_rdata;
                            end
                            else if(s_rvalid&&s_rready)
                            begin
                                data_stall_req_r=1;
                                data_cpu_data_o=s_rdata;
                            end
                            else
                            begin
                                data_stall_req_r=1;
                                data_cpu_data_o=0;
                            end       
                        end
                default:begin
                        end
            endcase
        end
    end

    //read
    //state machine
    always @(posedge aclk)
    begin
        if(!aresetn)
        begin
            data_r_state<=`R_FREE;
            data_s_arid<=0;
            data_s_araddr<=0;
            data_s_arsize<=0;
            data_buffer<=0;
            data_s_arlen<=0;
            data_s_rready<=0;

            data_s_arvalid<=0;
        end
        else
        begin
            case(data_r_state)

                `R_FREE:begin

                    if(data_cpu_ce_i&&(data_cpu_we_i==0)&&(is_fetching_inst==0)&&(write_wait_enable==0))
                    begin
                        data_r_state<=`R_ADDR;
                        data_s_arid<=data_id;
                        data_s_araddr<=data_cpu_addr_i;
                        data_s_arsize<=3'b010;
                        data_buffer<=0;
                        data_s_arlen<=data_real_s_arlen;
                        data_s_rready<=0;

                        data_s_arvalid<=1;
                    end
                    else
                    begin
                        data_r_state<=data_r_state;
                        data_s_arid<=0;
                        data_s_araddr<=0;
                        data_s_arsize<=0;
                        data_buffer<=0;
                        data_s_arlen<=0;
                        data_s_rready<=0;

                        data_s_arvalid<=0;
                    end
                end

                /** AR **/
                `R_ADDR:begin

                    if(s_arready&&s_arvalid)
                    begin
                        data_r_state<=`R_DATA;
                        data_s_arid<=0;
                        data_s_araddr<=0;
                        data_s_arsize<=0;
                        data_buffer<=0;
                        data_s_arlen<=0;
                        data_s_rready<=1;

                        data_s_arvalid<=0;
                    end
                    else
                    begin
                        data_r_state<=data_r_state;
                        data_s_arid<=data_s_arid;
                        data_s_araddr<=data_s_araddr;
                        data_s_arsize<=data_s_arsize;
                        data_buffer<=0;
                        data_s_arlen<=data_s_arlen;
                        data_s_rready<=data_s_rready;

                        data_s_arvalid<=data_s_arvalid;

                    end

                
                end

                /** R **/
                `R_DATA:begin
                    if(s_rvalid&&s_rlast)
                    begin
                        data_r_state<=`R_FREE;
                        data_buffer<=s_rdata;
                        data_s_rready<=0;

                        data_s_arid<=0;
                        data_s_araddr<=0;
                        data_s_arsize<=0;
                        data_s_arlen<=0;
                    end
                    else
                    begin
                        data_r_state<=data_r_state;
                        data_buffer<=0;
                        data_s_rready<=data_s_rready;

                        data_s_arid<=0;
                        data_s_araddr<=0;
                        data_s_arsize<=0;
                        data_s_arlen<=0;
                    end

                end

                default:
                begin
                    
                end

            endcase
        end
    end


    //set default
    //ar
    assign s_arlen=data_s_arlen|inst_s_arlen;
    assign s_arburst=`INCR;
    assign s_arlock=0;
    assign s_arcache=4'b0000;
    assign s_arprot=3'b000;


    //write
    reg [`BurstData]write_buffer;





    //state machine
    reg [3:0]w_state;
    
    //counter 
    reg [31:0]cnt;
    always @(posedge aclk ) begin
        if(!aresetn) cnt<=0;
        else if(w_state==`W_DATA)
        begin
            if(s_wvalid&&s_wready) cnt<=cnt+1;
            else cnt<=cnt;
        end
        else    cnt<=0;
    end

    //改变输出
    always @(*) begin
        if(!aresetn)   
        begin
            stall_req_w=0;
            write_wait_enable=0;
        end
         
        else
        begin
            case(w_state)
                `W_FREE:begin
                    if(data_cpu_ce_i&&(data_cpu_we_i))    
                    begin
                        stall_req_w=1;
                        write_wait_enable=1;
                    end
                    else 
                    begin
                        stall_req_w=0;
                        write_wait_enable=0;
                    end
                end
                `W_ADDR,`W_DATA:
                begin
                    stall_req_w=1;
                    write_wait_enable=1;
                end
                `W_RESP:begin
                            if(s_bvalid&&s_bready)  
                            begin
                                stall_req_w=0;
                                write_wait_enable=0;
                            end
                            else 
                            begin
                                stall_req_w=1;
                                write_wait_enable=1;
                            end
                        end
                default:
                begin
                end
            endcase
        end 
        
    end

    always @(posedge aclk) begin
        if(!aresetn)
        begin
            w_state<=`W_FREE;
            s_awaddr<=0;
            s_awsize<=0;

            s_awvalid<=0;
            s_wdata<=0;
            s_wvalid<=0;
            s_bready<=0;
            write_buffer<=0;
            s_wlast<=0;
        end
        else
        begin
            case(w_state)

                `W_FREE:begin

                    if(data_cpu_ce_i&&(data_cpu_we_i))
                    begin
                        w_state<=`W_ADDR;
                        s_awaddr<=data_cpu_addr_i;
                        s_awsize<=3'b010;

                        s_awvalid<=1;
                        s_wdata<=0;
                        s_wvalid<=0;
                        s_bready<=0;
                        write_buffer<=dcache_wr_data;
                        s_wlast<=0;
                    end
                    else
                    begin
                        w_state<=w_state;
                        s_awaddr<=0;
                        s_awsize<=0;

                        s_awvalid<=0;
                        s_wdata<=0;
                        s_wvalid<=0;
                        s_bready<=0;
                        write_buffer<=0;
                        s_wlast<=0;
                    end
                end
                /** AW **/
                `W_ADDR:begin

                    if(s_awvalid&&s_awready)
                    begin
                        w_state<=`W_DATA;
                        s_awaddr<=0;
                        s_awsize<=0;

                        s_awvalid<=0;
                        s_wvalid<=1;
                        s_bready<=1;
                        // s_wdata<=data_cpu_data_i;
                        s_wdata<=write_buffer[31:0];
                        write_buffer<={{32{1'b0}},write_buffer[127:32]};

                        if(s_awlen==0)  s_wlast<=1;
                        else s_wlast<=0;
                    end
                    else
                    begin
                        w_state<=w_state;
                        s_awaddr<=s_awaddr;
                        s_awsize<=s_awsize;

                        s_awvalid<=s_awvalid;
                        s_wvalid<=s_wvalid;
                        s_bready<=s_bready;
                        s_wdata<=0;
                        write_buffer<=write_buffer;
                        s_wlast<=s_wlast;
                    end
                end
                /** W **/
                `W_DATA:begin
                    
                    if(s_wvalid&&s_wready)
                    begin
                        if(cnt==s_awlen)
                        begin
                            w_state<=`W_RESP;
                            s_wdata<=0;
                            s_wvalid<=0;
                            write_buffer<=0;
                            s_wlast=0;
                        end
                        else
                        begin
                            w_state<=w_state;
                            s_wdata<=write_buffer[31:0];
                            write_buffer<={{32{1'b0}},write_buffer[127:32]};
                            s_wvalid<=1;
                            if(cnt==s_awlen-1)  s_wlast<=1;
                            else s_wlast<=0;
                            
                        end
                        
                    end
                    else
                    begin
                        w_state<=w_state;
                        s_wdata<=s_wdata;
                        s_wvalid<=s_wvalid;
                        s_wlast=s_wlast;
                    end

                end
                /** B **/
                `W_RESP:begin
                    
                    if(s_bvalid&&s_bready)
                    begin
                        w_state<=`W_FREE;
                        s_bready<=0;
                    end
                    else
                    begin
                        w_state<=w_state;
                        s_bready<=s_bready;
                    end
                end

                default:
                begin
                    
                end

            endcase
        end
    end

    //set default
    //aw
    assign s_awid=1;
    assign s_awlen=(dcache_wr_type_i==3'b100)?8'b11:8'b0;
    assign s_awburst=`INCR;
    assign s_awlock=0;
    assign s_awcache=0;
    assign s_awprot=0;
    assign s_wid=0;
    assign s_wstrb=data_cpu_sel_i;
    // assign s_wlast=1;

    
    //set axi signal
    assign s_arid=inst_s_arid|data_s_arid;
    assign s_araddr=inst_s_araddr|data_s_araddr;
    assign s_arsize=inst_s_arsize|data_s_arsize;
    assign s_arvalid=inst_s_arvalid|data_s_arvalid;
    assign s_rready=inst_s_rready|data_s_rready;
endmodule