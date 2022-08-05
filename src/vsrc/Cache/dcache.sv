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
    input logic mem_valid,

    // mem req,come from ex
    input logic valid,
    input logic [`RegBus] vaddr,
    input logic [2:0] req_type,
    input logic [3:0] wstrb,
    input logic [31:0] wdata,

    //  from mem1
    input logic uncache_en,
    input logic [`RegBus] paddr,

    //CACOP
    input logic cacop_i,
    input logic [1:0] cacop_mode_i,

    input logic cpu_flush,

    output logic [1:0] tag_hit_o,

    output logic dcache_ready,
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

        UNCACHE_READ_REQ,
        UNCACHE_READ_WAIT,
        UNCACHE_WRITE_REQ,
        UNCACHE_WRITE_WAIT
    }
        state, next_state;

    logic cpu_wreq;
    logic [15:0] random_r;

    // AXI
    logic [ADDR_WIDTH-1:0] axi_addr_o;
    logic axi_req_o;
    logic axi_we_o;
    logic axi_rdy_i;
    logic axi_rvalid_i, axi_bvalid_i, axi_valid_i_delay;
    logic [2:0] axi_size_o;
    logic [AXI_DATA_WIDTH-1:0] axi_data_i;
    logic [AXI_DATA_WIDTH-1:0] axi_wdata_o;
    logic [(AXI_DATA_WIDTH/8)-1:0] axi_wstrb_o;

    // BRAM signals
    logic [NWAY-1:0][DCACHELINE_WIDTH-1:0] data_bram_rdata, data_bram_wdata, p3_data_bram_rdata;
    logic [NWAY-1:0][$clog2(NSET)-1:0] data_bram_raddr, data_bram_waddr;
    logic [NWAY-1:0][(DCACHELINE_WIDTH/8)-1:0] data_bram_we;

    // Tag bram 
    // {1bit dirty,1bit valid, 20bits tag}
    logic [NWAY-1:0][TAG_BRAM_WIDTH-1:0] tag_bram_rdata, p3_tag_bram_rdata;
    logic [NWAY-1:0][TAG_BRAM_WIDTH-1:0] tag_bram_wdata;
    logic [NWAY-1:0][$clog2(NSET)-1:0] tag_bram_raddr, tag_bram_waddr;
    logic [NWAY-1:0] tag_bram_we, tag_bram_ren;

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
    logic p3_cacop_op_mode0, p3_cacop_op_mode1, p3_cacop_op_mode2;
    logic [1:0] cacop_op_mode2_hit, p3_cacop_op_mode2_hit;
    logic [$clog2(NWAY)-1:0] cacop_way, p3_cacop_way;

    logic [1:0] dirty;

    logic [`RegBus] fifo_wreq_sel_data;


    logic [DCACHELINE_WIDTH-1:0] hit_data;
    logic fifo_full, dcache_stall;

    // P2
    logic p2_valid, p2_uncache_delay;
    logic [1:0] p3_tag_hit;
    logic [2:0] p2_req_type, p3_req_type;
    logic [3:0] p2_wstrb, p3_wstrb;
    logic [`RegBus] p2_wdata;

    // P3
    logic p3_valid, p3_uncache_en, p2_cacop, p3_cacop, p3_hit;
    logic [`RegBus] p3_wdata, p2_vaddr, p3_paddr;

    assign dcache_ready = ~dcache_stall;
    assign dcache_stall = (state != IDLE) || (next_state != IDLE) || fifo_full;
    assign fifo_full = fifo_state[1];


    //  the wstrb is not 0 means it is a write request;
    assign cpu_wreq = p3_wstrb != 4'b0;

    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin : transition_comb
        next_state = IDLE;
        case (state)
            IDLE: begin
                // if the fifo is full ,we keep the state 
                if (fifo_state[1]) next_state = IDLE;
                // if the dcache is idle,then accept the new request
                else if (p3_valid & p3_uncache_en & !cpu_flush & mem_valid & !axi_valid_i_delay) begin
                    if (cpu_wreq) next_state = UNCACHE_WRITE_REQ;
                    else next_state = UNCACHE_READ_REQ;
                end else if (p3_valid & !hit & !cpu_flush & mem_valid & !axi_valid_i_delay) begin
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
            UNCACHE_READ_REQ: begin
                if (axi_rdy_i) next_state = UNCACHE_READ_WAIT;  // If AXI ready, send request 
                else next_state = UNCACHE_READ_REQ;
            end
            UNCACHE_READ_WAIT: begin
                if (axi_rvalid_i) next_state = IDLE;
                else next_state = UNCACHE_READ_WAIT;
            end
            UNCACHE_WRITE_REQ: begin
                if (axi_rdy_i) next_state = UNCACHE_WRITE_WAIT;  // If AXI ready, send request 
                else next_state = UNCACHE_WRITE_REQ;
            end
            UNCACHE_WRITE_WAIT: begin
                if (axi_bvalid_i) next_state = IDLE;
                else next_state = UNCACHE_WRITE_WAIT;
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
            tag_bram_ren[i] = 0;
            tag_bram_raddr[i] = 0;
            data_bram_raddr[i] = 0;
        end
        if (state == IDLE) begin
            for (integer i = 0; i < NWAY; i++) begin
                if (valid | cacop_i) begin
                    tag_bram_ren[i] = 1;
                    tag_bram_raddr[i] = vaddr[11:4];
                    data_bram_raddr[i] = vaddr[11:4];
                end
            end
        end
    end

    // Stage 2
    //   - Use the tag rdata and paddr get tag hit
    //   - Use the paddr search the fifo 
    //   - Check the cacop mode and if mode2 hit


    // Hit signal
    always_comb begin
        if (uncache_en) tag_hit = 0;
        else begin
            tag_hit[0] = tag_bram_rdata[0][19:0] == paddr[31:12] && tag_bram_rdata[0][20];
            tag_hit[1] = tag_bram_rdata[1][19:0] == paddr[31:12] && tag_bram_rdata[1][20];
        end
    end

    // send to dispatch to deal with load to use
    assign tag_hit_o = tag_hit;

    assign dirty = {tag_bram_rdata[1][21], tag_bram_rdata[0][21]};

    always_comb begin : fifo_read_req
        fifo_rreq  = 0;
        fifo_raddr = 0;
        if (state == IDLE & p2_valid & !uncache_en) begin
            fifo_rreq  = 1;
            fifo_raddr = paddr;
        end
    end


    always_comb begin
        cacop_op_mode0 = 0;
        cacop_op_mode1 = 0;
        cacop_op_mode2 = 0;
        cacop_way = 0;
        if (p2_cacop) begin
            cacop_op_mode0 = cacop_mode_i == 2'b00;
            cacop_op_mode1 = cacop_mode_i == 2'b01 || cacop_mode_i == 2'b11;
            cacop_op_mode2 = cacop_mode_i == 2'b10;
            cacop_way = paddr[$clog2(NWAY)-1:0];
        end
    end

    //judge if the cacop mode2 hit
    always_comb begin
        cacop_op_mode2_hit = 0;
        if (cacop_op_mode2) begin
            for (integer i = 0; i < NWAY; i++) begin
                if (tag_bram_rdata[i][19:0] == paddr[31:12] && tag_bram_rdata[i][20])
                    cacop_op_mode2_hit[i] = 1;
            end
        end
    end

    // keep the uncache_en for stage 3 when stall
    always_ff @(posedge clk) begin
        if (rst) p2_uncache_delay <= 0;
        else if (dcache_stall) p2_uncache_delay <= uncache_en;
        else p2_uncache_delay <= 0;
    end

    // Stage 3
    //   - We get the fifo hit result and merge the hit
    //   - If requset hit ,we prepare the read/write data
    //   - If not ,turn to the refill state and stall the
    //   dcache pipeline until the refill finish

    always_comb begin
        hit = 0;
        hit_data = 0;
        for (integer i = 0; i < NWAY; i++) begin
            if (p3_tag_hit[i]) begin
                hit = 1;
                hit_data = p3_data_bram_rdata[i];
            end
        end
        if (fifo_r_hit) begin
            hit = 1;
            hit_data = fifo_rdata;
        end
    end

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
                    if (p3_tag_hit[i] && cpu_wreq && !cpu_flush && mem_valid) begin
                        tag_bram_we[i] = 1;
                        // make the dirty bit 1'b1
                        tag_bram_waddr[i] = p3_paddr[11:4];
                        tag_bram_wdata[i] = {1'b1, 1'b1, p3_paddr[31:12]};
                        data_bram_waddr[i] = p3_paddr[11:4];
                        //select the write bit
                        case (p3_wstrb)
                            //st.b 
                            4'b0001, 4'b0010, 4'b0100, 4'b1000: begin
                                data_bram_we[i][p3_paddr[3:0]] = 1'b1;
                                data_bram_wdata[i] = {4{p3_wdata}};
                            end
                            //st.h
                            4'b0011, 4'b1100: begin
                                data_bram_we[i][p3_paddr[3:0]+1] = 1'b1;
                                data_bram_we[i][p3_paddr[3:0]] = 1'b1;
                                data_bram_wdata[i] = {4{p3_wdata}};
                            end
                            //st.w
                            4'b1111: begin
                                data_bram_we[i][p3_paddr[3:0]+3] = 1'b1;
                                data_bram_we[i][p3_paddr[3:0]+2] = 1'b1;
                                data_bram_we[i][p3_paddr[3:0]+1] = 1'b1;
                                data_bram_we[i][p3_paddr[3:0]] = 1'b1;
                                data_bram_wdata[i] = {4{p3_wdata}};
                            end
                            default: begin

                            end
                        endcase
                    end
                    if (p3_cacop && !cpu_flush && mem_valid) begin
                        if ((p3_cacop_way == i[$clog2(NWAY)-1:0])) begin
                            if (p3_cacop_op_mode0 | p3_cacop_op_mode1) begin
                                tag_bram_we[i] = 1;
                                tag_bram_waddr[i] = p3_paddr[11:4];
                                tag_bram_wdata[i] = 0;
                            end
                        end
                        if (p3_cacop_op_mode2_hit[i]) begin
                            tag_bram_we[i] = 1;
                            tag_bram_waddr[i] = p3_paddr[11:4];
                            tag_bram_wdata[i] = 0;
                        end
                    end
                end
            end
            WRITE_WAIT, READ_WAIT: begin
                for (integer i = 0; i < NWAY; i++) begin
                    // select a line to write back 
                    if (i[0] == random_r[0]) begin
                        if (axi_rvalid_i) begin
                            tag_bram_we[i] = 1;
                            tag_bram_waddr[i] = p3_paddr[11:4];
                            //make the dirty bit 1'b1
                            tag_bram_wdata[i] = {1'b1, 1'b1, p3_paddr[31:12]};
                            data_bram_we[i] = 16'b1111_1111_1111_1111;
                            data_bram_waddr[i] = p3_paddr[11:4];
                            data_bram_wdata[i] = bram_write_data;
                        end
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
        case (p3_paddr[3:2])
            2'b00: wreq_sel_data = axi_data_i[31:0];
            2'b01: wreq_sel_data = axi_data_i[63:32];
            2'b10: wreq_sel_data = axi_data_i[95:64];
            2'b11: wreq_sel_data = axi_data_i[127:96];
            default: begin
            end
        endcase
        case (p3_wstrb)
            //st.b 
            4'b0001: wreq_sel_data[7:0] = p3_wdata[7:0];
            4'b0010: wreq_sel_data[15:8] = p3_wdata[15:8];
            4'b0100: wreq_sel_data[23:16] = p3_wdata[23:16];
            4'b1000: wreq_sel_data[31:24] = p3_wdata[31:24];
            //st.h
            4'b0011: wreq_sel_data[15:0] = p3_wdata[15:0];
            4'b1100: wreq_sel_data[31:16] = p3_wdata[31:16];
            //st.w
            4'b1111: wreq_sel_data = p3_wdata;
            default: begin
            end
        endcase
        case (p3_paddr[3:2])
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
        if (rst | cpu_flush) begin
            p2_valid <= 0;
            p2_req_type <= 0;
            p2_wstrb <= 0;
            p2_wdata <= 0;
            p2_cacop <= 0;
            p2_vaddr <= 0;
            p3_valid <= 0;
            p3_paddr <= 0;
            p3_req_type <= 0;
            p3_wstrb <= 0;
            p3_wdata <= 0;
            p3_cacop <= 0;
            p3_tag_hit <= 0;
            p3_uncache_en <= 0;
            p3_tag_bram_rdata <= 0;
            p3_data_bram_rdata <= 0;
            p3_cacop_way <= 0;
            p3_cacop_op_mode0 <= 0;
            p3_cacop_op_mode1 <= 0;
            p3_cacop_op_mode2 <= 0;
            p3_cacop_op_mode2_hit <= 0;
        end else if (dcache_stall) begin  // if the dcache is stall,keep the pipeline data
            p2_valid <= p2_valid;
            p2_req_type <= p2_req_type;
            p2_cacop <= p2_cacop;
            p2_wstrb <= p2_wstrb;
            p2_wdata <= p2_wdata;
            p2_vaddr <= p2_vaddr;
            p3_valid <= p3_valid;
            p3_req_type <= p3_req_type;
            p3_paddr <= p3_paddr;
            p3_wstrb <= p3_wstrb;
            p3_wdata <= p3_wdata;
            p3_cacop <= p3_cacop;
            p3_tag_hit <= p3_tag_hit;
            p3_uncache_en <= p3_uncache_en;
            p3_tag_bram_rdata <= p3_tag_bram_rdata;
            p3_data_bram_rdata <= p3_data_bram_rdata;
            p3_cacop_way <= p3_cacop_way;
            p3_cacop_op_mode0 <= p3_cacop_op_mode0;
            p3_cacop_op_mode1 <= p3_cacop_op_mode1;
            p3_cacop_op_mode2 <= p3_cacop_op_mode2;
            p3_cacop_op_mode2_hit <= p3_cacop_op_mode2_hit;
        end else begin
            // p1 -> p2
            p2_valid <= valid;
            p2_req_type <= req_type;
            p2_wstrb <= wstrb;
            p2_wdata <= wdata;
            p2_cacop <= cacop_i;
            p2_vaddr <= vaddr;
            // p2 -> p3
            p3_valid <= p2_valid;
            p3_req_type <= p2_req_type;
            p3_paddr <= paddr;
            p3_wstrb <= p2_wstrb;
            p3_wdata <= p2_wdata;
            p3_cacop <= p2_cacop;
            p3_tag_hit <= tag_hit;
            p3_uncache_en <= uncache_en | p2_uncache_delay;
            p3_tag_bram_rdata <= tag_bram_rdata;
            p3_data_bram_rdata <= data_bram_rdata;
            p3_cacop_way <= cacop_way;
            p3_cacop_op_mode0 <= cacop_op_mode0;
            p3_cacop_op_mode1 <= cacop_op_mode1;
            p3_cacop_op_mode2 <= cacop_op_mode2;
            p3_cacop_op_mode2_hit <= cacop_op_mode2_hit;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            axi_valid_i_delay <= 0;
        end else if (state != IDLE & (axi_rvalid_i | axi_bvalid_i)) begin // if the state is idle,the valid is for fifo,we don't care 
            axi_valid_i_delay <= 1;
        end else begin
            axi_valid_i_delay <= 0;
        end
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
                if (fifo_r_hit & cpu_wreq & !cpu_flush & mem_valid & !fifo_state[1]) begin
                    fifo_wreq = 1;
                    fifo_waddr = p3_paddr;
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
                        4'b0001: fifo_wreq_sel_data[7:0] = p3_wdata[7:0];
                        4'b0010: fifo_wreq_sel_data[15:8] = p3_wdata[15:8];
                        4'b0100: fifo_wreq_sel_data[23:16] = p3_wdata[23:16];
                        4'b1000: fifo_wreq_sel_data[31:24] = p3_wdata[31:24];
                        //st.h
                        4'b0011: fifo_wreq_sel_data[15:0] = p3_wdata[15:0];
                        4'b1100: fifo_wreq_sel_data[31:16] = p3_wdata[31:16];
                        //st.w
                        4'b1111: fifo_wreq_sel_data = p3_wdata;
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
                if (p3_cacop & !cpu_flush & mem_valid & !fifo_state[1]) begin
                    for (integer i = 0; i < NWAY; i++) begin
                        // write the invalidate cacheline back to mem
                        // cacop mode == 1 always write back
                        // cacop mode == 2 write back when hit
                        if (p3_cacop_way == i[$clog2(
                                NWAY
                            )-1:0] && p3_cacop_op_mode1 && p3_tag_bram_rdata[i][20]) begin
                            fifo_wreq  = 1;
                            fifo_waddr = {p3_tag_bram_rdata[i][19:0], paddr[11:0]};
                            fifo_wdata = p3_data_bram_rdata[i];
                        end
                        if (p3_cacop_op_mode2_hit[i]) begin
                            fifo_wreq  = 1;
                            fifo_waddr = {p3_tag_bram_rdata[i][19:0], paddr[11:0]};
                            fifo_wdata = p3_data_bram_rdata[i];
                        end
                    end
                end
            end
            // if the selected way is dirty,then sent the cacheline to the fifo
            READ_WAIT, WRITE_WAIT: begin
                for (integer i = 0; i < NWAY; i++) begin
                    // select a line to write back 
                    if (axi_rvalid_i) begin
                        if (i[0] == random_r[0] & p3_tag_bram_rdata[i][21] == 1'b1 & !fifo_state[1]) begin
                            fifo_wreq  = 1;
                            fifo_waddr = {p3_tag_bram_rdata[i][19:0], p3_paddr[11:4], 4'b0};
                            fifo_wdata = p3_data_bram_rdata[i];
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
                    rdata   = hit_data[p3_paddr[3:2]*32+:32];
                end else if (axi_rvalid_i) begin
                    data_ok = 1;
                    rdata   = axi_data_i[p3_paddr[3:2]*32+:32];
                end
            end
            READ_REQ, READ_WAIT, WRITE_REQ, WRITE_WAIT, UNCACHE_READ_REQ, UNCACHE_READ_WAIT: begin
                if (axi_rvalid_i) begin
                    data_ok = 1;
                    rdata   = axi_data_i[p3_paddr[3:2]*32+:32];
                end
            end
            UNCACHE_WRITE_REQ, UNCACHE_WRITE_WAIT: begin
                if (axi_bvalid_i) begin
                    data_ok = 1;
                end
            end
        endcase
    end



    //handshake with axi
    always_comb begin
        fifo_w_accept = 0;  // which used to tell fifo if it can send data to axi
        axi_req_o = 0;
        axi_addr_o = 0;
        axi_size_o = 0;
        axi_wdata_o = 0;
        axi_we_o = 0;
        axi_wstrb_o = 0;
        case (state)
            // if the state is idle,then the dcache is free
            // so send the wdata in fifo to axi when axi is free
            IDLE: begin
                if (axi_rdy_i & !fifo_state[0] & next_state == IDLE) begin
                    axi_req_o = 1;
                    fifo_w_accept = 1;
                    axi_we_o = fifo_axi_wr_req;
                    axi_size_o = 3'b100;
                    axi_addr_o = fifo_axi_wr_addr;
                    axi_wdata_o = fifo_axi_wr_data;
                    axi_wstrb_o = 16'b1111_1111_1111_1111;
                end
            end
            //if the axi is free then send the read request
            READ_REQ, WRITE_REQ: begin
                if (axi_rdy_i) begin
                    axi_req_o  = 1;
                    axi_size_o = 3'b100;
                    axi_addr_o = {p3_paddr[31:4], 4'b0};
                end
            end
            UNCACHE_READ_REQ: begin
                if (axi_rdy_i) begin
                    axi_req_o  = 1;
                    axi_size_o = p3_req_type;
                    axi_addr_o = p3_paddr;
                end
            end
            UNCACHE_WRITE_REQ: begin
                if (axi_rdy_i) begin
                    axi_req_o  = 1;
                    axi_we_o   = 1;
                    axi_size_o = p3_req_type;
                    axi_addr_o = p3_paddr;
                    case (p3_paddr[3:2])
                        2'b00: begin
                            axi_wdata_o = {{96{1'b0}}, p3_wdata};
                            axi_wstrb_o = {12'b0, p3_wstrb};
                        end
                        2'b01: begin
                            axi_wdata_o = {{64{1'b0}}, p3_wdata, {32{1'b0}}};
                            axi_wstrb_o = {8'b0, p3_wstrb, 4'b0};
                        end
                        2'b10: begin
                            axi_wdata_o = {32'b0, p3_wdata, {64{1'b0}}};
                            axi_wstrb_o = {4'b0, p3_wstrb, 8'b0};
                        end
                        2'b11: begin
                            axi_wdata_o = {p3_wdata, {96{1'b0}}};
                            axi_wstrb_o = {p3_wstrb, 12'b0};
                        end
                    endcase
                end
            end
            // wait for the data back
            READ_WAIT, WRITE_WAIT: begin
                axi_addr_o = {p3_paddr[31:4], 4'b0};
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
        .axi_bvalid_i(axi_rdy_i & (state == IDLE) & (next_state == IDLE)),
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
        .ID(0)
    ) u_axi_master (
        .clk        (clk),
        .rst        (rst),
        .m_axi      (m_axi),
        .new_request(axi_req_o),
        .we         (axi_we_o),
        .addr       (axi_addr_o),
        .size       (axi_size_o),
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
                .enb  (~dcache_stall),
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
                .enb  (~dcache_stall),
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
                .enb  (~dcache_stall),
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
                .enb  (~dcache_stall),
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


