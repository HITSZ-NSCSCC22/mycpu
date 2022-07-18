// simulate BRAM IP in simulation without Vivado
// data read latency is 1 cycle
module bram #(
    parameter DATA_WIDTH = 128,
    parameter DATA_DEPTH_EXP2 = 8,
    parameter ADDR_WIDTH = DATA_DEPTH_EXP2
) (
    input logic clk,
    input logic ena,  // Chip enable A
    input logic enb,  // Chip enable B
    input logic wea,  // Write enable A
    input logic web,  // Write enable B

    input  logic [DATA_WIDTH-1:0] dina,
    input  logic [ADDR_WIDTH-1:0] addra,
    output logic [DATA_WIDTH-1:0] douta,

    input  logic [DATA_WIDTH-1:0] dinb,
    input  logic [ADDR_WIDTH-1:0] addrb,
    output logic [DATA_WIDTH-1:0] doutb
);

    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] data[2**DATA_DEPTH_EXP2];

    // For Simulation
    initial begin
        for (integer i = 0; i < 2 ** DATA_DEPTH_EXP2; i++) begin
            data[i] = 0;
        end
    end

    // Read logic
    always_ff @(posedge clk) begin
        if (ena & wea) douta <= dina;
        else if (ena) douta <= data[addra];
        else douta <= 0;

        if (enb & web) doutb <= dinb;
        else if (enb) doutb <= data[addrb];
        else doutb <= 0;
    end

    // Write logic
    always_ff @(posedge clk) begin
        if (enb & web) begin
            data[addrb[DATA_DEPTH_EXP2-1:0]] <= dinb;
        end

        // A port has priority
        if (ena & wea) begin
            data[addra[DATA_DEPTH_EXP2-1:0]] <= dina;
        end
    end



endmodule
