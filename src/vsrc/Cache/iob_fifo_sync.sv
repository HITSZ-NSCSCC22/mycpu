module iob_fifo_sync #(
    parameter W_DATA_W = 0,
    R_DATA_W = 0,
    ADDR_W = 0,  //higher ADDR_W lower DATA_W
    //determine W_ADDR_W and R_ADDR_W
    MAXDATA_W = {((W_DATA_W) > (R_DATA_W)) ? (W_DATA_W) : (R_DATA_W)},
    MINDATA_W = {((W_DATA_W) < (R_DATA_W)) ? (W_DATA_W) : (R_DATA_W)},
    N = MAXDATA_W / MINDATA_W,
    MINADDR_W = ADDR_W - $clog2(N),  //lower ADDR_W (higher DATA_W)
    W_ADDR_W = (W_DATA_W == MAXDATA_W) ? MINADDR_W : ADDR_W,
    R_ADDR_W = (R_DATA_W == MAXDATA_W) ? MINADDR_W : ADDR_W
) (
    input logic arst,
    input logic rst,
    input logic clk,

    //write port
    output logic [N-1:0] ext_mem_w_en,
    output logic [MINDATA_W*N-1:0] ext_mem_w_data,
    output logic [MINADDR_W*N-1:0] ext_mem_w_addr,
    //read port
    output logic ext_mem_r_en,
    output logic [MINADDR_W*N-1:0] ext_mem_r_addr,
    input logic [MINDATA_W*N-1:0] ext_mem_r_data,

    //read port
    input logic r_en,
    output logic r_data,
    output logic [R_DATA_W-1:0] r_empty,
    //write port
    input logic w_en,
    input logic [W_DATA_W-1:0] w_data,
    output logic w_full,

    //FIFO level
    output logic [ADDR_W:0] level
);

    localparam ADDR_W_DIFF = $clog2(N);
    localparam [ADDR_W:0] FIFO_SIZE = (1'b1 << ADDR_W);  //in bytes

    //effective write enable
    wire w_en_int = w_en & ~w_full;

    //write address
    logic                           [W_ADDR_W-1:0] w_addr;
    always @(posedge clk, posedge arst) begin
        if (arst) w_addr <= 1'b0;
        else if (rst) w_addr <= 1'b0;
        else if (w_en_int) w_addr <= w_addr + 1'b1;
    end


    //effective read enable
    logic                r_en_int = r_en & ~r_empty;

    //read address
    logic [R_ADDR_W-1:0] r_addr;
    always @(posedge clk, posedge arst) begin
        if (arst) r_addr <= 1'b0;
        else if (rst) r_addr <= 1'b0;
        else if (r_en_int) r_addr <= r_addr + 1'b1;
    end

    //assign according to assymetry type
    wire [ADDR_W:0] w_incr;
    wire [ADDR_W:0] r_incr;
    generate
        if (W_DATA_W > R_DATA_W) begin
            assign r_incr = 1'b1;
            assign w_incr = 1'b1 << ADDR_W_DIFF;
        end else if (R_DATA_W > W_DATA_W) begin
            assign w_incr = 1'b1;
            assign r_incr = 1'b1 << ADDR_W_DIFF;
        end else begin
            assign r_incr = 1'b1;
            assign w_incr = 1'b1;
        end
    endgenerate

    //FIFO level
    reg [ADDR_W+1:0] level_nxt;
    always @(posedge clk, posedge arst) begin
        if (arst) level <= 1'b0;
        else if (rst) level <= 1'b0;
        else level <= level_nxt[0+:ADDR_W+1];
    end


    always_comb begin
        level_nxt = {1'd0, level};
        if (w_en_int && (!r_en_int)) level_nxt = level + w_incr;
        else if (w_en_int && r_en_int) level_nxt = (level + w_incr) - r_incr;
        else if ((!w_en_int) && r_en_int) level_nxt = level - r_incr;
    end

    //FIFO empty
    logic r_empty_nxt;
    assign r_empty_nxt = level_nxt[0+:ADDR_W+1] < r_incr;
    always @(posedge clk, posedge arst) begin
        if (arst) r_empty <= 1'd1;
        else r_empty <= r_empty_nxt;
    end

    //FIFO full
    logic w_full_nxt;
    assign w_full_nxt = level_nxt[0+:ADDR_W+1] > (FIFO_SIZE - w_incr);
    always @(posedge clk, posedge arst) begin
        if (arst) w_full <= 1'd1;
        else w_full <= w_full_nxt;
    end

    //FIFO memory
    iob_ram_2p_asym #(
        .W_DATA_W(W_DATA_W),
        .R_DATA_W(R_DATA_W),
        .ADDR_W  (ADDR_W)
    ) iob_ram_2p_asym0 (
        .clk(clk),

        .ext_mem_w_en  (ext_mem_w_en),
        .ext_mem_w_data(ext_mem_w_data),
        .ext_mem_w_addr(ext_mem_w_addr),
        .ext_mem_r_en  (ext_mem_r_en),
        .ext_mem_r_addr(ext_mem_r_addr),
        .ext_mem_r_data(ext_mem_r_data),

        .w_en  (w_en_int),
        .w_data(w_data),
        .w_addr(w_addr),

        .r_en  (r_en_int),
        .r_addr(r_addr),
        .r_data(r_data)
    );

endmodule

