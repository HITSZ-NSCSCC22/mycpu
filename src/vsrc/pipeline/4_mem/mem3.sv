`include "core_types.sv"
`include "core_config.sv"

module mem3
    import core_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,

    // Pipeline control signals
    input  logic flush,
    input  logic clear,
    input  logic advance,
    output logic advance_ready,

    // Previous stage
    input mem2_mem3_struct mem2_i,

    // <- DCache
    output logic mem_valid,
    input logic data_ok,
    input logic [`RegBus] cache_data_i,

    // Dispatch
    output data_forward_t data_forward_o,
    // Next stage
    output mem3_wb_struct mem3_o_buffer
);
    mem3_wb_struct mem3_o;

    // Assign input
    instr_info_t instr_info;
    special_info_t special_info;

    logic [`AluOpBus] aluop_i;
    logic mem_store_op, mem_load_op;
    logic [ADDR_WIDTH-1:0] mem_addr;

    logic data_already_ok;

    logic [`RegBus] cache_data_delay, cache_data;

    assign instr_info = mem2_i.instr_info;
    assign special_info = mem2_i.instr_info.special_info;


    assign aluop_i = mem2_i.aluop;
    assign mem_store_op = special_info.mem_store;
    assign mem_load_op = special_info.mem_load;
    assign mem_addr = mem2_i.mem_addr;

    assign data_forward_o = ~(mem_load_op & mem2_i.mem_access_valid) ? {mem2_i.wreg, 1'b1, mem2_i.waddr, mem2_i.wdata,mem2_i.csr_signal} :
       {mem3_o.wreg, data_ok | data_already_ok, mem3_o.waddr, mem3_o.wdata,mem3_o.csr_signal};

    always_ff @(posedge clk) begin
        if (rst) data_already_ok <= 0;
        else if (advance | flush) data_already_ok <= 0;
        else if (data_ok) data_already_ok <= 1;
    end

    assign cache_data = cache_data_delay | cache_data_i;
    always_ff @(posedge clk) begin
        if (rst) cache_data_delay <= 0;
        else if (advance | flush) cache_data_delay <= 0;
        else if (data_ok) cache_data_delay <= cache_data_i;
    end

    assign advance_ready = ((mem_load_op | mem_store_op) & mem2_i.mem_access_valid & (data_ok | data_already_ok)) | ~((mem_load_op| mem_store_op)  & mem2_i.mem_access_valid);

    assign mem_valid = mem2_i.mem_access_valid;

    always_comb begin
        mem3_o.instr_info = instr_info;
        mem3_o.wreg = mem2_i.wreg;
        mem3_o.waddr = mem2_i.waddr;
        mem3_o.wdata = mem2_i.wdata;
        mem3_o.LLbit_we = mem2_i.LLbit_we;
        mem3_o.LLbit_value = mem2_i.LLbit_value;
        mem3_o.mem_addr = mem2_i.mem_addr;
        mem3_o.aluop = mem2_i.aluop;
        mem3_o.csr_signal = mem2_i.csr_signal;
        mem3_o.inv_i = mem2_i.inv_i;
        mem3_o.difftest_mem_info = mem2_i.difftest_mem_info;
        if (mem_load_op)
            case (aluop_i)
                `EXE_LD_B_OP: begin
                    case (mem_addr[1:0])
                        2'b11: begin
                            mem3_o.wdata = {{24{cache_data[31]}}, cache_data[31:24]};
                        end
                        2'b10: begin
                            mem3_o.wdata = {{24{cache_data[23]}}, cache_data[23:16]};
                        end
                        2'b01: begin
                            mem3_o.wdata = {{24{cache_data[15]}}, cache_data[15:8]};
                        end
                        2'b00: begin
                            mem3_o.wdata = {{24{cache_data[7]}}, cache_data[7:0]};
                        end
                    endcase
                end
                `EXE_LD_H_OP: begin
                    case (mem_addr[1:0])
                        2'b10: begin
                            mem3_o.wdata = {{16{cache_data[31]}}, cache_data[31:16]};
                        end

                        2'b00: begin
                            mem3_o.wdata = {{16{cache_data[15]}}, cache_data[15:0]};
                        end
                        default: begin
                            mem3_o.wdata = 0;
                        end
                    endcase
                end
                `EXE_LD_W_OP: begin
                    mem3_o.wdata = cache_data;
                end
                `EXE_LD_BU_OP: begin
                    case (mem_addr[1:0])
                        2'b11: begin
                            mem3_o.wdata = {{24{1'b0}}, cache_data[31:24]};
                        end
                        2'b10: begin
                            mem3_o.wdata = {{24{1'b0}}, cache_data[23:16]};
                        end
                        2'b01: begin
                            mem3_o.wdata = {{24{1'b0}}, cache_data[15:8]};
                        end
                        2'b00: begin
                            mem3_o.wdata = {{24{1'b0}}, cache_data[7:0]};
                        end
                    endcase
                end
                `EXE_LD_HU_OP: begin
                    case (mem_addr[1:0])
                        2'b10: begin
                            mem3_o.wdata = {{16{1'b0}}, cache_data[31:16]};
                        end

                        2'b00: begin
                            mem3_o.wdata = {{16{1'b0}}, cache_data[15:0]};
                        end
                        default: begin
                            mem3_o.wdata = 0;
                        end
                    endcase
                end
                `EXE_LL_OP: begin
                    mem3_o.wdata = cache_data;
                end
                default: begin

                end
            endcase
    end

    always_ff @(posedge clk) begin
        if (rst) mem3_o_buffer <= 0;
        else if (flush | clear) mem3_o_buffer <= 0;
        else if (advance) mem3_o_buffer <= mem3_o;
    end

`ifdef SIMU
    logic [ADDR_WIDTH-1:0] debug_pc = instr_info.pc;
    logic [`RegBus] debug_wdata = mem3_o.wdata;
`endif


endmodule
