`include "../axi_defines.v"
module axi_Master (
    input wire aclk,
    input wire aresetn, //low is valid
    
    //CPU
    input wire [`ADDR]cpu_addr_i,
    input wire cpu_ce_i,
    input wire [`Data]cpu_data_i,
    input wire cpu_we_i ,
    input wire [3:0]cpu_sel_i, 
    input wire stall_i,
    input wire flush_i,
    output reg [`Data]cpu_data_o,
    output wire stallreq,
    input wire [3:0]id,//决定是读数据还是取指令
    
    //Master

    //ar 
    
    //r 

    //aw

    //w

    //b

    //Slave

    //ar
    output reg [`ID]s_arid,  //arbitration
    output reg [`ADDR]s_araddr,
    output wire [`Len]s_arlen,
    output reg [`Size]s_arsize,
    output wire [`Burst]s_arburst,
    output wire [`Lock]s_arlock,
    output wire [`Cache]s_arcache,
    output wire [`Prot]s_arprot,
    output reg s_arvalid,
    input wire s_arready,

    //r
    input wire [`ID]s_rid,
    input wire [`Data]s_rdata,
    input wire [`Resp]s_rresp,
    input wire s_rlast,//the last read data
    input wire s_rvalid,
    output reg s_rready,

    //aw
    output wire [`ID]s_awid,
    output reg [`ADDR]s_awaddr,
    output wire [`Len]s_awlen,
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
    output wire  s_wlast,
    output reg s_wvalid,
    input wire s_wready,

    //b
    input wire [`ID]s_bid,
    input wire [`Resp]s_bresp,
    input wire s_bvalid,
    output reg s_bready

);  

    //three stage state machine
    reg [3:0]r_current_state;
    reg [3:0]r_next_state;
    
    //stall request
    //Harvard structure need stall request
    reg stall_req_r;
    reg stall_req_w;

    assign stallreq=stall_req_r&stall_req_w;
    
    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn)begin
            stall_req_r<=0;
        end
        else
        begin
            case(r_next_state)
                `R_FREE:stall_req_r<=0;
                `R_ADDR:stall_req_r<=1;
                `R_DATA:stall_req_r<=1;
                `STALL:stall_req_r<=0;
                default:
                begin
                end
            endcase
        end
    end
    //read
    //state machine

    //状态转移 
    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn)begin
            r_current_state<=`R_FREE;
        end
        else
        begin
            r_current_state<=r_next_state;
        end
    end

    //状态更新
    always @(*) begin
        case (r_current_state)

            `R_FREE:begin
                if(cpu_ce_i&&(cpu_we_i==0))
                    begin
                        r_next_state=`R_ADDR;
                    end
                    else
                    begin
                        r_next_state=`R_FREE;
                    end
            end
            //AR
            `R_ADDR:begin
                if(s_arready&&s_arvalid)
                    begin
                        r_next_state<=`R_DATA;
                    end
                    else
                    begin
                        r_next_state<=r_next_state;
                    end
            end
            //R
            `R_DATA:begin
                if(s_rvalid&&s_rlast&&stall_i==0)
                    begin
                        r_next_state<=`R_FREE;
                    end
                    else if(s_rvalid&&s_rlast&&stall_i==1)
                    begin
                        r_next_state<=`STALL;
                    end
                    else
                    begin
                        r_next_state<=r_next_state;
                    end
            end

            //STALL
            `STALL:begin
                if(stall_i==0)begin
                    r_next_state=`R_FREE;
                end
                else
                begin
                    r_next_state<=r_next_state;
                end
            end
            default: begin
                
            end
        endcase
    end

    //输出的更新
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_arid<=0;
            s_araddr<=0;
            s_arsize<=0;
            cpu_data_o<=0;

        end
        else
        begin
            case(r_next_state)
                `R_FREE:begin
                    //R
                    if(r_current_state==`R_DATA)begin
                        s_arid<=0;
                        s_araddr<=0;
                        s_arsize<=0;
                        cpu_data_o<=s_rdata;
                    end
                    else if(r_current_state==`STALL)begin
                        s_arid<=0;
                        s_araddr<=0;
                        s_arsize<=0;
                        cpu_data_o<=cpu_data_o;
                    end
                    else
                    begin
                        s_arid<=0;
                        s_araddr<=0;
                        s_arsize<=0;
                        cpu_data_o<=0;
                    end
                end
                //AR
                `R_ADDR:begin
                    if(r_current_state==`R_FREE)begin
                        s_arid<=0;
                        s_araddr<=0;
                        s_arsize<=0;
                        cpu_data_o<=0;
                    end
                    else
                    begin
                        s_arid<=s_arid;
                        s_araddr<=s_araddr;
                        s_arsize<=s_arsize;
                        cpu_data_o<=cpu_data_o;
                    end
                end
                //R
                `R_DATA:begin
                    
                    if(r_current_state==`R_ADDR)begin
                        s_arid<=id;
                        s_araddr<=cpu_addr_i;
                        s_arsize<=3'b010;
                        cpu_data_o<=0;
                    end
                    else
                    begin
                        s_arid<=s_arid;
                        s_araddr<=s_araddr;
                        s_arsize<=s_arsize;
                        cpu_data_o<=cpu_data_o;
                    end
                end

                `STALL:
                begin
                        if(r_current_state==`R_DATA)
                        begin
                            s_arid<=0;
                            s_araddr<=0;
                            s_arsize<=0;
                            cpu_data_o<=s_rdata;
                        end
                        else
                        begin
                            s_arid<=s_arid;
                            s_araddr<=s_araddr;
                            s_arsize<=s_arsize;
                            cpu_data_o<=cpu_data_o;
                        end     
                end
                default:
                begin
                end
            endcase
        end
    end

    //hand shake Signal

    //s_arvalid
    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn)
        begin
            s_arvalid<=0;
        end
        else
        begin
            case(r_next_state)
                `R_FREE:s_arvalid<=0;
                //AR
                `R_ADDR:begin
                    if(r_current_state==`R_FREE)begin
                        s_arvalid<=1;
                    end
                    else
                    begin
                        s_arvalid<=s_arvalid;
                    end
                end
                //R
                `R_DATA:s_arvalid<=0;
                `STALL:s_arvalid<=0;
                default:
                begin
                    
                end
            endcase
        end 
    end

    //s_rready
    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn)
        begin
            s_rready<=0;
        end
        else
        begin
            case(r_next_state)
                `R_FREE:s_rready<=0;
                //AR
                `R_ADDR:s_rready<=0;
                //R
                `R_DATA:begin
                    if(r_current_state==`R_ADDR)
                    begin
                        s_rready<=0;
                    end
                    else
                    begin
                        if(~s_rready)
                        begin
                            s_rready<=1;
                        end
                        else if(s_rready&&s_rvalid)
                        begin
                            s_rready<=0;
                        end
                        else
                        begin
                            s_rready<=s_rready;
                        end
                    end
                end
                `STALL:
                begin
                    s_rready<=0;
                end
                default:
                begin
                    
                end
            endcase
        end 
    end



    //set default
    //ar
    assign s_arlen=0;
    assign s_arburst=`INCR;
    assign s_arlock=0;
    assign s_arcache=4'b0000;
    assign s_arprot=3'b000;


    //write
    //state machine
    reg [3:0]w_current_state;
    reg [3:0]w_next_state;

        always @(posedge aclk or negedge aresetn) begin
        if(!aresetn)begin
            stall_req_w<=0;
        end
        else
        begin
            case(w_next_state)
                `W_FREE:stall_req_w<=0;
                `W_ADDR:stall_req_w<=1;
                `W_DATA:stall_req_w<=1;
                `W_RESP:stall_req_w<=1;
                `STALL:stall_req_w<=0;
                default:
                begin
                    
                end
            endcase
        end
    end
    //状态转移
    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn)
        begin
            w_current_state<=0;
        end
        else
        begin
            w_current_state<=w_next_state;
        end
        
    end

    //状态更新
always @(*) begin
    case (w_current_state)
        `W_FREE:begin
            //AW
            if(cpu_ce_i&&(cpu_we_i))
                    begin
                        w_next_state<=`W_ADDR;
                    end
                    else
                    begin
                        w_next_state<=`W_FREE;
                    end
        end 
        //AW
        `W_ADDR:begin
                    if(s_awvalid&&s_awready)
                    begin
                        w_next_state<=`W_DATA;
                    end
                    else
                    begin
                        w_next_state<=w_next_state;
                    end
        end

        //W
        `W_DATA:begin
                    if(s_wvalid&&s_wready)
                    begin
                        w_next_state<=`W_RESP;
                    end
                    else
                    begin
                        w_next_state<=w_next_state;
                    end
        end

        //B
        `W_RESP:begin
                    if(s_bvalid&&s_bready&&stall_i==0)
                    begin
                        w_next_state<=`W_FREE;
                    end
                    else if(s_bvalid&&s_bready&&stall_i==1)
                    begin
                        w_next_state<=`STALL;
                    end
                    else
                    begin
                        w_next_state<=w_next_state;
                    end
        end

        //STALL
        `STALL:
        begin
            if(stall_i==0)  w_next_state<=`W_FREE;
            else    w_next_state<=w_next_state;
        end
        default:
        begin
            
        end
    endcase
end

    //输出更新
    always @(negedge aclk or negedge aresetn) begin
        if(!aresetn)begin
            s_awaddr<=0;
            s_awsize<=0;
            s_wdata<=0;
        end
        else
        begin
            case (w_next_state)
                `W_FREE:begin
                    //B
                        s_awaddr<=0;
                        s_awsize<=0;
                        s_wdata<=0;
                end

                //AW
                `W_ADDR:begin
                    if(w_current_state==`W_FREE)
                    begin
                        s_awaddr<=0;
                        s_awsize<=0;
                        s_wdata<=0;
                    end
                    else
                    begin
                        s_awaddr<=s_awaddr;
                        s_awsize<=s_awsize;
                        s_wdata<=s_wdata;
                    end
                end
                
                //W
                `W_DATA:begin
                    if(w_current_state==`W_ADDR)begin
                        s_wdata<=0;
                        s_awaddr<=cpu_addr_i;
                        s_awsize<=3'b010;
                    end
                    else
                    begin
                        s_awaddr<=s_awaddr;
                        s_awsize<=s_awsize;
                        s_wdata<=s_wdata;
                    end
                end
                
                //B
                `W_RESP:begin
                    if(w_current_state==`W_DATA)begin
                        s_awaddr<=s_awaddr;
                        s_awsize=s_awsize;
                        s_wdata<=cpu_data_i;
                    end
                    else
                    begin
                        s_awaddr<=s_awaddr;
                        s_awsize=s_awsize;
                        s_wdata<=s_wdata;
                    end
                end

                //STALL
                `STALL:begin
                    if(w_current_state==`W_RESP)
                    begin
                        s_awaddr<=0;
                        s_awsize<=0;
                        s_wdata<=0;
                    end
                    else
                    begin
                        s_awaddr<=0;
                        s_awsize<=0;
                        s_wdata<=0;
                    end
                end

                default: begin
                    
                end
            endcase
        end
    end

    //hand shake Signal

    //s_awvalid
    always @(posedge aclk or negedge aresetn ) begin
        if(!aresetn)begin
            s_awvalid<=0;
        end
        else
        begin
            case(w_next_state)
                `W_FREE:s_awvalid<=0;
                `W_ADDR:s_awvalid<=1;
                `W_DATA:s_awvalid<=0;
                `W_RESP:s_awvalid<=0;
                `STALL:s_awvalid<=0;
            endcase
        end
    end

    //s_wvalid
    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn)
        begin
            s_wvalid<=0;
        end
        else
        begin
            case(w_next_state)
                `R_FREE:s_wvalid<=0;
                `R_ADDR:s_wvalid<=0;
                `R_DATA:begin
                    if(w_current_state==`R_ADDR)
                    begin
                        s_wvalid<=1;
                    end
                    else
                    begin
                        if(~s_wvalid)begin
                            s_wvalid<=1;
                        end
                        else if(s_wvalid&&s_wready)begin
                            s_wvalid<=0;
                        end
                        else
                        begin
                            s_wvalid<=s_wvalid;
                        end
                    end
                end
                `W_RESP:s_wvalid<=0;
                `STALL:s_wvalid<=0;
            endcase
        end
        
    end

    //s_bready
    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn)begin
            s_bready<=0;
        end
        else
        begin
            case(w_next_state)
                `W_FREE:s_bready<=0;
                `W_ADDR:s_bready<=0;
                `W_DATA:s_bready<=1;
                `W_RESP:s_bready<=s_bready;
                `STALL:s_bready<=0;
            endcase
        end 
        
    end

    //set default
    //aw
    assign s_awid=1;
    assign s_awlen=0;
    assign s_awburst=`INCR;
    assign s_awlock=0;
    assign s_awcache=0;
    assign s_awprot=0;
    assign s_wid=0;
    assign s_wstrb={4{cpu_we_i}}&cpu_sel_i;
    assign s_wlast=1;

    
endmodule