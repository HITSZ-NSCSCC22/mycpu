module dual_port_lutram #(
    parameter DATA_WIDTH = 128,
    parameter DATA_DEPTH_EXP2 = 8,
    parameter ADDR_WIDTH = DATA_DEPTH_EXP2
) (
    input logic clk,

    input logic ena,
    input logic wea,
    input logic [ADDR_WIDTH-1:0] addra,
    input logic [DATA_WIDTH-1:0] dina,

    input logic enb,
    input logic [ADDR_WIDTH-1:0] addrb,
    output logic [DATA_WIDTH-1:0] doutb
);


    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] data[2**DATA_DEPTH_EXP2];


    initial begin
        for (integer i = 0; i < 2 ** DATA_DEPTH_EXP2; i++) begin
            data[i] = 0;
        end
    end

    always_ff @(posedge clk) begin
        if (enb & ena & wea & (addra == addrb)) doutb <= dina;
        else if (enb) doutb <= data[addrb];
        else doutb <= 0;
    end

    // Write logic
    always_ff @(posedge clk) begin
        if (ena & wea) begin
            data[addra[DATA_DEPTH_EXP2-1:0]] <= dina;
        end
    end


endmodule
