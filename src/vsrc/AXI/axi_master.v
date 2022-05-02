`include "AXI/axi_defines.v"
module axi_master (
    input wire aclk,
    input wire aresetn, //low is valid

    //CPU
    input wire [`ADDR] cpu_addr_i,
    input wire cpu_ce_i,
    input wire [`Data] cpu_data_i,
    input wire cpu_we_i,
    input wire [3:0] cpu_sel_i,
    input wire stall_i,
    input wire flush_i,
    output reg [`Data] cpu_data_o,
    output wire stallreq,
    input wire [3:0] id,  //决定是读数据还是取指令

    //Master

    //ar 

    //r 

    //aw

    //w

    //b

    //Slave

    //ar
    output reg [`ID] s_arid,  //arbitration
    output reg [`ADDR] s_araddr,
    output wire [`Len] s_arlen,
    output reg [`Size] s_arsize,
    output wire [`Burst] s_arburst,
    output wire [`Lock] s_arlock,
    output wire [`Cache] s_arcache,
    output wire [`Prot] s_arprot,
    output reg s_arvalid,
    input wire s_arready,

    //r
    input wire [`ID] s_rid,
    input wire [`Data] s_rdata,
    input wire [`Resp] s_rresp,
    input wire s_rlast,  //the last read data
    input wire s_rvalid,
    output reg s_rready,

    //aw
    output wire [`ID] s_awid,
    output reg [`ADDR] s_awaddr,
    output wire [`Len] s_awlen,
    output reg [`Size] s_awsize,
    output wire [`Burst] s_awburst,
    output wire [`Lock] s_awlock,
    output wire [`Cache] s_awcache,
    output wire [`Prot] s_awprot,
    output reg s_awvalid,
    input wire s_awready,

    //w
    output wire [`ID] s_wid,
    output reg [`Data] s_wdata,
    output wire [3:0] s_wstrb,  //字节选通位和sel差不多
    output wire s_wlast,
    output reg s_wvalid,
    input wire s_wready,

    //b
    input wire [`ID] s_bid,
    input wire [`Resp] s_bresp,
    input wire s_bvalid,
    output reg s_bready

);
    reg stall_req_r;
    reg stall_req_w;

    assign stallreq = stall_req_r || stall_req_w;
    reg [31:0] data_buffer;



    reg [ 3:0] r_state;

    //改变输出
    always @(*) begin
        if (!aresetn) begin
            stall_req_r = 0;
            cpu_data_o  = 0;
        end else begin
            case (r_state)
                `R_FREE: begin
                    if (cpu_ce_i && cpu_we_i == 0) begin
                        stall_req_r = 1;
                        cpu_data_o  = 0;
                    end else begin
                        stall_req_r = 0;
                        cpu_data_o  = 0;
                    end
                end
                `R_ADDR: begin
                    stall_req_r = 1;
                    cpu_data_o  = 0;
                end
                `R_DATA: begin
                    if (s_rvalid && s_rlast) begin
                        stall_req_r = 0;
                        cpu_data_o  = s_rdata;
                    end else begin
                        stall_req_r = 1;
                        cpu_data_o  = 0;
                    end
                end
                default: begin
                end
            endcase
        end
    end

    //read
    //state machine
    always @(posedge aclk) begin
        if (!aresetn) begin
            r_state <= `R_FREE;
            s_arid <= 0;
            s_araddr <= 0;
            s_arsize <= 0;
            data_buffer <= 0;
            s_rready <= 0;

            s_arvalid <= 0;
        end else begin
            case (r_state)

                `R_FREE: begin

                    if (cpu_ce_i && (cpu_we_i == 0)) begin
                        r_state <= `R_ADDR;
                        s_arid <= 0;
                        s_araddr <= cpu_addr_i;
                        s_arsize <= 0;
                        data_buffer <= 0;
                        s_rready <= 0;

                        s_arvalid <= 1;


                    end else begin
                        r_state <= r_state;
                        s_arid <= 0;
                        s_araddr <= 0;
                        s_arsize <= 0;
                        data_buffer <= 0;
                        s_rready <= 0;

                        s_arvalid <= 0;
                    end
                end

                /** AR **/
                `R_ADDR: begin

                    if (s_arready && s_arvalid) begin
                        r_state <= `R_DATA;
                        s_arid <= id;
                        s_araddr <= cpu_addr_i;
                        s_arsize <= 3'b010;
                        data_buffer <= 0;
                        s_rready <= 1;

                        s_arvalid <= 0;
                    end else begin
                        r_state <= r_state;
                        s_arid <= s_arid;
                        s_araddr <= s_araddr;
                        s_arsize <= s_arsize;
                        data_buffer <= 0;
                        s_rready <= s_rready;

                        s_arvalid <= s_arvalid;

                    end


                end

                /** R **/
                `R_DATA: begin
                    // if(!aresetn)
                    // begin

                    // end
                    if (s_rvalid && s_rlast) begin
                        r_state <= `R_FREE;
                        data_buffer <= s_rdata;
                        s_rready <= 0;
                    end else begin
                        r_state <= r_state;
                        data_buffer <= 0;
                        s_rready <= s_rready;
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

                default: begin

                end

            endcase
        end
    end

    //set default
    //ar
    assign s_arlen   = 0;
    assign s_arburst = `INCR;
    assign s_arlock  = 0;
    assign s_arcache = 4'b0000;
    assign s_arprot  = 3'b000;


    //write
    //state machine
    reg [3:0] w_state;
    //改变输出
    always @(*) begin
        if (!aresetn) stall_req_w = 0;
        else begin
            case (w_state)
                `W_FREE: begin
                    if (cpu_ce_i && (cpu_we_i)) stall_req_w = 1;
                    else stall_req_w = 0;
                end
                `W_ADDR, `W_DATA: stall_req_w = 1;
                `W_RESP: begin
                    if (s_bvalid && s_bready) stall_req_w = 0;
                    else stall_req_w = 1;
                end
                default: begin
                    stall_req_w = 0;
                end
            endcase
        end

    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            w_state   <= `W_FREE;
            s_awaddr  <= 0;
            s_awsize  <= 0;

            s_awvalid <= 0;
            s_wdata   <= 0;
            s_wvalid  <= 0;
            s_bready  <= 0;
        end else begin
            case (w_state)

                `W_FREE: begin

                    if (cpu_ce_i && (cpu_we_i)) begin
                        w_state   <= `W_ADDR;
                        s_awaddr  <= 0;
                        s_awsize  <= 0;

                        s_awvalid <= 1;
                        s_wdata   <= 0;
                        s_wvalid  <= 0;
                        s_bready  <= 0;
                    end else begin
                        w_state   <= w_state;
                        s_awaddr  <= 0;
                        s_awsize  <= 0;

                        s_awvalid <= 0;
                        s_wdata   <= 0;
                        s_wvalid  <= 0;
                        s_bready  <= 0;
                    end
                end
                /** AW **/
                `W_ADDR: begin

                    if (s_awvalid && s_awready) begin
                        w_state   <= `W_DATA;
                        s_awaddr  <= cpu_addr_i;
                        s_awsize  <= 3'b010;

                        s_awvalid <= 0;
                        s_wvalid  <= 1;
                        s_bready  <= 1;
                    end else begin
                        w_state   <= w_state;
                        s_awaddr  <= s_awaddr;
                        s_awsize  <= s_awsize;

                        s_awvalid <= s_awvalid;
                        s_wvalid  <= s_wvalid;
                        s_bready  <= s_bready;
                    end
                end
                /** W **/
                `W_DATA: begin

                    if (s_wvalid && s_wready) begin
                        w_state <= `W_RESP;
                        s_wdata <= cpu_data_i;
                    end else begin
                        w_state <= w_state;
                        s_wdata <= s_wdata;
                    end

                    //set wvalid
                    if (s_wvalid && s_wready) begin
                        s_wvalid <= 0;
                    end else if (~s_wvalid) begin
                        s_wvalid <= 1;
                    end else begin
                        s_wvalid <= s_wvalid;
                    end

                end
                /** B **/
                `W_RESP: begin

                    if (s_bvalid && s_bready) begin
                        w_state  <= `W_FREE;
                        s_bready <= 0;
                    end else begin
                        w_state  <= w_state;
                        s_bready <= s_bready;
                    end
                end

                default: begin

                end

            endcase
        end
    end

    //set default
    //aw
    assign s_awid = 1;
    assign s_awlen = 0;
    assign s_awburst = `INCR;
    assign s_awlock = 0;
    assign s_awcache = 0;
    assign s_awprot = 0;
    assign s_wid = 0;
    assign s_wstrb = {4{cpu_we_i}} & cpu_sel_i;
    assign s_wlast = 1;


endmodule
