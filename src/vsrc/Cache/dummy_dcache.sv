`include "core_config.sv"
`include "axi/axi_interface.sv"

module dummy_dcache
    import core_config::*;
(
    input logic clk,
    input logic rst,

    //cache与CPU流水线的交互接
    input logic valid,  //表明请求有效
    input logic [`RegBus] addr,
    input logic [3:0] wstrb,  //写字节使能信号
    input logic [31:0] wdata,  //写数据
    input logic [2:0] rd_type_i, //读请求类型：3'b000: 字节；3'b001: 半字；3'b010: 字；3'b100：Cache行
    input logic [2:0] wr_type_i,
    input logic flush, // 冲刷信号，如果出于某种原因需要取消写事务，CPU拉高此信号
    output logic cache_ready,
    output logic cache_ack,
    output logic addr_ok,             //该次请求的地址传输OK，读：地址被接收；写：地址和数据被接收
    output logic data_ok,             //该次请求的数据传输Ok，读：数据返回；写：数据写入完成
    output logic [31:0] rdata,  //读Cache的结果

    // axi_interface.master m_axi
);

    // AXI
    logic [ADDR_WIDTH-1:0] axi_addr_o;
    logic axi_req_o;
    logic axi_we_o;
    logic axi_rdy_i;
    logic axi_rvalid_i;
    logic axi_rlast_i;
    assign axi_rlast_i = axi_rvalid_i;
    logic [AXI_DATA_WIDTH-1:0] axi_data_i;
    logic [AXI_DATA_WIDTH-1:0] axi_wdata_o;
    logic [(AXI_DATA_WIDTH/8)-1:0] axi_wstrb_o;
    logic [2:0] rd_type;
    logic [2:0] wr_type;

    logic valid_buffer;
    logic op;
    logic op_buffer;
    logic [7:0] index_buffer;
    logic [19:0] tag_buffer;
    logic [3:0] offset_buffer;
    logic [3:0] wstrb_buffer;
    logic [31:0] wdata_buffer;
    logic [2:0] rd_type_buffer;
    logic [2:0] wr_type_buffer;

    logic flush;
    logic [31:0] cpu_addr;
    logic rd_req_r;
    logic [31:0] rd_addr_r;

    // State machine
    enum int {
        IDLE,
        LOOK_UP,
        READ_REQ,
        READ_WAIT,
        WRITE_REQ,
        WRITE_WAIT
    }
        state, next_state;
    assign cache_ready = state == IDLE && ~valid_buffer;
    assign op = wstrb == 4'b0;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // State transition
    always_comb begin : transition_comb
        case (state)
            IDLE: begin
                if (valid) next_state = LOOK_UP;
                else next_state = IDLE;
            end
            LOOK_UP: begin
                if (valid_buffer) begin
                    if (op_buffer & ~flush) next_state = WRITE_REQ;
                    else if (~op_buffer) next_state = READ_REQ;
                    else next_state = IDLE;
                end else next_state = IDLE;
            end
            READ_REQ: begin
                if (axi_rdy_i) next_state = READ_WAIT;  // If AXI ready, send request 
                else next_state = READ_REQ;
            end
            READ_WAIT: begin
                if (axi_rvalid_i) next_state = IDLE;  // If return valid, back to IDLE
                else next_state = READ_WAIT;
            end
            WRITE_REQ: begin
                // If AXI is ready, then write req is accept this cycle, back to IDLE
                // If flushed, back to IDLE
                if (axi_rdy_i) next_state = IDLE;
                else next_state = WRITE_REQ;
            end
            WRITE_WAIT: begin
                if (axi_rdy_i) next_state = IDLE;
                else next_state = WRITE_WAIT;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end



    always_ff @(posedge clk) begin : data_buffer
        if (rst) begin
            valid_buffer <= 0;
            op_buffer <= 0;
            index_buffer <= 0;
            tag_buffer <= 0;
            offset_buffer <= 0;
            wstrb_buffer <= 0;
            wdata_buffer <= 0;
            rd_type_buffer <= 0;
            wr_type_buffer <= 0;
        end else if (flush & state != WRITE_REQ) begin
            valid_buffer <= 0;
            op_buffer <= 0;
            index_buffer <= 0;
            tag_buffer <= 0;
            offset_buffer <= 0;
            wstrb_buffer <= 0;
            wdata_buffer <= 0;
            rd_type_buffer <= 0;
            wr_type_buffer <= 0;
        end else if (valid & cache_ack) begin  // not accept new request while working
            valid_buffer <= valid;
            op_buffer <= op;
            index_buffer <= addr[11:4];
            tag_buffer <= addr[31:12];
            offset_buffer <= addr[3:0];
            wstrb_buffer <= wstrb;
            wdata_buffer <= wdata;
            rd_type_buffer <= rd_type_i;
            wr_type_buffer <= wr_type_i;
        end else if (next_state == IDLE) begin  //means that cache will finish work,so flush the buffered signal
            valid_buffer   <= 0;
            op_buffer      <= 0;
            index_buffer   <= 0;
            tag_buffer     <= 0;
            offset_buffer  <= 0;
            wstrb_buffer   <= 0;
            wdata_buffer   <= 0;
            rd_type_buffer <= 0;
            wr_type_buffer <= 0;
        end else begin
            valid_buffer <= valid_buffer;
            op_buffer <= op_buffer;
            index_buffer <= index_buffer;
            tag_buffer <= tag_buffer;
            offset_buffer <= offset_buffer;
            wstrb_buffer <= wstrb_buffer;
            wdata_buffer <= wdata_buffer;
            rd_type_buffer <= rd_type_buffer;
            wr_type_buffer <= wr_type_buffer;
        end
    end

    always_comb begin
        if (rst) cache_ack = 0;
        else if (state == IDLE) cache_ack = valid;
        else cache_ack = 0;
    end

    assign cpu_addr = addr;


    // Handshake with AXI
    always_ff @(posedge clk) begin
        case (state)
            READ_REQ: begin
                if (axi_rdy_i) begin
                    rd_req_r  <= 1;
                    rd_addr_r <= cpu_addr;
                end
            end
        endcase
    end


    assign rd_type =  rd_type_buffer ;
    assign wr_type =  wr_type_buffer ;
    always_comb begin
        // Default signal
        axi_addr_o = 0;
        axi_req_o = 0;
        axi_we_o = 0;
        axi_wdata_o = 0;
        axi_wstrb_o = 0;

        case (state)
            READ_REQ: begin
                if (axi_rdy_i) begin
                    axi_req_o  = 1;
                    axi_addr_o = cpu_addr;
                end
            end
            READ_WAIT: begin
            end
            WRITE_REQ: begin
                if (axi_rdy_i) begin
                    axi_req_o = 1;
                    axi_we_o = 1;
                    axi_addr_o =  cpu_addr;  // DO NOT align addr, 128b -> 32b translate need info from addr

                    case (cpu_addr[3:2])
                        2'b00: begin
                            axi_wdata_o = {{96{1'b0}}, wdata_buffer};
                            axi_wstrb_o = {12'b0, wstrb_buffer};
                        end
                        2'b01: begin
                            axi_wdata_o = {{64{1'b0}}, wdata_buffer, {32{1'b0}}};
                            axi_wstrb_o = {8'b0, wstrb_buffer, 4'b0};
                        end
                        2'b10: begin
                            axi_wdata_o = {32'b0, wdata_buffer, {64{1'b0}}};
                            axi_wstrb_o = {4'b0, wstrb_buffer, 8'b0};
                        end
                        2'b11: begin
                            axi_wdata_o = {wdata_buffer, {96{1'b0}}};
                            axi_wstrb_o = {wstrb_buffer, 12'b0};
                        end
                    endcase
                end
            end
        endcase
    end

    // Handshake with CPU
    always_comb begin
        addr_ok = 0;
        data_ok = 0;
        rdata   = 0;
        case (state)
            READ_WAIT: begin
                if (axi_rvalid_i) begin
                    addr_ok = 1;
                    data_ok = 1;
                    rdata   = axi_data_i[rd_addr_r[3:2]*32+:32];
                end
            end
            WRITE_REQ: begin
                if (axi_rdy_i) begin
                    addr_ok = 1;
                    data_ok = 1;
                end
            end
        endcase
    end

    axi_master u_axi_master (
        .clk        (clk),
        .rst        (rst),
        .m_axi      (m_axi),
        .new_request(axi_req_o),
        .we         (axi_we_o),
        .addr       (axi_addr_o),
        .size       (axi_we_o ? wr_type : rd_type),
        .data_in    (axi_wdata_o),
        .wstrb      (axi_wstrb_o),
        .ready_out  (axi_rdy_i),
        .valid_out  (axi_rvalid_i),
        .data_out   (axi_data_i)
    );

endmodule
