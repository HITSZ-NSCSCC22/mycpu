`include "core_config.sv"
`include "defines.sv"
`include "utils/lfsr.sv"
`include "utils/byte_bram.sv"
`include "utils/dual_port_lutram.sv"
`include "Cache/dcache_fifo.sv"
// `include "axi/axi_dcache_master.sv"
`include "axi/axi_read_channel.sv"
`include "axi/axi_write_channel.sv"
`include "axi/axi_interface.sv"

module dcache
    import core_config::*;
(
    input logic clk,
    input logic rst,
    input logic mem_valid,

    // mem req,come from ex
    input logic valid,
    input logic [`RegBus] paddr,
    input logic [2:0] req_type,
    input logic [3:0] wstrb,
    input logic [31:0] wdata,

    //  from mem1
    input logic uncache_en,

    //CACOP
    input logic cacop_i,
    input logic [1:0] cacop_mode_i,

    input logic cpu_flush,

    output logic [NWAY-1:0] tag_hit_o,

    output logic dcache_ready,
    output logic data_ok,
    output logic [31:0] rdata,

    axi_interface.master m_axi
);
    // axi_interface m_axi();

    localparam NWAY = DCACHE_NWAY;
    localparam NSET = DCACHE_NSET;
    localparam OFFSET_WIDTH = $clog2(DCACHELINE_WIDTH / 8);
    localparam NSET_WIDTH = $clog2(NSET);
    localparam NWAY_WIDTH = $clog2(NWAY);
    localparam TAG_WIDTH = ADDR_WIDTH - NSET_WIDTH - OFFSET_WIDTH;
    localparam TAG_BRAM_WIDTH = TAG_WIDTH + 2;


    // State machine is located at P3
    enum int {
        IDLE,

        READ_REQ,
        READ_WAIT,
        WRITE_REQ,
        WRITE_WAIT,

        UNCACHE_READ_REQ,
        UNCACHE_READ_WAIT,
        UNCACHE_WRITE_REQ,
        UNCACHE_WRITE_WAIT,

        CACOP_REQ,
        CACOP_WAIT,

        FIFO_CLEAR,

        WRITE_BACK_REQ,
        WRITE_BACK_WAIT
    }
        state, next_state;

    logic [15:0] random_r;

    // AXI
    logic [ADDR_WIDTH-1:0] axi_addr_o;
    logic axi_wreq_o, axi_rreq_o;
    logic axi_uncached_o;
    logic axi_rrdy_i, axi_wrdy_i;
    logic axi_rvalid_i, axi_bvalid_i;
    logic [2:0] axi_size_o;
    logic [AXI_DATA_WIDTH-1:0] axi_data_i;
    logic [AXI_DATA_WIDTH-1:0] axi_wdata_o;
    logic [(AXI_DATA_WIDTH/8)-1:0] axi_wstrb_o;

    logic bram_rdata_delay;

    // BRAM signals
    logic [NWAY-1:0][DCACHELINE_WIDTH-1:0]
        data_bram_rdata, data_bram_rdata_delay, data_bram_wdata, p3_data_bram_rdata;
    logic [NWAY-1:0][NSET_WIDTH-1:0] data_bram_raddr, data_bram_waddr;
    logic [NWAY-1:0][(DCACHELINE_WIDTH/8)-1:0] data_bram_we;

    // Tag bram 
    // {1bit dirty, 1bit valid, tag_width tag}
    logic [NWAY-1:0][TAG_BRAM_WIDTH-1:0]
        tag_bram_rdata, tag_bram_rdata_delay, p3_tag_bram_rdata;
    logic [NWAY-1:0][TAG_BRAM_WIDTH-1:0] tag_bram_wdata;
    logic [NWAY-1:0][NSET_WIDTH-1:0] tag_bram_raddr, tag_bram_waddr;
    logic [NWAY-1:0] tag_bram_we, tag_bram_ren;



    logic [`RegBus] wreq_sel_data;

    // FIFO handshake
    logic [1:0] fifo_state;
    logic fifo_full;
    logic fifo_rreq, fifo_wreq, fifo_r_hit, fifo_w_hit, fifo_axi_wr_req, fifo_w_accept;
    logic [`DataAddrBus] fifo_raddr, fifo_waddr, fifo_axi_wr_addr;
    logic [DCACHELINE_WIDTH-1:0] fifo_rdata, fifo_wdata, fifo_axi_wr_data;
    logic [`RegBus] fifo_wreq_sel_data;



    // P2
    logic p2_valid, p2_uncache_en;
    logic [ADDR_WIDTH-1:0] p2_paddr;
    logic [1:0] p2_cacop_mode;
    logic [2:0] p2_req_type;
    logic [3:0] p2_wstrb;
    logic [DATA_WIDTH-1:0] p2_wdata;
    logic [NWAY-1:0] p2_tag_hit, p2_tag_hit_r;
    // CACOP
    logic p2_cacop;
    logic p2_cacop_op_mode0, p2_cacop_op_mode1, p2_cacop_op_mode2;
    logic [NWAY_WIDTH-1:0] p2_cacop_way;
    logic [1:0] p2_cacop_op_mode2_hit, p2_cacop_op_mode2_hit_r;

    // P3
    logic p3_valid, p3_uncache_en;
    logic [DATA_WIDTH-1:0] p3_wdata;
    logic [ADDR_WIDTH-1:0] p3_paddr;
    logic [2:0] p3_req_type;
    logic [3:0] p3_wstrb;
    logic p3_hit;
    logic [NWAY-1:0] p3_tag_hit;
    logic p3_cpu_wreq;
    logic [DCACHELINE_WIDTH-1:0] p3_hit_data;
    logic [DCACHELINE_WIDTH-1:0] p3_refill_data;
    // CACOP
    logic p3_cacop;
    logic p3_cacop_op_mode0, p3_cacop_op_mode1, p3_cacop_op_mode2;
    logic [NWAY_WIDTH-1:0] p3_cacop_way;
    logic [1:0] p3_cacop_op_mode2_hit;
    logic p3_cacop_writeback_valid;
    logic [ADDR_WIDTH-1:0] p3_cacop_writeback_waddr;
    logic [DCACHELINE_WIDTH-1:0] p3_cacop_writeback_wdata;

    logic write_back_req;
    logic [ADDR_WIDTH-1:0] write_back_addr;
    logic [DCACHELINE_WIDTH-1:0] write_back_data;

    // DCache pipeline control
    logic dcache_stall, dcache_stall_delay;
    assign dcache_ready = state == IDLE && ~dcache_stall;
    // DCache pipeline is stalled if
    // 1. Currently busy
    // 2. Cannot return result in P3, for any reason.
    assign dcache_stall = (state != IDLE && !data_ok) || (state == IDLE &&((p3_valid & (p3_uncache_en | ~p3_hit)) | p3_cacop_writeback_valid) && !cpu_flush && mem_valid);
    assign fifo_full = fifo_state[1];
    always_ff @(posedge clk) begin
        if (rst) dcache_stall_delay <= 0;
        else dcache_stall_delay <= dcache_stall;
    end



    ////////////////////////////////////////////////////////////////////////////////////////
    // Stage 1
    //   - Use the index to search
    //
    // Setup Tag RAM port B. We only use this port for tag query, not writing
    ////////////////////////////////////////////////////////////////////////////////////////

    // P1 comb
    always_comb begin : bram_read_comb
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
                    tag_bram_raddr[i] = paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                    data_bram_raddr[i] = paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                end
            end
        end
    end

    ////////////////////////////////////////////////////////////////////////////////////////
    // Stage 2
    //   - Use the tag rdata and paddr get tag hit
    //   - Use the paddr search the fifo 
    //   - Check the cacop mode and if mode2 hit
    ////////////////////////////////////////////////////////////////////////////////////////

    // P2 ff
    always_ff @(posedge clk) begin : p2_reg
        if (rst | cpu_flush) begin
            p2_valid <= 0;
            p2_req_type <= 0;
            p2_wstrb <= 0;
            p2_wdata <= 0;
            p2_cacop_mode <= 0;
            p2_uncache_en <= 0;
            p2_cacop <= 0;
            p2_paddr <= 0; 
        end else if (dcache_stall) begin  // if the dcache is stall,keep the pipeline data
        end else begin
            // p1 -> p2
            p2_valid <= valid;
            p2_req_type <= req_type;
            p2_wstrb <= wstrb;
            p2_wdata <= wdata;
            p2_cacop <= cacop_i;
            p2_paddr <= paddr;
            p2_cacop_mode <= cacop_mode_i;
            p2_uncache_en <= uncache_en;
        end
    end
    
    // P2 comb
    // Hit signal
    always_comb begin : p2_tag_hit_comb
        p2_tag_hit = 0;
        if (p2_valid & ~p2_uncache_en) begin
            for (integer i = 0; i < NWAY; i++) begin
                p2_tag_hit[i] = tag_bram_rdata[i][TAG_WIDTH-1:0] == p2_paddr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_WIDTH] && tag_bram_rdata[i][TAG_WIDTH];
            end
        end
    end

    // FIFO read
    always_comb begin : fifo_read_req_comb
        fifo_rreq  = 0;
        fifo_raddr = 0;
        // The same condition as P2 -> P3 advance condition
        // This is to ensure fifo_r_hit match the actual request
        // Uncache request or CACOP does not use fifo_r_hit, so no rreq
        if (~dcache_stall & ~cpu_flush & p2_valid & ~p2_uncache_en) begin
            fifo_rreq  = 1;
            fifo_raddr = {p2_paddr[31:4], 4'b0};
        end
    end

    // CACOP
    always_comb begin
        p2_cacop_op_mode0 = 0;
        p2_cacop_op_mode1 = 0;
        p2_cacop_op_mode2 = 0;
        p2_cacop_way = 0;
        if (p2_cacop) begin
            p2_cacop_op_mode0 = p2_cacop_mode == 2'b00;
            p2_cacop_op_mode1 = p2_cacop_mode == 2'b01 || p2_cacop_mode == 2'b11;
            p2_cacop_op_mode2 = p2_cacop_mode == 2'b10;
            p2_cacop_way = p2_paddr[NWAY_WIDTH-1:0];
        end
    end

    // CACOP op2 hit
    always_comb begin
        p2_cacop_op_mode2_hit = 0;
        if (p2_cacop_op_mode2) begin
            for (integer i = 0; i < NWAY; i++) begin
                if (tag_bram_rdata[i][TAG_WIDTH-1:0] == p2_paddr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_WIDTH] && tag_bram_rdata[i][TAG_WIDTH])
                    p2_cacop_op_mode2_hit[i] = 1;
            end
        end
    end

    // BRAM output register
    always_ff @(posedge clk) begin
        if (rst) begin
            bram_rdata_delay <= 0;
            p2_tag_hit_r <= 0;
            tag_bram_rdata_delay <= 0;
            data_bram_rdata_delay <= 0;
            p2_cacop_op_mode2_hit_r <= 0;
        end else if (dcache_stall & !dcache_stall_delay) begin
            bram_rdata_delay <= 1;
            p2_tag_hit_r <= p2_tag_hit;
            tag_bram_rdata_delay <= tag_bram_rdata;
            data_bram_rdata_delay <= data_bram_rdata;
            p2_cacop_op_mode2_hit_r <= p2_cacop_op_mode2_hit;
        end else if (!dcache_stall & dcache_stall_delay) begin
            bram_rdata_delay <= 0;
            p2_tag_hit_r <= 0;
            tag_bram_rdata_delay <= 0;
            data_bram_rdata_delay <= 0;
            p2_cacop_op_mode2_hit_r <= 0;
        end
    end

    //////////////////////////////////////////////////////////////////////////////////
    // Stage 2 END
    //////////////////////////////////////////////////////////////////////////////////



    //////////////////////////////////////////////////////////////////////////////////
    // Stage 3
    //   - We get the fifo hit result and merge the hit
    //   - If request hit, we prepare the read/write data
    //   - If miss or is a special request, transit to non-IDLE state 
    //     and stall the dcache pipeline until the refill finish
    //////////////////////////////////////////////////////////////////////////////////

    // State Machine
    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin : transition_comb
        case (state)
            IDLE: begin
                if (~mem_valid | cpu_flush)
                    // Remain IDLE if P3 request is invalid
                    // IMPORTANT! assume P3 request is valid in other state
                    next_state = IDLE;
                else if (p3_cacop_writeback_valid)
                    // CACOP cause a state change
                    next_state = CACOP_REQ;
                else if (p3_valid & p3_uncache_en) begin
                    // Uncached request
                    if (p3_cpu_wreq) next_state = UNCACHE_WRITE_REQ;
                    else next_state = UNCACHE_READ_REQ;
                end else if (p3_valid & ~p3_hit) begin
                    // Cached request, but miss
                    if (p3_cpu_wreq) next_state = WRITE_REQ;
                    else next_state = READ_REQ;
                end else 
                    // P3 is a hit request
                    next_state = IDLE;
            end
            READ_REQ: begin
                if (axi_rrdy_i)  // If AXI ready, send request
                    next_state = READ_WAIT;  
                else next_state = READ_REQ;
            end
            READ_WAIT: begin
                if ((axi_rvalid_i | axi_rrdy_i) ) begin
                    if(write_back_req)next_state = WRITE_BACK_REQ;
                    else next_state = IDLE;
                end// If return valid, back to IDLE
                    
                else next_state = READ_WAIT;
            end
            WRITE_REQ: begin
                if (axi_rrdy_i) // If AXI ready, send request
                    next_state = WRITE_WAIT;
                else next_state = WRITE_REQ;
            end
            WRITE_WAIT: begin
                if ((axi_rvalid_i | axi_rrdy_i) ) begin
                    if(write_back_req)next_state = WRITE_BACK_REQ;
                    else next_state = IDLE;
                end
                else next_state = WRITE_WAIT;
            end
            WRITE_BACK_REQ:begin
                if (axi_wrdy_i) // If return valid, back to IDLE
                    next_state = WRITE_BACK_WAIT;
                else next_state = WRITE_BACK_REQ;
            end
            WRITE_BACK_WAIT:begin
                if (axi_bvalid_i) // If return valid, back to IDLE
                    next_state = IDLE;
                else next_state = WRITE_BACK_WAIT;
            end
            UNCACHE_READ_REQ: begin
                if (axi_rrdy_i)  // If AXI ready, send request 
                    next_state = UNCACHE_READ_WAIT; 
                else next_state = UNCACHE_READ_REQ;
            end
            UNCACHE_READ_WAIT: begin
                if (axi_rvalid_i) 
                    next_state = IDLE;
                else next_state = UNCACHE_READ_WAIT;
            end
            UNCACHE_WRITE_REQ: begin
                if (axi_wrdy_i)  // If AXI ready, send request 
                    next_state = UNCACHE_WRITE_WAIT; 
                else next_state = UNCACHE_WRITE_REQ;
            end
            UNCACHE_WRITE_WAIT: begin
                if (axi_bvalid_i)  // If return valid, back to IDLE
                    next_state = IDLE;
                else next_state = UNCACHE_WRITE_WAIT;
            end
            CACOP_REQ: begin
                if (axi_wrdy_i)
                    next_state = CACOP_WAIT;
                else next_state = CACOP_REQ;
            end
            CACOP_WAIT: begin
                if (axi_bvalid_i) 
                    next_state = IDLE;
                else next_state = CACOP_WAIT;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // P3 ff
    always_ff @(posedge clk) begin : p3_ff
        if (rst | cpu_flush) begin
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
        end else if (dcache_stall) begin
        end else begin
            p3_valid <= p2_valid;
            p3_req_type <= p2_req_type;
            p3_paddr <= p2_paddr;
            p3_wstrb <= p2_wstrb;
            p3_wdata <= p2_wdata;
            p3_cacop <= p2_cacop;
            p3_tag_hit <= bram_rdata_delay ? p2_tag_hit_r : p2_tag_hit;
            p3_uncache_en <= p2_uncache_en;
            p3_tag_bram_rdata <= bram_rdata_delay ? tag_bram_rdata_delay : tag_bram_rdata;
            p3_data_bram_rdata <= bram_rdata_delay ? data_bram_rdata_delay : data_bram_rdata;
            p3_cacop_way <= p2_cacop_way;
            p3_cacop_op_mode0 <= p2_cacop_op_mode0;
            p3_cacop_op_mode1 <= p2_cacop_op_mode1;
            p3_cacop_op_mode2 <= p2_cacop_op_mode2;
            p3_cacop_op_mode2_hit <= bram_rdata_delay ? p2_cacop_op_mode2_hit_r : p2_cacop_op_mode2_hit;
        end
    end


    // P3 comb
    assign p3_cpu_wreq = p3_wstrb != 4'b0;

    // P3 hit
    always_comb begin: p3_hit_comb
        p3_hit = 0;
        p3_hit_data = 0;
        for (integer i = 0; i < NWAY; i++) begin
            if (p3_tag_hit[i]) begin
                p3_hit = 1;
                p3_hit_data = p3_data_bram_rdata[i];
            end
        end
        // FIFO hit override
        if (fifo_r_hit & ~p3_uncache_en) begin
            p3_hit = 1;
            p3_hit_data = fifo_rdata;
        end
    end
    // Select P3 refill data
    always_comb begin : p3_refill_data_comb
        wreq_sel_data  = 0;
        p3_refill_data = 0;
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
            2'b00: p3_refill_data = {axi_data_i[127:32], wreq_sel_data};
            2'b01: p3_refill_data = {axi_data_i[127:64], wreq_sel_data, axi_data_i[31:0]};
            2'b10: p3_refill_data = {axi_data_i[127:96], wreq_sel_data, axi_data_i[63:0]};
            2'b11: p3_refill_data = {wreq_sel_data, axi_data_i[95:0]};
            default: begin
            end
        endcase
    end
    // CACOP writeback
    always_comb begin : p3_cacop_writeback_comb
        p3_cacop_writeback_valid = 0;
        p3_cacop_writeback_waddr = 0;
        p3_cacop_writeback_wdata = 0;
        if (p3_cacop & ~cpu_flush) begin
            for (integer i = 0; i < NWAY; i++) begin
                // write the invalidate cacheline back to mem
                // cacop mode == 1 write back if valid
                // cacop mode == 2 write back when hit
                if (p3_cacop_way == i[NWAY_WIDTH-1:0] && p3_cacop_op_mode1 && p3_tag_bram_rdata[i][TAG_WIDTH]) begin
                    p3_cacop_writeback_valid = 1;
                    p3_cacop_writeback_waddr = {
                        p3_tag_bram_rdata[i][TAG_WIDTH-1:0],
                        p3_paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH],
                        4'b0
                    };
                    p3_cacop_writeback_wdata = p3_data_bram_rdata[i];
                end else if (p3_cacop_op_mode2_hit[i]) begin
                    p3_cacop_writeback_valid = 1;
                    p3_cacop_writeback_waddr = {
                        p3_tag_bram_rdata[i][TAG_WIDTH-1:0],
                        p3_paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH],
                        4'b0
                    };
                    p3_cacop_writeback_wdata = p3_data_bram_rdata[i];
                end
            end
        end
    end

    ///////////////////////////////////////////////////////////////////////////////////
    // Stage 3 END
    ///////////////////////////////////////////////////////////////////////////////////

    always_comb begin 
        write_back_req = 0;
        case (state)
            READ_WAIT,WRITE_WAIT:begin
                for (integer i = 0; i < NWAY; i++) begin
                    if (axi_rvalid_i | axi_rrdy_i) begin
                            write_back_req = 1;
                        end 
                    end
                end
            default: begin     
            end
        endcase
    end

    // write back to memory
    always_ff @(posedge clk) begin : write_back_ff
        // fifo_wreq = 0;
        // fifo_waddr = 0;
        // fifo_wdata = 0;
        // fifo_wreq_sel_data = 0;
            case(state)
            // IDLE: begin
            //     // If a write request hit the cacheline in the fifo 
            //     // then rewrite the cacheline in the fifo. 
            //     // Must check request since FIFO write has side effect
            //     if (fifo_r_hit & p3_cpu_wreq & ~p3_uncache_en & ~cpu_flush & mem_valid) begin
            //         fifo_wreq = 1;
            //         fifo_waddr = p3_paddr;
            //         fifo_wdata = fifo_rdata;
            //         fifo_wreq_sel_data = 0;
            //         case (p3_paddr[3:2])
            //             2'b00: fifo_wreq_sel_data = fifo_wdata[31:0];
            //             2'b01: fifo_wreq_sel_data = fifo_wdata[63:32];
            //             2'b10: fifo_wreq_sel_data = fifo_wdata[95:64];
            //             2'b11: fifo_wreq_sel_data = fifo_wdata[127:96];
            //         endcase
            //         case (p3_wstrb)
            //             //st.b 
            //             4'b0001: fifo_wreq_sel_data[7:0] = p3_wdata[7:0];
            //             4'b0010: fifo_wreq_sel_data[15:8] = p3_wdata[15:8];
            //             4'b0100: fifo_wreq_sel_data[23:16] = p3_wdata[23:16];
            //             4'b1000: fifo_wreq_sel_data[31:24] = p3_wdata[31:24];
            //             //st.h
            //             4'b0011: fifo_wreq_sel_data[15:0] = p3_wdata[15:0];
            //             4'b1100: fifo_wreq_sel_data[31:16] = p3_wdata[31:16];
            //             //st.w
            //             4'b1111: fifo_wreq_sel_data = p3_wdata;
            //         endcase
            //         case (p3_paddr[3:2])
            //             2'b00: fifo_wdata[31:0] = fifo_wreq_sel_data;
            //             2'b01: fifo_wdata[63:32] = fifo_wreq_sel_data;
            //             2'b10: fifo_wdata[95:64] = fifo_wreq_sel_data;
            //             2'b11: fifo_wdata[127:96] = fifo_wreq_sel_data;
            //         endcase
            //     end
            // end
            // if the selected way is dirty,then sent the cacheline to the fifo
            READ_WAIT,WRITE_WAIT:begin
                for (integer i = 0; i < NWAY; i++) begin
                    if (axi_rvalid_i | axi_rrdy_i) begin
                        // NOTICE: must be the same cycle as BRAM write
                        // to ensure random state is the same
                        if (i[NWAY_WIDTH-1:0] == random_r[NWAY_WIDTH-1:0] && p3_tag_bram_rdata[i][TAG_WIDTH + 1] ) begin
                            write_back_addr <= {
                                 p3_tag_bram_rdata[i][TAG_WIDTH-1:0],
                                 p3_paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH],
                                 4'b0
                             };
                             write_back_data <= p3_data_bram_rdata[i];
                            // fifo_wreq = 1;
                            // fifo_waddr = {
                            //     p3_tag_bram_rdata[i][TAG_WIDTH-1:0],
                            //     p3_paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH],
                            //     4'b0
                            // };
                            // fifo_wdata = p3_data_bram_rdata[i];
                        end
                    end
                end
            end
            WRITE_BACK_WAIT:begin
                if(axi_bvalid_i)begin
                    write_back_addr <= 0;
                    write_back_data <= 0;
                end
            end
        endcase
    end

    // BRAM write
    always_comb begin : bram_write_comb
        // Default 0
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
                    // If write hit, then write the hit line, if miss then don't write
                    // Must validated the request since BRAM write has side effect
                    if (p3_valid & p3_tag_hit[i] & p3_cpu_wreq & ~cpu_flush & mem_valid) begin
                        tag_bram_we[i] = 1;
                        tag_bram_waddr[i] = p3_paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                        // make the dirty bit 1'b1
                        tag_bram_wdata[i] = {
                            1'b1, 1'b1, p3_paddr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_WIDTH]
                        };
                        data_bram_waddr[i] = p3_paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
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
                        endcase
                    end
                    else if (p3_cacop & ~cpu_flush & mem_valid) begin
                        if (p3_cacop_op_mode0 | p3_cacop_op_mode1) begin
                            if ((p3_cacop_way == i[NWAY_WIDTH-1:0])) begin
                                tag_bram_we[i] = 1;
                                tag_bram_waddr[i] = p3_paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                                tag_bram_wdata[i] = 0;
                            end
                        end else if (p3_cacop_op_mode2_hit[i]) begin
                            tag_bram_we[i] = 1;
                            tag_bram_waddr[i] = p3_paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                            tag_bram_wdata[i] = 0;
                        end
                    end
                end
            end
            WRITE_WAIT, READ_WAIT: begin // Refill
                for (integer i = 0; i < NWAY; i++) begin
                    // select a line to write back 
                    if (axi_rvalid_i | axi_rrdy_i) begin
                        // Ensure FIFO is not full
                        // And FIFO write is same cycle as BRAM write
                        if (i[NWAY_WIDTH-1:0] == random_r[NWAY_WIDTH-1:0] && ~fifo_full) begin
                            tag_bram_we[i] = 1;
                            tag_bram_waddr[i] = p3_paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                            //make the dirty bit 1'b1
                            tag_bram_wdata[i] = {
                                1'b1, 1'b1, p3_paddr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_WIDTH]
                            };
                            data_bram_we[i] = 16'b1111_1111_1111_1111;
                            data_bram_waddr[i] = p3_paddr[OFFSET_WIDTH+NSET_WIDTH-1:OFFSET_WIDTH];
                            data_bram_wdata[i] = p3_refill_data;
                        end
                    end
                end
            end
        endcase
    end

    // AXI handshake
    always_comb begin : axi_handshake_comb
        fifo_w_accept = 0;  // which used to tell fifo if it can send data to axi
        axi_wreq_o = 0;
        axi_rreq_o = 0;
        axi_addr_o = 0;
        axi_size_o = 0;
        axi_wdata_o = 0;
        axi_uncached_o = 0;
        axi_wstrb_o = 0;
        case (state)
            // IDLE: begin
            //     // if the state is idle, then the dcache is free
            //     // so send the wdata in fifo to axi when axi is free
            //     if (axi_wrdy_i & !fifo_state[0] & fifo_axi_wr_req) begin
            //         axi_wreq_o = 1;
            //         fifo_w_accept = 1;
            //         axi_size_o = 3'b100;
            //         axi_addr_o = fifo_axi_wr_addr;
            //         axi_wdata_o = fifo_axi_wr_data;
            //         axi_wstrb_o = 16'b1111_1111_1111_1111;
            //     end
            // end
            READ_REQ, WRITE_REQ: begin
                //if the axi is free then send the read request
                if (axi_rrdy_i) begin
                    axi_rreq_o = 1;
                    axi_size_o = 3'b100;
                    axi_addr_o = {p3_paddr[31:4], 4'b0};
                end
            end
            WRITE_BACK_REQ: begin
                // If write channel is free, can send write request
                // necessary because refill wait on FIFO full
                // allow fifo send request to avoid deadlock
                if (axi_rvalid_i | axi_rrdy_i) begin
                    axi_wreq_o = 1;
                    fifo_w_accept = 1;
                    axi_size_o = 3'b100;
                    axi_addr_o = write_back_addr;
                    axi_wdata_o = write_back_data;
                    axi_wstrb_o = 16'b1111_1111_1111_1111;
                end
            end
            UNCACHE_READ_REQ: begin
                if (axi_rrdy_i) begin
                    axi_rreq_o = 1;
                    axi_uncached_o = 1;
                    axi_size_o = p3_req_type;
                    axi_addr_o = p3_paddr;
                end
            end
            UNCACHE_WRITE_REQ: begin
                if (axi_wrdy_i) begin
                    axi_wreq_o = 1;
                    axi_uncached_o = 1;
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
            CACOP_REQ: begin
                if (axi_wrdy_i) begin
                    axi_wreq_o = 1;
                    axi_uncached_o = 1;
                    axi_size_o = 3'b100;
                    axi_addr_o = p3_cacop_writeback_waddr;
                    axi_wdata_o = p3_cacop_writeback_wdata;
                    axi_wstrb_o = 16'b1111_1111_1111_1111;
                end
            end
        endcase

    end 

    // CPU handshake
    always_comb begin : cpu_handshake_comb
        data_ok = 0;
        rdata   = 0;
        case (state)
            IDLE: begin
                if ((p3_valid & p3_hit) | (p3_cacop & ~p3_cacop_writeback_valid)) begin
                    data_ok = 1;
                    rdata   = p3_hit_data[p3_paddr[3:2]*32+:32];
                end
            end
            READ_WAIT, WRITE_WAIT: begin
                if ((axi_rvalid_i | axi_rrdy_i) & ~fifo_full) begin
                    // Return data the same cycle as FIFO & BRAM write
                    data_ok = 1;
                    rdata   = axi_data_i[p3_paddr[3:2]*32+:32];
                end
            end
            UNCACHE_READ_WAIT: begin
                if (axi_rvalid_i) begin
                    data_ok = 1;
                    rdata   = axi_data_i[p3_paddr[3:2]*32+:32];
                end
            end
            UNCACHE_WRITE_WAIT, CACOP_WAIT: begin
                if (axi_bvalid_i) begin
                    data_ok = 1;
                end
            end
        endcase
    end


    /////////////////////////////////////////////////////////////////////////////////
    // Implementation END
    /////////////////////////////////////////////////////////////////////////////////
    


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
        .axi_bvalid_i(axi_bvalid_i),
        .axi_req_accept(fifo_w_accept),
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


    axi_read_channel #(
        .ID(1)
    ) u_axi_read_channel (
        .clk        (clk),
        .rst        (rst),
        .new_request(axi_rreq_o),
        .uncached   (axi_uncached_o),
        .addr       (axi_addr_o),
        .size       (axi_size_o),
        .data_out   (axi_data_i),
        .ready_out  (axi_rrdy_i),
        .rvalid_out (axi_rvalid_i),
        .arready    (m_axi.arready),
        .arvalid    (m_axi.arvalid),
        .arid       (m_axi.arid),
        .arlen      (m_axi.arlen),
        .arburst    (m_axi.arburst),
        .arsize     (m_axi.arsize),
        .araddr     (m_axi.araddr),
        .arcache    (m_axi.arcache),
        .rready     (m_axi.rready),
        .rvalid     (m_axi.rvalid),
        .rlast      (m_axi.rlast),
        .rid        (m_axi.rid),
        .rdata      (m_axi.rdata),
        .rresp      (m_axi.rresp)
    );

    axi_write_channel #(
        .ID(1)
    ) u_axi_write_channel (
        .clk        (clk),
        .rst        (rst),
        .new_request(axi_wreq_o),
        .uncached   (axi_uncached_o),
        .addr       (axi_addr_o),
        .size       (axi_size_o),
        .data_in    (axi_wdata_o),
        .wstrb_in   (axi_wstrb_o),
        .ready_out  (axi_wrdy_i),
        .bvalid_out (axi_bvalid_i),
        .awready    (m_axi.awready),
        .awvalid    (m_axi.awvalid),
        .awid       (m_axi.awid),
        .awlen      (m_axi.awlen),
        .awburst    (m_axi.awburst),
        .awsize     (m_axi.awsize),
        .awaddr     (m_axi.awaddr),
        .awcache    (m_axi.awcache),
        .wready     (m_axi.wready),
        .wvalid     (m_axi.wvalid),
        .wlast      (m_axi.wlast),
        .wdata      (m_axi.wdata),
        .wstrb      (m_axi.wstrb),
        .wid        (),
        .bready     (m_axi.bready),
        .bvalid     (m_axi.bvalid),
        .bid        (m_axi.bid),
        .bresp      (m_axi.bresp)
    );

    // BRAM instantiation
    generate
        for (genvar i = 0; i < NWAY; i++) begin : bram_gen_blk
            dual_port_lutram #(
                .DATA_WIDTH     (TAG_BRAM_WIDTH),
                .DATA_DEPTH_EXP2(NSET_WIDTH)
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
                .DATA_DEPTH_EXP2(NSET_WIDTH)
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
        end
    endgenerate


endmodule
