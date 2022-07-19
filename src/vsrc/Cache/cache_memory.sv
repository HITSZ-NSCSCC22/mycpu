`timescale 1ns / 1ps
`include "Cache/dcache_config.sv"
`include "Cache/iob_ram_sp.sv"
`include "Cache/onehot_to_bin.sv"
`include "Cache/replacement_policy.sv"

module cache_memory
    import dcache_config::*;
(
    input clk,
    input reset,
    //front-end
    input valid,
    input [FE_ADDR_W-1:BE_BYTE_W + LINE2MEM_W] addr,
    output [FE_DATA_W-1:0] rdata,
    output ready,
    //stored input value
    input valid_reg,
    input [FE_ADDR_W-1:FE_BYTE_W] addr_reg,
    input [FE_DATA_W-1:0] wdata_reg,
    input [FE_NBYTES-1:0] wstrb_reg,
    //back-end write-channel
    output write_valid,
    output [FE_ADDR_W-1:FE_BYTE_W + WRITE_POL*WORD_OFF_W] write_addr,
    output [FE_DATA_W + WRITE_POL*(FE_DATA_W*(2**WORD_OFF_W)-FE_DATA_W)-1 :0] write_wdata,//write-through[FE_DATA_W]; write-back[FE_DATA_W*2**WORD_OFF_W]
    output [FE_NBYTES-1:0] write_wstrb,
    input write_ready,
    //back-end read-channel
    output replace_valid,
    output [FE_ADDR_W -1:BE_BYTE_W+LINE2MEM_W] replace_addr,
    input replace,
    input read_valid,
    input [LINE2MEM_W-1:0] read_addr,
    input [BE_DATA_W-1:0] read_rdata,
    //cache-control
    input invalidate,
    output wtbuf_full,
    output wtbuf_empty,
    output write_hit,
    output write_miss,
    output read_hit,
    output read_miss
);

    localparam TAG_W = FE_ADDR_W - (FE_BYTE_W + WORD_OFF_W + LINE_OFF_W);

    logic hit;

    //cache-memory internal signals
    logic [N_WAYS-1:0] way_hit, way_select;

    logic [TAG_W-1:0]                                                            tag       = addr_reg[FE_ADDR_W-1       -:TAG_W     ]; //so the tag doesnt update during ready on a read-access, losing the current hit status (can take the 1 clock-cycle delay)
    logic [LINE_OFF_W-1:0]                                                       index     = addr    [FE_ADDR_W-TAG_W-1 -:LINE_OFF_W];//cant wait, doesnt update during a write-access
    logic [LINE_OFF_W-1:0]                                                       index_reg = addr_reg[FE_ADDR_W-TAG_W-1 -:LINE_OFF_W];//cant wait, doesnt update during a write-access
    logic [WORD_OFF_W-1:0]                                                       offset    = addr_reg[FE_BYTE_W         +:WORD_OFF_W]; //so the offset doesnt update during ready on a read-access (can take the 1 clock-cycle delay)

    logic [N_WAYS*(2**WORD_OFF_W)*FE_DATA_W-1:0] line_rdata;
    logic [N_WAYS*TAG_W-1:0] line_tag;
    reg [N_WAYS*(2**LINE_OFF_W)-1:0] v_reg;
    reg [N_WAYS-1:0] v;

    reg [(2**WORD_OFF_W)*FE_NBYTES-1:0] line_wstrb;

    logic write_access = |wstrb_reg & valid_reg;
    logic                                                                        read_access = ~|wstrb_reg & valid_reg;//signal mantains the access 1 addition clock-cycle after ready is asserted

    //back-end write channel
    logic buffer_empty, buffer_full;
    logic [FE_NBYTES+(FE_ADDR_W-FE_BYTE_W)+(FE_DATA_W)-1:0] buffer_dout;

    //for write-back write-allocate only
    reg   [                                     N_WAYS-1:0] dirty;
    reg   [                     N_WAYS*(2**LINE_OFF_W)-1:0] dirty_reg;


    // if (WRITE_POL == WRITE_BACK)

    //back-end write channel
    assign write_wstrb = {FE_NBYTES{1'bx}};
    //write_valid, write_addr and write_wdata assigns are generated bellow (dependencies)

    //back-end read channel
    assign replace_valid = (~|way_hit) & (write_ready) & valid_reg & ~replace;
    assign replace_addr = addr[FE_ADDR_W-1:BE_BYTE_W+LINE2MEM_W];

    //buffer status (non-existant)
    assign wtbuf_full = 1'b0;
    assign wtbuf_empty = 1'b1;



    //////////////////////////////////////////////////////
    // Read-After-Write (RAW) Hazard (pipeline) control
    //////////////////////////////////////////////////////
    logic                  raw;
    reg                    write_hit_prev;
    reg   [WORD_OFF_W-1:0] offset_prev;
    reg   [    N_WAYS-1:0] way_hit_prev;

    //// if (WRITE_POL == WRITE_BACK)
    always @(posedge clk) begin
        write_hit_prev <= write_access;  //all writes will have the data in cache in the end
        //previous write position
        offset_prev <= offset;
        way_hit_prev <= way_hit;
    end
    assign raw = write_hit_prev & (way_hit_prev == way_hit) & (offset_prev == offset) & read_access; //without read_access it is an infinite replacement loop

    ///////////////////////////////////////////////////////////////
    // Hit signal: data available and in the memory's output
    ///////////////////////////////////////////////////////////////
    assign hit = |way_hit & ~replace & (~raw);


    /////////////////////////////////
    //front-end READY signal
    /////////////////////////////////

    // if (WRITE_POL == WRITE_BACK)
    assign ready = hit & valid_reg;


    //cache-control hit-miss counters enables
    generate
        if (CTRL_CACHE & CTRL_CNT) begin
            //cache-control hit-miss counters enables
            assign write_hit  = ready & (hit & write_access);
            assign write_miss = ready & (~hit & write_access);
            assign read_hit   = ready & (hit & read_access);
            assign read_miss  = replace_valid;  //will also subtract read_hit
        end else begin
            assign write_hit  = 1'bx;
            assign write_miss = 1'bx;
            assign read_hit   = 1'bx;
            assign read_miss  = 1'bx;
        end  // else: !if(CACHE_CTRL & CTRL_CNT)
    endgenerate


    ////////////////////////////////////////
    //Memories implementation configurations
    ////////////////////////////////////////
    genvar i, j, k;
    generate

        //Data-Memory
        for (k = 0; k < N_WAYS; k = k + 1) begin : n_ways_block
            for (j = 0; j < 2 ** LINE2MEM_W; j = j + 1) begin : line2mem_block
                for (i = 0; i < BE_DATA_W / FE_DATA_W; i = i + 1) begin : BE_FE_block
                    iob_gen_sp_ram #(
                        .DATA_W(FE_DATA_W),
                        .ADDR_W(LINE_OFF_W)
                    ) cache_memory (
                        .clk(clk),
                        .en(valid),
                        .we ({FE_NBYTES{way_hit[k]}} & line_wstrb[(j*(BE_DATA_W/FE_DATA_W)+i)*FE_NBYTES +: FE_NBYTES]),
                        .addr((write_access & way_hit[k] & ((j*(BE_DATA_W/FE_DATA_W)+i) == offset))? index_reg : index),
                        .data_in((replace) ? read_rdata[i*FE_DATA_W+:FE_DATA_W] : wdata_reg),
                        .data_out(line_rdata[(k*(2**WORD_OFF_W)+j*(BE_DATA_W/FE_DATA_W)+i)*FE_DATA_W +: FE_DATA_W])
                    );
                end
            end
        end

        //Cache Line Write Strobe
        if (LINE2MEM_W > 0) begin
            always @*
                if (replace)
                    line_wstrb = {BE_NBYTES{read_valid}} << (read_addr*BE_NBYTES); //line-replacement: read_addr indexes the words in cache-line
                else line_wstrb = (wstrb_reg & {FE_NBYTES{write_access}}) << (offset * FE_NBYTES);
        end else begin
            always @*
                if (replace)
                    line_wstrb = {BE_NBYTES{read_valid}}; //line-replacement: mem's word replaces entire line
                else line_wstrb = (wstrb_reg & {FE_NBYTES{write_access}}) << (offset * FE_NBYTES);
        end  // else: !if(LINE2MEM_W > 0)

        // Valid-Tag memories & replacement-policy

        logic [NWAY_W-1:0]
            way_hit_bin, way_select_bin;  //reason for the 2 generates for single vs multiple ways
        //valid-memory
        always @(posedge clk, posedge reset) begin
            if (reset) v_reg <= 0;
            else if (invalidate) v_reg <= 0;
            else if (replace_valid)
                v_reg <= v_reg | (1 << (way_select_bin * (2 ** LINE_OFF_W) + index_reg));
            else v_reg <= v_reg;
        end

        for (k = 0; k < N_WAYS; k = k + 1) begin : tag_mem_block
            //valid-memory output stage register - 1 c.c. read-latency (cleaner simulation during rep.)
            always @(posedge clk)
                if (invalidate) v[k] <= 0;
                else v[k] <= v_reg[(2**LINE_OFF_W)*k+index];

            //tag-memory
            iob_ram_sp #(
                .DATA_W(TAG_W),
                .ADDR_W(LINE_OFF_W)
            ) tag_memory (
                .clk (clk),
                .en  (valid),
                .we  (way_select[k] & replace_valid),
                .addr(index),
                .din (tag),
                .dout(line_tag[TAG_W*k+:TAG_W])
            );


            //Way hit signal - hit or replacement
            assign way_hit[k] = (tag == line_tag[TAG_W*k+:TAG_W]) & v[k];
        end
        //Read Data Multiplexer
        assign rdata [FE_DATA_W-1:0] = line_rdata >> FE_DATA_W*(offset + (2**WORD_OFF_W)*way_hit_bin);


        //replacement-policy module
        replacement_policy replacement_policy_algorithm (
            .clk           (clk),
            .reset         (reset | invalidate),
            .write_en      (ready),
            .way_hit       (way_hit),
            .line_addr     (index_reg),
            .way_select    (way_select),
            .way_select_bin(way_select_bin)
        );

        //onehot-to-binary for way-hit
        onehot_to_bin #(
            .BIN_W(NWAY_W)
        ) way_hit_encoder (
            .onehot(way_hit[N_WAYS-1:1]),
            .bin   (way_hit_bin)
        );

        //dirty-memory
        always @(posedge clk, posedge reset) begin
            if (reset) dirty_reg <= 0;
            else if (write_valid)
                dirty_reg <= dirty_reg & ~(1<<(way_select_bin*(2**LINE_OFF_W) + index_reg));// updates position with 0
            else if (write_access & hit)
                dirty_reg <= dirty_reg |  (1<<(way_hit_bin*(2**LINE_OFF_W) + index_reg));//updates position with 1
            else dirty_reg <= dirty_reg;
        end

        for (k = 0; k < N_WAYS; k = k + 1) begin : dirty_block
            //valid-memory output stage register - 1 c.c. read-latency (cleaner simulation during rep.)
            always @(posedge clk) dirty[k] <= dirty_reg[(2**LINE_OFF_W)*k+index];
        end

        //flush line
        assign write_valid = valid_reg & ~(|way_hit) & (way_select == dirty); //flush if there is not a hit, and the way selected is dirty
        logic [TAG_W-1:0] tag_flush = line_tag >> (way_select_bin * TAG_W);  //auxiliary logic
        assign write_addr = {
            tag_flush, index_reg
        };  //the position of the current block in cache (not of the access)
        assign write_wdata = line_rdata >> (way_select_bin * FE_DATA_W * (2 ** WORD_OFF_W));

    endgenerate

endmodule  // cache_memory


/*---------------------------------*/
/* Byte-width generable iob-sp-ram */
/*---------------------------------*/

//For cycle that generated byte-width (single enable) single-port SRAM
//older synthesis tool may require this approch

module iob_gen_sp_ram #(
    parameter DATA_W = 32,
    parameter ADDR_W = 10
) (
    input                 clk,
    input                 en,
    input  [DATA_W/8-1:0] we,
    input  [  ADDR_W-1:0] addr,
    output [  DATA_W-1:0] data_out,
    input  [  DATA_W-1:0] data_in
);

    genvar i;
    generate
        for (i = 0; i < (DATA_W / 8); i = i + 1) begin : ram
            iob_ram_sp #(
                .DATA_W(8),
                .ADDR_W(ADDR_W)
            ) iob_cache_mem (
                .clk (clk),
                .en  (en),
                .we  (we[i]),
                .addr(addr),
                .dout(data_out[8*i+:8]),
                .din (data_in[8*i+:8])
            );
        end
    endgenerate

endmodule
