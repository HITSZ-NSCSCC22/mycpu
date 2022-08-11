`include "core_config.sv"
`include "defines.sv"
`include "utils/lutram_1w_mr.sv"

module dcache_fifo
    import core_config::*;
(
    input clk,
    input rst,
    //CPU write request
    input logic cpu_wreq_i,
    input logic [`DataAddrBus] cpu_awaddr_i,
    input logic [DCACHELINE_WIDTH-1:0] cpu_wdata_i,
    output logic write_hit_o,
    //CPU read request and response
    input logic cpu_rreq_i,
    input logic [`DataAddrBus] cpu_araddr_i,
    output logic read_hit_o,
    output logic [DCACHELINE_WIDTH-1:0] cpu_rdata_o,
    //FIFO state
    output logic [1:0] state,
    //write to memory 
    input logic axi_bvalid_i,
    output logic axi_wen_o,
    output logic [DCACHELINE_WIDTH-1:0] axi_wdata_o,
    output logic [`DataAddrBus] axi_awaddr_o

);

    // Parameters 
    localparam DEPTH = DCACHE_FIFO_DEPTH;

    //store  addr
    logic [DEPTH-1:0][`RegBus] addr_queue;


    logic [$clog2(DEPTH)-1:0] head, tail;
    logic [DEPTH-1:0] queue_valid;

    logic full, empty;

    logic [`DataAddrBus] cpu_awaddr;
    logic [`DataAddrBus] cpu_araddr;

    logic [DEPTH-1:0] read_hit, write_hit, write_not_hit_head;

    logic queue_wreq;
    logic [$clog2(DEPTH)-1:0] queue_waddr, queue_raddr;
    logic [DCACHELINE_WIDTH-1:0] queue_wdata;

    assign state = {full, empty};

    assign full = queue_valid[tail] == 1'b1;
    assign empty = queue_valid[head] == 1'b0;

    // read and write the cacheline don't use the offset
    assign cpu_awaddr = {cpu_awaddr_i[31:4], 4'h0};

    assign cpu_araddr = {cpu_araddr_i[31:4], 4'h0};


    always_ff @(posedge clk) begin
        if (rst) begin
            head <= 0;
            tail <= 0;
            queue_valid <= 0;
        end  //if dcache sent a new data which don't hit 
             //put it at the tail of the queue
        if (cpu_wreq_i == `WriteEnable && write_hit_o == 1'b0) begin
            if (tail == DEPTH[$clog2(DEPTH)-1:0] - 1) begin
                tail <= 0;
            end else begin
                tail <= tail + 1;
            end
            queue_valid[tail] <= 1'b1;
        end  // if axi is free and there is not write collsion then sent the data
        if (axi_bvalid_i && queue_valid[head]) begin
            queue_valid[head] <= 1'b0;
            if (head == DEPTH[$clog2(DEPTH)-1:0] - 1) begin
                head <= 0;
            end else begin
                head <= head + 1;
            end
        end
    end

    //Read Hit
    assign read_hit_o = |read_hit;
    always_ff @(posedge clk) begin
        for (integer i = 0; i < DEPTH; i = i + 1) begin
            if (cpu_rreq_i)
                read_hit[i] <= ((cpu_araddr[31:4] == addr_queue[i][31:4]) && queue_valid[i]) ? 1'b1 : 1'b0;
            else read_hit[i] <= 0;
        end
    end


    //Read hit
    always_comb begin
        if (rst) queue_raddr = 0;
        else if (read_hit_o) begin
            queue_raddr = 0;
            for (integer i = 0; i < DEPTH; i = i + 1) begin
                if (read_hit[i]) queue_raddr = i[$clog2(DEPTH)-1:0];
            end
        end else queue_raddr = 0;
    end


    //Write Hit
    assign write_hit_o = |write_not_hit_head;
    always_comb begin
        for (integer i = 0; i < DEPTH; i = i + 1) begin
            write_hit[i] = ((cpu_awaddr[31:4] == addr_queue[i][31:4]) && queue_valid[i]) ? 1'b1 : 1'b0;
            write_not_hit_head[i] = (axi_bvalid_i && head == i[$clog2(DEPTH)-1:0]) ? 1'b0 :
                write_hit[i];
        end
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            addr_queue <= 0;
        end else if (cpu_wreq_i & !write_hit_o) begin
            addr_queue[tail] <= cpu_awaddr;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            queue_wreq  <= 0;
            queue_waddr <= 0;
            queue_wdata <= 0;
        end else if (cpu_wreq_i) begin
            if (write_hit_o) begin
                for (integer i = 0; i < DEPTH; i = i + 1) begin
                    if (write_not_hit_head[i] == 1'b1) begin
                        queue_wreq  <= 1;
                        queue_waddr <= i[$clog2(DEPTH)-1:0];
                        queue_wdata <= cpu_wdata_i;
                    end
                end
            end else begin
                queue_wreq  <= 1;
                queue_waddr <= tail;
                queue_wdata <= cpu_wdata_i;
            end
        end
    end


    assign axi_wen_o = !empty & axi_bvalid_i & queue_valid[head];
    assign axi_awaddr_o = addr_queue[head];

    lutram_1w_mr #(
        .WIDTH(DCACHELINE_WIDTH),
        .DEPTH(DEPTH),
        .NUM_READ_PORTS(2)
    ) mem_queue (
        .clk(clk),

        .waddr(queue_waddr),
        .raddr({queue_raddr, head}),

        .ram_write(queue_wreq),
        .new_ram_data(queue_wdata),
        .ram_data_out({cpu_rdata_o, axi_wdata_o})
    );


endmodule
