`include "Cache/dcache_config.sv"
module cache_control
    import dcache_config::*;
(
    input                        clk,
    input                        reset,
    input                        valid,
    input      [CTRL_ADDR_W-1:0] addr,
    input                        wtbuf_full,
    input                        wtbuf_empty,
    input                        write_hit,
    input                        write_miss,
    input                        read_hit,
    input                        read_miss,
    output reg [  FE_DATA_W-1:0] rdata,
    output reg                   ready,
    output reg                   invalidate
);

    generate
        if (CTRL_CNT) begin

            reg [FE_DATA_W-1:0] read_hit_cnt, read_miss_cnt, write_hit_cnt, write_miss_cnt;
            wire [FE_DATA_W-1:0] hit_cnt, miss_cnt;
            reg counter_reset;

            assign hit_cnt  = read_hit_cnt + write_hit_cnt;
            assign miss_cnt = read_miss_cnt + write_miss_cnt;

            always @(posedge clk, posedge reset) begin
                if (reset) begin
                    read_hit_cnt   <= {FE_DATA_W{1'b0}};
                    read_miss_cnt  <= {FE_DATA_W{1'b0}};
                    write_hit_cnt  <= {FE_DATA_W{1'b0}};
                    write_miss_cnt <= {FE_DATA_W{1'b0}};
                end else begin
                    if (counter_reset) begin
                        read_hit_cnt   <= {FE_DATA_W{1'b0}};
                        read_miss_cnt  <= {FE_DATA_W{1'b0}};
                        write_hit_cnt  <= {FE_DATA_W{1'b0}};
                        write_miss_cnt <= {FE_DATA_W{1'b0}};
                    end else if (read_hit) begin
                        read_hit_cnt <= read_hit_cnt + 1;
                    end else if (write_hit) begin
                        write_hit_cnt <= write_hit_cnt + 1;
                    end else if (read_miss) begin
                        read_miss_cnt <= read_miss_cnt + 1;
                        read_hit_cnt  <= read_hit_cnt - 1;
                    end else if (write_miss) begin
                        write_miss_cnt <= write_miss_cnt + 1;
                    end else begin
                        read_hit_cnt   <= read_hit_cnt;
                        read_miss_cnt  <= read_miss_cnt;
                        write_hit_cnt  <= write_hit_cnt;
                        write_miss_cnt <= write_miss_cnt;
                    end
                end  // else: !if(ctrl_arst)   
            end  // always @ (posedge clk, posedge ctrl_arst)

            always @(posedge clk) begin
                rdata <= {FE_DATA_W{1'b0}};
                invalidate <= 1'b0;
                counter_reset <= 1'b0;
                ready <= valid; // Sends acknowlege the next clock cycle after request (handshake)               
                if (valid)
                    if (addr == 3) rdata <= hit_cnt;
                    else if (addr == 4) rdata <= miss_cnt;
                    else if (addr == 5) rdata <= read_hit_cnt;
                    else if (addr == 6) rdata <= read_miss_cnt;
                    else if (addr == 7) rdata <= write_hit_cnt;
                    else if (addr == 8) rdata <= write_miss_cnt;
                    else if (addr == 9) counter_reset <= 1'b1;
                    else if (addr == 10) invalidate <= 1'b1;
                    else if (addr == 1) rdata <= wtbuf_empty;
                    else if (addr == 2) rdata <= wtbuf_full;
            end  // always @ (posedge clk)
        end // if (CTRL_CNT)
      else
        begin

            always @(posedge clk) begin
                rdata <= {FE_DATA_W{1'b0}};
                invalidate <= 1'b0;
                ready <= valid; // Sends acknowlege the next clock cycle after request (handshake)               
                if (valid)
                    if (addr == 10) invalidate <= 1'b1;
                    else if (addr == 1) rdata[0] <= wtbuf_empty;
                    else if (addr == 2) rdata[0] <= wtbuf_full;
            end
        end
    endgenerate

endmodule
