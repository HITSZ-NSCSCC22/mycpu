module byte_bram #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_WIDTH = 8,
    parameter DATA_DEPTH_EXP2 = 8,
    parameter BYTE_NUM = 16
) (
    input logic clk,

    input logic ena,
    input logic [BYTE_NUM-1:0] wea,
    input logic [ADDR_WIDTH-1:0] addra,
    input logic [DATA_WIDTH-1:0] dina,

    input logic enb,
    input logic [ADDR_WIDTH-1:0] addrb,
    output logic [DATA_WIDTH-1:0] doutb
);


    bit [DATA_WIDTH-1:0] data[2**DATA_DEPTH_EXP2];


    initial begin
        for (integer i = 0; i < 2 ** DATA_DEPTH_EXP2; i++) begin
            data[i] = 0;
        end
    end

    always_ff @(posedge clk) begin
        if (enb) doutb <= data[addrb];
        else doutb <= doutb;
    end

    // Write logic
    always_ff @(posedge clk) begin
        // data[addra[DATA_DEPTH_EXP2-1:0]] <= dina;
        if (ena) begin
            if (wea[0]) data[addra][7:0] <= dina[7:0];
            if (wea[1]) data[addra][15:8] <= dina[15:8];
            if (wea[2]) data[addra][23:16] <= dina[23:16];
            if (wea[3]) data[addra][31:24] <= dina[31:24];
            if (wea[4]) data[addra][39:32] <= dina[39:32];
            if (wea[5]) data[addra][47:40] <= dina[47:40];
            if (wea[6]) data[addra][55:48] <= dina[55:48];
            if (wea[7]) data[addra][63:56] <= dina[63:56];
            if (wea[8]) data[addra][71:64] <= dina[71:64];
            if (wea[9]) data[addra][79:72] <= dina[79:72];
            if (wea[10]) data[addra][87:80] <= dina[87:80];
            if (wea[11]) data[addra][95:88] <= dina[95:88];
            if (wea[12]) data[addra][103:96] <= dina[103:96];
            if (wea[13]) data[addra][111:104] <= dina[111:104];
            if (wea[14]) data[addra][119:112] <= dina[119:112];
            if (wea[15]) data[addra][127:120] <= dina[127:120];
        end
    end

`ifdef SIMU
    logic [127:0] debug_data;
    assign debug_data = data[173];
`endif

endmodule
