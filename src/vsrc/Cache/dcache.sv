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
    input logic excp,

    // mem req,come from ex
    input logic valid,
    input logic [`RegBus] vaddr,
    input logic [3:0] wstrb,
    input logic [31:0] wdata,

    // paddr from mem1
    input logic [`RegBus] paddr,

    //CACOP
    input logic cacop_i,
    input logic [1:0] cacop_mode_i,

    output logic data_ok,
    output logic [31:0] rdata,

    axi_interface.master m_axi
);

    localparam NWAY = DCACHE_NWAY;
    localparam NSET = DCACHE_NSET;
    localparam OFFSET_WIDTH = $clog2(DCACHELINE_WIDTH / 8);
    localparam NSET_WIDTH = $clog2(NSET);
    localparam NWAY_WIDTH = $clog2(NWAY);
    localparam TAG_WIDTH = ADDR_WIDTH - NSET_WIDTH - OFFSET_WIDTH;
    localparam TAG_BRAM_WIDTH = 22;

    enum int {
        IDLE,

        READ_REQ,
        READ_WAIT,
        WRITE_REQ,
        WRITE_WAIT,
        REFILLING,

        CACOP_INVALID
    }
        state, next_state;

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
    logic [NWAY-1:0][DCACHELINE_WIDTH-1:0] data_bram_rdata, data_bram_wdata;
    logic [NWAY-1:0][$clog2(NSET)-1:0] data_bram_raddr, data_bram_waddr;
    logic [NWAY-1:0][(DCACHELINE_WIDTH/8)-1:0] data_bram_we;

    // Tag bram 
    // {1bit dirty,1bit valid, 20bits tag}
    logic [NWAY-1:0][TAG_BRAM_WIDTH-1:0] tag_bram_rdata;
    logic [NWAY-1:0][TAG_BRAM_WIDTH-1:0] tag_bram_wdata;
    logic [NWAY-1:0][$clog2(NSET)-1:0] tag_bram_raddr, tag_bram_waddr;
    logic [NWAY-1:0 ] tag_bram_we;

    logic [ `RegBus]  cpu_addr;
    logic miss_pulse, miss_r, miss;
    logic hit;
    logic [NWAY-1:0] tag_hit;

    logic [`RegBus] wreq_sel_data;
    logic [DCACHELINE_WIDTH-1:0] bram_write_data;


    logic [1:0] fifo_state;
    logic fifo_rreq, fifo_wreq, fifo_r_hit, fifo_w_hit, fifo_axi_wr_req, fifo_w_accept;
    logic [`DataAddrBus] fifo_raddr, fifo_waddr, fifo_axi_wr_addr;
    logic [DCACHELINE_WIDTH-1:0] fifo_rdata, fifo_wdata, fifo_axi_wr_data;

    // CACOP
    logic cacop_op_mode0, cacop_op_mode1, cacop_op_mode2;
    logic [1:0] cacop_op_mode2_hit;
    logic [$clog2(NWAY)-1:0] cacop_way;

    logic [1:0] dirty;

    logic [`RegBus] fifo_wreq_sel_data;

    logic rd_req_r;
    logic [31:0] rd_addr_r;
    logic [DCACHELINE_WIDTH-1:0] hit_data;
    logic refill_stall;

    // reg for p2 and p3 state
    logic p2_valid, p3_valid, p3_fifo_hit;
    logic [1:0] p3_tag_hit;
    logic [3:0] p2_wstrb, p3_wstrb;
    logic [`RegBus] p2_wdata, p3_wdata, p3_paddr;

    assign refill_stall = state != IDLE;

    assign cpu_addr = {tag_buffer, index_buffer, offset_buffer};

    assign cacop_op_mode0 = cacop_i && cacop_mode_i == 2'b00;
    assign cacop_op_mode1 = cacop_i && (cacop_mode_i == 2'b01 || cacop_mode_i == 2'b11);
    assign cacop_op_mode2 = cacop_i && cacop_mode_i == 2'b10;
    assign cacop_way = paddr[$clog2(NWAY)-1:0];

    //judge if the cacop mode2 hit
    always_comb begin
        cacop_op_mode2_hit = 0;
        if (cacop_op_mode2 && cacop_i) begin
            for (integer i = 0; i < NWAY; i++) begin
                if (tag_bram_rdata[i][19:0] == paddr[31:12] && tag_bram_rdata[i][20])
                    cacop_op_mode2_hit[i] = 1;
            end
        end
    end

    //  the wstrb is not 0 means it is a write request;
    assign cpu_wreq = wstrb_buffer != 4'b0;

    always_comb begin : transition_comb
        next_state = IDLE;
        case (state)
            IDLE: begin
                if (cacop_i) next_state = CACOP_INVALID;
                // if the dcache is idle,then accept the new request
                else if (p3_valid & !hit) begin
                    if (cpu_wreq) next_state = WRITE_REQ;
                    else next_state = READ_REQ;
                end else next_state = IDLE;
            end
            READ_REQ: begin
                if (axi_rdy_i) next_state = READ_WAIT;  // If AXI ready, send request 
                else next_state = READ_REQ;
            end
            READ_WAIT: begin
                // If return valid, back to IDLE
                if (axi_rvalid_i) next_state = REFILLING;
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
                if (axi_rvalid_i) next_state = REFILLING;
                else next_state = WRITE_WAIT;
            end
            REFILLING: begin
                next_state = IDLE;
            end
            CACOP_INVALID: begin
                if (fifo_state[1]) next_state = CACOP_INVALID;
                else next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end


    // Stage 1
    //   - Use the virtual index to search
    //
    // Setup Tag RAM port B. We only use this port for tag query, not writing

    always_comb begin
        // Default all 0
        for (integer i = 0; i < NWAY; i++) begin
            tag_bram_raddr[i]  = 0;
            data_bram_raddr[i] = 0;
        end
        if (state == IDLE) begin
            for (integer i = 0; i < NWAY; i++) begin
                if (valid | cacop_i) begin
                    tag_bram_raddr[i]  = vaddr[11:4];
                    data_bram_raddr[i] = vaddr[11:4];
                end
            end
        end
    end

    // Stage 2
    //   - Use the tag rdata and paddr get tag hit
    //   - Use the paddr search the fifo and get fifo hit
    //   - Dual with the read after write


    // Hit signal
    always_comb begin
        tag_hit[0] = tag_bram_rdata[0][19:0] == tag_buffer && tag_bram_rdata[0][20];
        tag_hit[1] = tag_bram_rdata[1][19:0] == tag_buffer && tag_bram_rdata[1][20];
    end

    assign dirty = {tag_bram_rdata[1][21], tag_bram_rdata[0][21]};

    always_comb begin : fifo_read_req
        fifo_rreq  = 0;
        fifo_raddr = 0;
        if (state == IDLE & p2_valid) begin
            fifo_rreq  = 1;
            fifo_raddr = paddr;
        end
    end

    // Stage 3
    //   - If requset hit ,we prepare the read/write data
    //   - If not ,turn to the refill state and stall the
    //   dcache pipeline until the refill finish

    always_comb begin : bram_data_gen
        for (integer i = 0; i < NWAY; i++) begin
            tag_bram_we[i] = 0;
            tag_bram_waddr[i] = 0;
            tag_bram_wdata[i] = 0;
            data_bram_we[i] = 0;
            data_bram_waddr[i] = 0;
            data_bram_wdata[i] = 0;
        end
        case (state)
            IDLE: begin
                // if write hit,then replace the cacheline
                for (integer i = 0; i < NWAY; i++) begin
                    // if write hit ,then write the hit line, if miss then don't write
                    if (p3_tag_hit[i] && cpu_wreq) begin
                        tag_bram_we[i] = 1;
                        // make the dirty bit 1'b1
                        tag_bram_waddr[i] = paddr[11:4];
                        tag_bram_wdata[i] = {1'b1, 1'b1, paddr[31:12]};
                        data_bram_waddr[i] = paddr[11:4];
                        //select the write bit
                        case (p3_wstrb)
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
            REFILLING: begin
                for (integer i = 0; i < NWAY; i++) begin
                    // select a line to write back 
                    if (i[0] == random_r[0]) begin
                        if (axi_rvalid_i) begin
                            tag_bram_we[i] = 1;
                            tag_bram_waddr[i] = paddr[11:4];
                            //make the dirty bit 1'b1
                            tag_bram_wdata[i] = {1'b1, 1'b1, paddr[31:12]};
                            data_bram_we[i] = 16'b1111_1111_1111_1111;
                            data_bram_waddr[i] = paddr[11:4];
                            data_bram_wdata[i] = bram_write_data;
                        end
                    end
                end
            end
            CACOP_INVALID: begin
                for (integer i = 0; i < NWAY; i++) begin
                    if ((cacop_way == i[$clog2(NWAY)-1:0])) begin
                        if (cacop_op_mode0 | cacop_op_mode1) begin
                            tag_bram_we[i] = 1;
                            tag_bram_waddr[i] = paddr[11:4];
                            tag_bram_wdata[i] = 0;
                        end
                    end
                    if (cacop_op_mode2_hit[i]) begin
                        tag_bram_we[i] = 1;
                        tag_bram_waddr[i] = paddr[11:4];
                        tag_bram_wdata[i] = 0;
                    end
                end
            end
            default: begin
            end
        endcase
    end

    always_comb begin
        wreq_sel_data   = 0;
        bram_write_data = 0;
        case (paddr[3:2])
            2'b00: wreq_sel_data = axi_data_i[31:0];
            2'b01: wreq_sel_data = axi_data_i[63:32];
            2'b10: wreq_sel_data = axi_data_i[95:64];
            2'b11: wreq_sel_data = axi_data_i[127:96];
            default: begin
            end
        endcase
        case (p3_wstrb)
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
        case (paddr[3:2])
            2'b00: bram_write_data = {axi_data_i[127:32], wreq_sel_data};
            2'b01: bram_write_data = {axi_data_i[127:64], wreq_sel_data, axi_data_i[31:0]};
            2'b10: bram_write_data = {axi_data_i[127:96], wreq_sel_data, axi_data_i[63:0]};
            2'b11: bram_write_data = {wreq_sel_data, axi_data_i[95:0]};
            default: begin
            end
        endcase
    end

    // keep the data from last state
    always_ff @(posedge clk) begin : p2_reg
        if (rst) begin
            p2_valid <= 0;
            p2_wstrb <= 0;
            p2_wdata <= 0;
            p3_valid <= 0;
            p3_paddr <= 0;
            p3_wstrb <= 0;
            p3_wdata <= 0;
            p3_tag_hit <= 0;
            p3_fifo_hit <= 0;
        end else if (refill_stall) begin
            p2_valid <= p2_valid;
            p2_wstrb <= p2_wstrb;
            p2_wdata <= p2_wdata;
            p3_valid <= p3_valid;
            p3_paddr <= p3_paddr;
            p3_wstrb <= p3_wstrb;
            p3_wdata <= p3_wdata;
            p3_tag_hit <= p3_tag_hit;
            p3_fifo_hit <= p3_fifo_hit;
        end else begin
            p2_valid <= valid;
            p2_wstrb <= wstrb;
            p2_wdata <= wdata;
            p3_valid <= p2_valid;
            p3_paddr <= paddr;
            p3_wstrb <= p2_wstrb;
            p3_wdata <= p3_wdata;
            p3_tag_hit <= tag_hit;
            p3_fifo_hit <= fifo_r_hit;
        end
    end


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
        fifo_wreq = 0;
        fifo_waddr = 0;
        fifo_wdata = 0;
        fifo_wreq_sel_data = 0;
        case (state)
            IDLE: begin
                // if write hit the cacheline in the fifo 
                // then rewrite the cacheline in the fifo 
                if (p3_fifo_r_hit & cpu_wreq) begin
                    fifo_wreq = 1;
                    fifo_waddr = fifo_raddr;
                    fifo_wdata = fifo_rdata;
                    fifo_wreq_sel_data = 0;
                    case (p3_paddr[3:2])
                        2'b00: fifo_wreq_sel_data = fifo_wdata[31:0];
                        2'b01: fifo_wreq_sel_data = fifo_wdata[63:32];
                        2'b10: fifo_wreq_sel_data = fifo_wdata[95:64];
                        2'b11: fifo_wreq_sel_data = fifo_wdata[127:96];
                    endcase
                    case (p3_wstrb)
                        //st.b 
                        4'b0001: fifo_wreq_sel_data[7:0] = wdata_buffer[7:0];
                        4'b0010: fifo_wreq_sel_data[15:8] = wdata_buffer[15:8];
                        4'b0100: fifo_wreq_sel_data[23:16] = wdata_buffer[23:16];
                        4'b1000: fifo_wreq_sel_data[31:24] = wdata_buffer[31:24];
                        //st.h
                        4'b0011: fifo_wreq_sel_data[15:0] = wdata_buffer[15:0];
                        4'b1100: fifo_wreq_sel_data[31:16] = wdata_buffer[31:16];
                        //st.w
                        4'b1111: fifo_wreq_sel_data = wdata_buffer;
                        default: begin

                        end
                    endcase
                    case (p3_paddr[3:2])
                        2'b00: fifo_wdata[31:0] = fifo_wreq_sel_data;
                        2'b01: fifo_wdata[63:32] = fifo_wreq_sel_data;
                        2'b10: fifo_wdata[95:64] = fifo_wreq_sel_data;
                        2'b11: fifo_wdata[127:96] = fifo_wreq_sel_data;
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
                    if (!fifo_state[1]) begin
                        if (cacop_way == i[$clog2(
                                NWAY
                            )-1:0] && cacop_op_mode1 && tag_bram_rdata[i][20]) begin
                            fifo_wreq  = 1;
                            fifo_waddr = {tag_bram_rdata[i][19:0], paddr[11:0]};
                            fifo_wdata = data_bram_rdata[i];
                        end
                        if (cacop_op_mode2_hit[i]) begin
                            fifo_wreq  = 1;
                            fifo_waddr = {tag_bram_rdata[i][19:0], paddr[11:0]};
                            fifo_wdata = data_bram_rdata[i];
                        end
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
            IDLE: begin
                if (hit) begin
                    data_ok = 1;
                    rdata   = hit_data[cpu_addr[3:2]*32+:32];
                end else if (axi_rvalid_i) begin
                    data_ok = 1;
                    rdata   = axi_data_i[cpu_addr[3:2]*32+:32];
                end
            end
            READ_REQ, READ_WAIT: begin
                if (axi_rvalid_i) begin
                    data_ok = 1;
                    rdata   = axi_data_i[rd_addr_r[3:2]*32+:32];
                end
            end
            WRITE_REQ, WRITE_WAIT: begin
                if (axi_rvalid_i) begin
                    data_ok = 1;
                end
            end
            CACOP_INVALID: begin
                data_ok = 1;
            end
        endcase
    end

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
                    axi_addr_o = {p3_paddr[31:4], 4'b0};
                end
            end
            // wait for the data back
            READ_WAIT, WRITE_WAIT: begin
                axi_addr_o = {p3_paddr[31:4], 4'b0};
            end
            CACOP_INVALID: begin
                if (axi_rdy_i & !fifo_state[0]) begin
                    fifo_w_accept = 1;
                    axi_req_o = 1;
                    axi_we_o = fifo_axi_wr_req;
                    axi_addr_o = fifo_axi_wr_addr;
                    axi_wdata_o = fifo_axi_wr_data;
                    axi_wstrb_o = 16'b1111_1111_1111_1111;
                end
            end
            default: begin
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
        .axi_bvalid_i(axi_rdy_i & (state == IDLE | state == CACOP_INVALID)),
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
            bram_dcache_tag_ram u_tag_bram (
                .clka (clk),
                .clkb (clk),
                .ena  (1'b1),
                .enb  (1'b1),
                .wea  (tag_bram_we[i]),
                .web  (0),
                .dina (tag_bram_wdata[i]),
                .addra(tag_bram_waddr[i]),
                .douta(),
                .dinb (tag_bram_wdata[i]),
                .addrb(tag_bram_raddr[i]),
                .doutb(tag_bram_rdata[i])
            );
            dcache_data_bram u_data_bram (
                .clka (clk),
                .clkb (clk),
                .ena  (1'b1),
                .enb  (1'b1),
                .wea  (data_bram_we[i]),
                .web  (0),
                .dina (data_bram_wdata[i]),
                .addra(data_bram_waddr[i]),
                .douta(),
                .dinb (data_bram_wdata[i]),
                .addrb(data_bram_raddr[i]),
                .doutb(data_bram_rdata[i])
            );
`else

            dual_port_lutram #(
                .DATA_WIDTH     (TAG_BRAM_WIDTH),
                .DATA_DEPTH_EXP2($clog2(NSET))
            ) u_tag_bram (
                .clk  (clk),
                .ena  (1'b1),
                .enb  (1'b1),
                .wea  (tag_bram_we[i]),
                .dina (tag_bram_wdata[i]),
                .addra(tag_bram_waddr[i]),
                .addrb(tag_bram_raddr[i]),
                .doutb(tag_bram_rdata[i])
            );
            byte_bram #(
                .DATA_WIDTH     (DCACHELINE_WIDTH),
                .DATA_DEPTH_EXP2($clog2(NSET))
            ) u_data_bram (
                .clk  (clk),
                .ena  (1'b1),
                .enb  (1'b1),
                .wea  (data_bram_we[i]),
                .dina (data_bram_wdata[i]),
                .addra(data_bram_waddr[i]),
                .addrb(data_bram_raddr[i]),
                .doutb(data_bram_rdata[i])
            );
`endif
        end
    endgenerate


endmodule


