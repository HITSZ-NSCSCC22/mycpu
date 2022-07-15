module lutram_1w_mr #(
    parameter WIDTH = 32,
    parameter DEPTH = 32,
    parameter NUM_READ_PORTS = 2
) (
    input logic clk,

    input logic [$clog2(DEPTH)-1:0] waddr,
    input logic [$clog2(DEPTH)-1:0] raddr[NUM_READ_PORTS],

    input logic ram_write,
    input logic [WIDTH-1:0] new_ram_data,
    output logic [WIDTH-1:0] ram_data_out[NUM_READ_PORTS]
);


    logic [WIDTH-1:0] ram[DEPTH-1:0];

    initial ram = '{default: 0};
    always_ff @(posedge clk) begin
        if (ram_write) ram[waddr] <= new_ram_data;
    end

    always_comb begin
        for (int i = 0; i < NUM_READ_PORTS; i++) begin
            ram_data_out[i] = ram[raddr[i]];
        end
    end


endmodule
