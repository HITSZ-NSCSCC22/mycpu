module lutram_1w_mr #(
    parameter WIDTH = 32,
    parameter DEPTH = 32,
    parameter NUM_READ_PORTS = 2
) (
    input logic clk,

    input logic [$clog2(DEPTH)-1:0] waddr,
    input logic [NUM_READ_PORTS-1:0][$clog2(DEPTH)-1:0] raddr,

    input logic ram_write,
    input logic [WIDTH-1:0] new_ram_data,
    output logic [NUM_READ_PORTS-1:0][WIDTH-1:0] ram_data_out
);


    logic [WIDTH-1:0] ram[DEPTH-1:0];

    initial ram = '{default: 0};
    always_ff @(posedge clk) begin
        if (ram_write) ram[waddr] <= new_ram_data;
    end

    always_comb begin
        for (int i = 0; i < NUM_READ_PORTS; i++) begin
            if (ram_write && (raddr[i] == waddr)) ram_data_out[i] = new_ram_data;
            else ram_data_out[i] = ram[raddr[i]];
        end
    end


endmodule
