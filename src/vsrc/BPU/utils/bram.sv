// simulate BRAM IP in simulation without Vivado
// data read latency is 1 cycle
module bram #(
    parameter DATA_WIDTH = 1,
    parameter DATA_DEPTH_EXP2 = 1
) (
    input logic clk,
    input logic wea,  // Write enable A
    input logic web,  // Write enable B

    input logic [DATA_WIDTH-1:0] dina,
    input logic [DATA_DEPTH_EXP2-1:0] addra,
    output logic [DATA_WIDTH-1:0] douta,

    input logic [DATA_WIDTH-1:0] dinb,
    input logic [DATA_DEPTH_EXP2-1:0] addrb,
    output logic [DATA_WIDTH-1:0] doutb
);

    bit [DATA_WIDTH-1:0] data[2**DATA_DEPTH_EXP2];

    // For Simulation
    initial begin
        for (integer i = 0; i < 2 ** DATA_DEPTH_EXP2; i++) begin
            data[i] = 0;
        end
    end

    // Read logic
    always_ff @(posedge clk) begin
        douta <= data[addra];
        doutb <= data[addrb];
    end

    // Write logic
    always_ff @(posedge clk) begin
        if (wea) begin
            data[addra] <= dina;
        end
        if (web) begin
            if (addra != addrb) begin  // Write conflict
                data[addrb] <= dinb;
            end
        end
    end



endmodule
