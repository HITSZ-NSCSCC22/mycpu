`include "core_config.sv"
`include "defines.sv"
`include "utils/lfsr.sv"
`include "utils/byte_bram.sv"
`include "utils/dual_port_lutram.sv"
`include "Cache/dcache_fifo.sv"
`include "axi/axi_dcache_master.sv"
`include "axi/axi_interface.sv"

module dcache
    import core_config::*;
(
    input logic clk,
    input logic rst,

    //cache与CPU流水线的交互接
    input logic valid,  //表明请求有效
    input logic [`RegBus] addr,
    input logic [3:0] wstrb,  //写字节使能信号
    input logic [31:0] wdata,  //写数据

    //CACOP
    input logic cacop_i,
    input logic [1:0] cacop_mode_i,
    input logic [ADDR_WIDTH-1:0] cacop_addr_i,
    output cacop_ack_o,

    output logic data_ok,             //该次请求的数据传输Ok，读：数据返回；写：数据写入完成
    output logic [31:0] rdata,  //读Cache的结果

    axi_interface.master m_axi
);

    localparam NWAY = DCACHE_NWAY;
    localparam NSET = DCACHE_NSET;

    enum int {
        IDLE,

        LOOK_UP,
        READ_REQ,
        READ_WAIT,
        WRITE_REQ,
        WRITE_WAIT,

        CACOP_INVALID
    }
        state, next_state;

    // save the input signal
    logic valid_buffer;
    logic [7:0] index_buffer;
    logic [19:0] tag_buffer;
    logic [3:0] offset_buffer;
    logic [3:0] wstrb_buffer;
    logic [31:0] wdata_buffer;
    logic [2:0] req_type_buffer;

    logic cacop_buffer;
    logic [1:0] cacop_mode_buffer;
    logic [ADDR_WIDTH-1:0] cacop_addr_buffer;

    logic cpu_wreq;
    logic [15:0] random_r;

    // AXI
    logic [ADDR_WIDTH-1:0] axi_addr_o;
    logic axi_req_o;
    logic axi_we_o;
    logic axi_rdy_i;
    logic axi_rvalid_i;
    logic axi_bvalid_i;
    logic [AXI_DATA_WIDTH-1:0] axi_data_i;
    logic [AXI_DATA_WIDTH-1:0] axi_wdata_o;
    logic [(AXI_DATA_WIDTH/8)-1:0] axi_wstrb_o;

    // BRAM signals
    logic [NWAY-1:0][DCACHELINE_WIDTH-1:0] data_bram_rdata;
    logic [NWAY-1:0][ICACHELINE_WIDTH-1:0] data_bram_wdata;
    logic [NWAY-1:0][$clog2(NSET)-1:0] data_bram_addr;
    logic [NWAY-1:0][15:0] data_bram_we;
    logic [NWAY-1:0] data_bram_en;

    // Tag bram 
    // {1bit dirty,1bit valid, 20bits tag}
    localparam TAG_BRAM_WIDTH = 22;
    logic [NWAY-1:0][TAG_BRAM_WIDTH-1:0] tag_bram_rdata;
    logic [NWAY-1:0][TAG_BRAM_WIDTH-1:0] tag_bram_wdata;
    logic [NWAY-1:0][$clog2(NSET)-1:0] tag_bram_addr;
    logic [NWAY-1:0] tag_bram_we;
    logic [NWAY-1:0] tag_bram_en;

    logic [`RegBus] cpu_addr;
    logic miss_pulse, miss_r, miss;
    logic hit;
    logic [NWAY-1:0] tag_hit;

    assign cpu_addr = {tag_buffer, index_buffer, offset_buffer};


    logic [1:0] fifo_state;
    logic fifo_rreq, fifo_wreq, fifo_r_hit, fifo_w_hit, fifo_axi_wr_req, fifo_w_accept;
    logic [`DataAddrBus] fifo_raddr, fifo_waddr, fifo_axi_wr_addr;
    logic [DCACHELINE_WIDTH-1:0] fifo_rdata, fifo_wdata, fifo_axi_wr_data;

    // CACOP
    logic cacop_op_mode0, cacop_op_mode1, cacop_op_mode2, cacop_op_mode2_hit;
    logic [$clog2(NWAY)-1:0] cacop_way;
    logic [$clog2(NSET)-1:0] cacop_index;
    assign cacop_op_mode0 = cacop_i & cacop_mode_i == 2'b00;
    assign cacop_op_mode1 = cacop_i & cacop_mode_i == 2'b01;
    assign cacop_op_mode2 = cacop_i & cacop_mode_i == 2'b10;
    assign cacop_way = cacop_addr_i[$clog2(NWAY)-1:0];
    assign cacop_index = cacop_addr_i[$clog2(
        DCACHELINE_WIDTH
    )+$clog2(
        NSET
    )-1:$clog2(
        DCACHELINE_WIDTH
    )];

    logic [1:0] dirty;
    assign dirty = {tag_bram_rdata[1][21], tag_bram_rdata[0][21]};

    //judge if the cacop mode2 hit
    always_comb begin
        cacop_op_mode2_hit = 0;
        if (cacop_op_mode2) begin
            if(tag_bram_rdata[cacop_way][19:0] == cacop_addr_buffer[31:12] 
                && tag_bram_rdata[cacop_way][20] == 1'b1)
                cacop_op_mode2_hit = 1;
        end else cacop_op_mode2_hit = 0;
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end


    always_ff @(posedge clk) begin : data_buffer
        if (rst) begin
            valid_buffer <= 0;
            index_buffer <= 0;
            tag_buffer <= 0;
            offset_buffer <= 0;
            wstrb_buffer <= 0;
            wdata_buffer <= 0;
            cacop_buffer <= 0;
            cacop_mode_buffer <= 0;
            cacop_addr_buffer <= 0;
        end else if (valid) begin  // not accept new request while working
            valid_buffer <= valid;
            index_buffer <= addr[11:4];
            tag_buffer <= addr[31:12];
            offset_buffer <= addr[3:0];
            wstrb_buffer <= wstrb;
            wdata_buffer <= wdata;
            cacop_buffer <= cacop_i;
            cacop_mode_buffer <= cacop_mode_i;
            cacop_addr_buffer <= cacop_addr_i;
        end else if (next_state == IDLE) begin  //means that cache will finish work,so flush the buffered signal
            valid_buffer      <= 0;
            index_buffer      <= 0;
            tag_buffer        <= 0;
            offset_buffer     <= 0;
            wstrb_buffer      <= 0;
            wdata_buffer      <= 0;
            cacop_buffer      <= 0;
            cacop_mode_buffer <= 0;
            cacop_addr_buffer <= 0;
        end else begin
            valid_buffer <= valid_buffer;
            index_buffer <= index_buffer;
            tag_buffer <= tag_buffer;
            offset_buffer <= offset_buffer;
            wstrb_buffer <= wstrb_buffer;
            wdata_buffer <= wdata_buffer;
            cacop_buffer <= cacop_buffer;
            cacop_mode_buffer <= cacop_mode_buffer;
            cacop_addr_buffer <= cacop_addr_buffer;
        end
    end

    //  the wstrb is not 0 means it is a write request;
    assign cpu_wreq = wstrb_buffer != 4'b0;

    always_comb begin : transition_comb
        case (state)
            IDLE: begin
                if (cacop_i) next_state = CACOP_INVALID;
                // if the dcache is idle,then accept the new request
                else if (valid) begin
                    next_state = LOOK_UP;
                end
            end
            LOOK_UP: begin
                if (valid) begin
                    // if write hit,then turn to write idle
                    // if write miss,then wait for read
                    if (cpu_wreq) begin
                        // if hit the dirty cacheline but the fifo is full
                        // then wait until then fifo is not full
                        if (hit & (tag_hit & dirty) != 2'b0 & fifo_state[0]) next_state = LOOK_UP;
                        if (miss) next_state = WRITE_REQ;
                        else next_state = IDLE;
                    end  // if hit,then back,if miss then wait for read
                    else begin
                        if (miss) next_state = READ_REQ;
                        else next_state = IDLE;
                    end
                end else next_state = IDLE;
            end
            READ_REQ: begin
                if (axi_rdy_i) next_state = READ_WAIT;  // If AXI ready, send request 
                else next_state = READ_REQ;
            end
            READ_WAIT: begin
                // If return valid, back to IDLE
                if (axi_rvalid_i) next_state = IDLE;
                else next_state = READ_WAIT;
            end
            WRITE_REQ: begin
                // If AXI is ready and write missthen write req is accept this cycle,and wait until rdata ret
                // If flushed, back to IDLE
                // if AXi is not ready,then wait until it ready and sent the read req
                if (axi_rdy_i) next_state = WRITE_WAIT;
                else next_state = WRITE_REQ;
            end
            WRITE_WAIT: begin
                // wait the rdata back
                if (axi_rvalid_i) next_state = IDLE;
                else next_state = WRITE_WAIT;
            end
            CACOP_INVALID: next_state = IDLE;
            default: begin
                next_state = IDLE;
            end
        endcase
    end


    always_comb begin
        // Default all 0
        for (integer i = 0; i < NWAY; i++) begin
            tag_bram_addr[i] = 0;
            data_bram_addr[i] = 0;
            tag_bram_addr[i] = 0;
            data_bram_addr[i] = 0;
            tag_bram_en[i] = 0;
            data_bram_en[i] = 0;
        end
        case (state)
            IDLE: begin
                for (integer i = 0; i < NWAY; i++) begin
                    // Port 1
                    if (valid) begin
                        tag_bram_en[i] = 1;
                        data_bram_en[i] = 1;
                        tag_bram_addr[i] = addr[11:4];
                        data_bram_addr[i] = addr[11:4];
                        fifo_rreq = 1;
                        fifo_raddr = addr;
                    end
                end
            end
            LOOK_UP: begin
                for (integer i = 0; i < NWAY; i++) begin
                    if (valid_buffer) begin
                        tag_bram_en[i] = 1;
                        data_bram_en[i] = 1;
                        tag_bram_addr[i] = index_buffer;
                        data_bram_addr[i] = index_buffer;
                        fifo_rreq = 1;
                        fifo_raddr = {tag_buffer, index_buffer, offset_buffer};
                    end
                end
            end
            READ_REQ, READ_WAIT: begin
                for (integer i = 0; i < NWAY; i++) begin
                    tag_bram_en[i] = 1;
                    data_bram_en[i] = 1;
                    tag_bram_addr[i] = index_buffer;
                    data_bram_addr[i] = index_buffer;
                end
            end
            WRITE_REQ, WRITE_WAIT: begin
                for (integer i = 0; i < NWAY; i++) begin
                    //if hit ,write the data to the line
                    tag_bram_en[i] = 1;
                    data_bram_en[i] = 1;
                    tag_bram_addr[i] = index_buffer;
                    data_bram_addr[i] = index_buffer;
                end
            end
            CACOP_INVALID: begin
                for (integer i = 0; i < NWAY; i++) begin
                    tag_bram_en[i]  = 0;
                    tag_bram_en[i]  = 0;
                    data_bram_en[i] = 0;
                    data_bram_en[i] = 0;
                    if (cacop_way == i[0]) begin
                        tag_bram_addr[i] = cacop_index;
                        tag_bram_en[i]   = 1;
                    end
                end
            end
        endcase
    end

    always_comb begin : bram_data_gen
        for (integer i = 0; i < NWAY; i++) begin
            tag_bram_we[i] = 0;
            tag_bram_wdata[i] = 0;
            data_bram_we[i] = 0;
            data_bram_wdata[i] = 0;
        end
        case (state)
            LOOK_UP: begin
                // if write hit,then replace the cacheline
                for (integer i = 0; i < NWAY; i++) begin
                    // if write hit ,then write the hit line, if miss then don't write
                    if (tag_hit[i] && cpu_wreq) begin
                        tag_bram_we[i] = 1;
                        // make the dirty bit 1'b1
                        tag_bram_wdata[i] = {1'b1, 1'b1, tag_buffer};
                        //select the write bit
                        case (wstrb_buffer)
                            //st.b 
                            4'b0001, 4'b0010, 4'b0100, 4'b1000: begin
                                data_bram_we[i][offset_buffer] = 1'b1;
                                data_bram_wdata[i] = {4{wdata_buffer}};
                            end
                            //st.h
                            4'b0011, 4'b1100: begin
                                data_bram_we[i][offset_buffer+1] = 1'b1;
                                data_bram_we[i][offset_buffer] = 1'b1;
                                data_bram_wdata[i] = {4{wdata_buffer}};
                            end
                            //st.w
                            4'b1111: begin
                                data_bram_we[i][offset_buffer+3] = 1'b1;
                                data_bram_we[i][offset_buffer+2] = 1'b1;
                                data_bram_we[i][offset_buffer+1] = 1'b1;
                                data_bram_we[i][offset_buffer] = 1'b1;
                                data_bram_wdata[i] = {4{wdata_buffer}};
                            end
                            default: begin

                            end
                        endcase
                    end
                end
            end
            READ_WAIT: begin
                for (integer i = 0; i < NWAY; i++) begin
                    // select a line to write back 
                    if (i[0] == random_r[0]) begin
                        if (axi_rvalid_i) begin
                            tag_bram_we[i] = 1;
                            //make the dirty bit 1'b0
                            tag_bram_wdata[i] = {1'b0, 1'b1, tag_buffer};
                            data_bram_we[i] = 16'b1111_1111_1111_1111;
                            data_bram_wdata[i] = axi_data_i;
                        end
                    end
                end
            end
            WRITE_WAIT: begin
                for (integer i = 0; i < NWAY; i++) begin
                    // select a line to write back 
                    if (i[0] == random_r[0]) begin
                        if (axi_rvalid_i) begin
                            tag_bram_we[i] = 1;
                            //make the dirty bit 1'b1
                            tag_bram_wdata[i] = {1'b1, 1'b1, tag_buffer};
                            data_bram_we[i] = 16'b1111_1111_1111_1111;
                            data_bram_wdata[i] = axi_data_i;
                            data_bram_wdata[i] = bram_write_data;
                        end
                    end
                end
            end
            CACOP_INVALID: begin
                for (integer i = 0; i < NWAY; i++) begin
                    if (cacop_way == i[0]) begin
                        tag_bram_we[i] = 1;
                        tag_bram_wdata[i] = 0;
                    end
                end
            end
            default: begin
            end
        endcase
    end

    logic [`RegBus] wreq_sel_data;
    logic [DCACHELINE_WIDTH-1:0] bram_write_data;
    always_comb begin
        wreq_sel_data   = 0;
        bram_write_data = 0;
        case (offset_buffer[3:2])
            2'b00: wreq_sel_data = axi_data_i[31:0];
            2'b01: wreq_sel_data = axi_data_i[63:32];
            2'b10: wreq_sel_data = axi_data_i[95:64];
            2'b11: wreq_sel_data = axi_data_i[127:96];
            default: begin
            end
        endcase
        case (wstrb_buffer)
            //st.b 
            4'b0001: wreq_sel_data[7:0] = wdata_buffer[7:0];
            4'b0010: wreq_sel_data[15:8] = wdata_buffer[15:8];
            4'b0100: wreq_sel_data[23:16] = wdata_buffer[23:16];
            4'b1000: wreq_sel_data[31:24] = wdata_buffer[31:24];
            //st.h
            4'b0011: wreq_sel_data[15:0] = wdata_buffer[15:0];
            4'b1100: wreq_sel_data[31:16] = wdata_buffer[31:16];
            //st.w
            4'b1111: wreq_sel_data = wdata_buffer;
            default: begin

            end
        endcase
        case (offset_buffer[3:2])
            2'b00: bram_write_data = {axi_data_i[127:32], wreq_sel_data};
            2'b01: bram_write_data = {axi_data_i[127:64], wreq_sel_data, axi_data_i[31:0]};
            2'b10: bram_write_data = {axi_data_i[127:96], wreq_sel_data, axi_data_i[63:0]};
            2'b11: bram_write_data = {wreq_sel_data, axi_data_i[95:0]};
            default: begin
            end
        endcase
    end


    logic rd_req_r;
    logic [31:0] rd_addr_r;

    // Handshake with AXI
    always_ff @(posedge clk) begin
        case (state)
            LOOK_UP, READ_REQ: begin
                if (axi_rdy_i) begin
                    rd_req_r  <= 1;
                    rd_addr_r <= cpu_addr;
                end
            end
        endcase
    end



    // write to fifo
    always_comb begin
        fifo_wreq  = 0;
        fifo_waddr = 0;
        fifo_wdata = 0;
        case (state)
            LOOK_UP: begin
                // if write hit the cacheline in the fifo 
                // then rewrite the cacheline in the fifo 
                if (fifo_r_hit & cpu_wreq) begin
                    fifo_wreq  = 1;
                    fifo_waddr = fifo_raddr;
                    fifo_wdata = fifo_rdata;
                    case (cpu_addr[3:2])
                        2'b00: fifo_wdata[31:0] = wdata_buffer;
                        2'b01: fifo_wdata[63:32] = wdata_buffer;
                        2'b10: fifo_wdata[95:64] = wdata_buffer;
                        2'b11: fifo_wdata[127:96] = wdata_buffer;
                    endcase
                end
            end
            // if the selected way is dirty,then sent the cacheline to the fifo
            READ_WAIT, WRITE_WAIT: begin
                for (integer i = 0; i < NWAY; i++) begin
                    // select a line to write back 
                    if (axi_rvalid_i) begin
                        if (i[0] == random_r[0] & tag_bram_rdata[i][21] == 1'b1 & !fifo_state[1]) begin
                            fifo_wreq  = 1;
                            fifo_waddr = {tag_bram_rdata[i][19:0], index_buffer, 4'b0};
                            fifo_wdata = data_bram_rdata[i];
                        end
                    end
                end
            end
            CACOP_INVALID: begin
                for (integer i = 0; i < NWAY; i++) begin
                    // write the invalidate cacheline back to mem
                    // cacop mode == 1 always write back
                    // cacop mode == 2 write back when hit
                    if (cacop_op_mode1 | (cacop_op_mode2 & cacop_op_mode2_hit)) begin
                        fifo_wreq  = 1;
                        fifo_waddr = cacop_addr_buffer;
                        fifo_wdata = data_bram_rdata[i];
                    end
                end
            end
            default: begin
                fifo_wreq  = 0;
                fifo_waddr = 0;
                fifo_wdata = 0;
            end
        endcase
    end

    // Handshake with CPU
    always_comb begin
        data_ok = 0;
        rdata   = 0;
        case (state)
            LOOK_UP: begin
                if (!miss) begin
                    data_ok = 1;
                    rdata   = hit_data[cpu_addr[3:2]*32+:32];
                end else if (axi_rvalid_i) begin
                    data_ok = 1;
                    rdata   = axi_data_i[cpu_addr[3:2]*32+:32];
                end
            end
            READ_REQ, READ_WAIT: begin
                if (!miss) begin
                    data_ok = 1;
                    rdata   = hit_data[rd_addr_r[3:2]*32+:32];
                end else if (axi_rvalid_i) begin
                    data_ok = 1;
                    rdata   = axi_data_i[rd_addr_r[3:2]*32+:32];
                end
            end
            WRITE_REQ, WRITE_WAIT: begin
                if (axi_rvalid_i) begin
                    data_ok = 1;
                end
            end
        endcase
    end


    // Miss signal
    assign miss_pulse = valid_buffer & ~hit & (state == LOOK_UP);
    assign miss = miss_pulse | miss_r;
    always_ff @(posedge clk) begin
        if (rst) begin
            miss_r <= 0;
        end else if (next_state == IDLE) miss_r <= 0;
        else begin
            case (state)
                LOOK_UP: begin
                    miss_r <= miss_pulse;
                end
                READ_WAIT, WRITE_WAIT: begin
                    if (axi_rvalid_i) miss_r <= 0;
                end
                default: begin
                end
            endcase
        end
    end

    logic [21:0] tag1, tag2;
    assign tag1 = tag_bram_rdata[0];
    assign tag2 = tag_bram_rdata[1];

    // Hit signal
    always_comb begin
        tag_hit[0] = tag_bram_rdata[0][19:0] == tag_buffer && tag_bram_rdata[0][20];
        tag_hit[1] = tag_bram_rdata[1][19:0] == tag_buffer && tag_bram_rdata[1][20];
    end

    logic [DCACHELINE_WIDTH-1:0] hit_data;
    always_comb begin
        hit = 0;
        hit_data = 0;
        for (integer i = 0; i < NWAY; i++) begin
            if (tag_hit[i]) begin
                hit = 1;
                hit_data = data_bram_rdata[i];
            end
        end
        if (fifo_r_hit) begin
            hit = 1;
            hit_data = fifo_rdata;
        end
    end

    //handshake with axi
    always_comb begin
        fifo_w_accept = 0;  // which used to tell fifo if it can send data to axi
        axi_req_o = 0;
        axi_addr_o = 0;
        axi_wdata_o = 0;
        axi_we_o = 0;
        axi_wstrb_o = 0;
        case (state)
            // if the state is idle,then the dcache is free
            // so send the wdata in fifo to axi when axi is free
            IDLE: begin
                if (axi_rdy_i & !fifo_state[0]) begin
                    fifo_w_accept = 1;
                    axi_req_o = 1;
                    axi_we_o = fifo_axi_wr_req;
                    axi_addr_o = fifo_axi_wr_addr;
                    axi_wdata_o = fifo_axi_wr_data;
                    axi_wstrb_o = 16'b1111_1111_1111_1111;
                end
            end
            // if the state is look up and tag hit,then the dcache is free
            // so send the wdata in fifo to axi when axi is also free
            LOOK_UP: begin
                if (axi_rdy_i & !fifo_state[0] & !miss) begin
                    axi_req_o = 1;
                    fifo_w_accept = 1;
                    axi_we_o = fifo_axi_wr_req;
                    axi_addr_o = fifo_axi_wr_addr;
                    axi_wdata_o = fifo_axi_wr_data;
                    axi_wstrb_o = 16'b1111_1111_1111_1111;
                end
            end
            //if the axi is free then send the read request
            READ_REQ, WRITE_REQ: begin
                if (axi_rdy_i) begin
                    axi_req_o  = 1;
                    axi_addr_o = cpu_addr;
                end
            end
            // wait for the data back
            READ_WAIT, WRITE_WAIT: begin
                axi_addr_o = cpu_addr;
            end
            default: begin
                axi_req_o = 0;
                fifo_w_accept = 0;
                axi_req_o = 0;
                axi_addr_o = 0;
                axi_wdata_o = 0;
                axi_we_o = 0;
                axi_wstrb_o = 0;
            end
        endcase

    end


    dcache_fifo u_dcache_fifo (
        .clk(clk),
        .rst(rst),
        //CPU write request
        .cpu_wreq_i(fifo_wreq),
        .cpu_awaddr_i(fifo_waddr),
        .cpu_wdata_i(fifo_wdata),
        .write_hit_o(fifo_w_hit),
        //CPU read request and response
        .cpu_rreq_i(fifo_rreq),
        .cpu_araddr_i(fifo_raddr),
        .read_hit_o(fifo_r_hit),
        .cpu_rdata_o(fifo_rdata),
        //FIFO state
        .state(fifo_state),
        //write to memory 
        .axi_bvalid_i(axi_rdy_i & (state == IDLE | (state == LOOK_UP & !miss))),
        .axi_wen_o(fifo_axi_wr_req),
        .axi_wdata_o(fifo_axi_wr_data),
        .axi_awaddr_o(fifo_axi_wr_addr)
    );

    // LSFR
    lfsr #(
        .WIDTH(16)
    ) u_lfsr (
        .clk  (clk),
        .rst  (rst),
        .en   (1'b1),
        .value(random_r)
    );


    axi_dcache_master #(
        .ID(2)
    ) u_axi_master (
        .clk        (clk),
        .rst        (rst),
        .m_axi      (m_axi),
        .new_request(axi_req_o),
        .we         (axi_we_o),
        .addr       (axi_addr_o),
        .size       (3'b100),
        .data_in    (axi_wdata_o),
        .wstrb      (axi_wstrb_o),
        .ready_out  (axi_rdy_i),
        .rvalid_out (axi_rvalid_i),
        .wvalid_out (axi_bvalid_i),
        .data_out   (axi_data_i)
    );



    // BRAM instantiation
    generate
        for (genvar i = 0; i < NWAY; i++) begin : bram_ip
`ifdef BRAM_IP
            bram_icache_tag_ram u_tag_bram (
                .clk  (clk),
                .ena  (tag_bram_en[i]),
                .enb  (tag_bram_en[i]),
                .wea  (tag_bram_we[i]),
                .dina (tag_bram_wdata[i]),
                .addra(tag_bram_addr[i]),
                .addrb(tag_bram_addr[i]),
                .doutb(tag_bram_rdata[i])
            );
            bram_icache_data_ram u_data_bram (
                .clk  (clk),
                .ena  (tag_bram_en[i]),
                .enb  (tag_bram_en[i]),
                .wea  (tag_bram_we[i]),
                .dina (tag_bram_wdata[i]),
                .addra(tag_bram_addr[i]),
                .addrb(tag_bram_addr[i]),
                .doutb(tag_bram_rdata[i])
            );
`else

            dual_port_lutram #(
                .DATA_WIDTH     (TAG_BRAM_WIDTH),
                .DATA_DEPTH_EXP2($clog2(NSET))
            ) u_tag_bram (
                .clk  (clk),
                .ena  (tag_bram_en[i]),
                .enb  (tag_bram_en[i]),
                .wea  (tag_bram_we[i]),
                .dina (tag_bram_wdata[i]),
                .addra(tag_bram_addr[i]),
                .addrb(tag_bram_addr[i]),
                .doutb(tag_bram_rdata[i])
            );
            byte_bram #(
                .DATA_WIDTH     (ICACHELINE_WIDTH),
                .DATA_DEPTH_EXP2($clog2(NSET))
            ) u_data_bram (
                .clk  (clk),
                .ena  (data_bram_en[i]),
                .enb  (data_bram_en[i]),
                .wea  (data_bram_we[i]),
                .dina (data_bram_wdata[i]),
                .addra(data_bram_addr[i]),
                .addrb(data_bram_addr[i]),
                .doutb(data_bram_rdata[i])
            );
`endif
        end
    endgenerate


endmodule


