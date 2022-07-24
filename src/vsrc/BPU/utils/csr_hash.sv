// Implement GHR hash using a CSR (Circular Shifted Register)
module csr_hash #(
    parameter INPUT_LENGTH  = 25,
    parameter OUTPUT_LENGTH = 10
) (
    input logic clk,
    input logic rst,
    input logic data_update_i,
    input logic [INPUT_LENGTH-1:0] data_i,
    output logic [OUTPUT_LENGTH-1:0] hash_o
);

    // Reset signal
    logic rst_n;
    assign rst_n = ~rst;

    bit [OUTPUT_LENGTH-1:0] CSR;

    // State migration function
    bit [OUTPUT_LENGTH-1:0] next_CSR;
    always_comb begin : csr_hash_comb
        localparam residual = (INPUT_LENGTH - 1) % OUTPUT_LENGTH;
        // $display(residual, INPUT_LENGTH, OUTPUT_LENGTH);
        next_CSR = {CSR[OUTPUT_LENGTH-2:0], CSR[OUTPUT_LENGTH-1] ^ data_i[0]};
        next_CSR[residual] = next_CSR[residual] ^ data_i[INPUT_LENGTH-1];
    end

    // Update CSR
    always_ff @(posedge clk or negedge rst_n) begin : csr_hash_ff
        if (!rst_n) begin
            CSR <= 0;
        end else if (data_update_i) begin
            CSR <= next_CSR;
        end
    end

    // Assign output
    assign hash_o = next_CSR;

endmodule
