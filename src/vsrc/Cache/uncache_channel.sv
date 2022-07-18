`include "core_config.sv"
`include "axi/axi_interface.sv"

module uncache_channel
    import core_config::*;
(
    input logic clk,
    input logic rst,

    //cache与CPU流水线的交互接
    input logic valid,  //表明请求有效
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [2:0] req_type, //请求类型：3'b000: 字节；3'b001: 半字；3'b010: 字；3'b100：Cache行
    input logic [3:0] wstrb,  //写字节使能信号
    input logic [31:0] wdata,  //写数据
    output logic [31:0] rdata,  //读Cache的结果
    output logic cache_ready,
    output logic data_ok,             //该次请求的数据传输Ok，读：数据返回；写：数据写入完成

    axi_interface.master m_axi
);

    // AXI
    logic [ADDR_WIDTH-1:0] axi_addr_o;
    logic axi_req_o;
    logic axi_we_o;
    logic axi_rdy_i;
    logic axi_rvalid_i;
    logic [AXI_DATA_WIDTH-1:0] axi_data_i;
    logic [AXI_DATA_WIDTH-1:0] axi_wdata_o;
    logic [(AXI_DATA_WIDTH/8)-1:0] axi_wstrb_o;

    logic valid_buffer;
    logic op;
    logic op_buffer;
    logic [7:0] index_buffer;
    logic [19:0] tag_buffer;
    logic [3:0] offset_buffer;
    logic [3:0] wstrb_buffer;
    logic [31:0] wdata_buffer;
    logic [2:0] req_type_buffer;

    logic [31:0] cpu_addr;

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
    assign op = ~(wstrb == 0);

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
                    if (op_buffer) next_state = WRITE_REQ;
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
            req_type_buffer <= 0;
        end else if (valid) begin  // not accept new request while working
            valid_buffer <= valid;
            op_buffer <= op;
            index_buffer <= addr[11:4];
            tag_buffer <= addr[31:12];
            offset_buffer <= addr[3:0];
            wstrb_buffer <= wstrb;
            wdata_buffer <= wdata;
            req_type_buffer <= req_type;
        end else if (next_state == IDLE) begin  //means that cache will finish work,so flush the buffered signal
            valid_buffer    <= 0;
            op_buffer       <= 0;
            index_buffer    <= 0;
            tag_buffer      <= 0;
            offset_buffer   <= 0;
            wstrb_buffer    <= 0;
            wdata_buffer    <= 0;
            req_type_buffer <= 0;
        end else begin
            valid_buffer <= valid_buffer;
            op_buffer <= op_buffer;
            index_buffer <= index_buffer;
            tag_buffer <= tag_buffer;
            offset_buffer <= offset_buffer;
            wstrb_buffer <= wstrb_buffer;
            wdata_buffer <= wdata_buffer;
            req_type_buffer <= req_type_buffer;
        end
    end

    assign cpu_addr = {tag_buffer, index_buffer, offset_buffer};

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
        data_ok = 0;
        rdata   = 0;
        case (state)
            READ_WAIT: begin
                if (axi_rvalid_i) begin
                    data_ok = 1;
                    rdata   = axi_data_i[cpu_addr[3:2]*32+:32];
                end
            end
            WRITE_REQ: begin
                if (axi_rdy_i) begin
                    data_ok = 1;
                end
            end
        endcase
    end

    axi_master #(
        .ID(1)
    ) u_axi_master (
        .clk        (clk),
        .rst        (rst),
        .m_axi      (m_axi),
        .new_request(axi_req_o),
        .we         (axi_we_o),
        .addr       (axi_addr_o),
        .size       (req_type_buffer),
        .data_in    (axi_wdata_o),
        .wstrb      (axi_wstrb_o),
        .ready_out  (axi_rdy_i),
        .valid_out  (axi_rvalid_i),
        .data_out   (axi_data_i)
    );

endmodule
