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
    input mem1_mem2_struct mem1_i,

    // <- DCache
    input logic data_ok,
    input logic [`RegBus] cache_data_i,
    output logic mem_valid,

    // Dispatch
    output data_forward_t data_forward_o,
    // Next stage
    output mem2_wb_struct mem2_o_buffer
);
    mem2_wb_struct mem2_o;

    // Assign input
    instr_info_t instr_info;
    special_info_t special_info;

    logic [`AluOpBus] aluop_i;
    logic mem_load_op;
    logic [ADDR_WIDTH-1:0] mem_addr;

    logic data_already_ok;

    logic [`RegBus] cache_data_delay, cache_data;

    assign instr_info = mem1_i.instr_info;
    assign special_info = mem1_i.instr_info.special_info;


    assign aluop_i = mem1_i.aluop;
    assign mem_load_op = special_info.mem_load;
    assign mem_addr = mem1_i.mem_addr;

    assign data_forward_o = ~(mem_load_op & mem1_i.mem_access_valid) ? {mem1_i.wreg, 1'b1, mem1_i.waddr, mem1_i.wdata} :
       {mem2_o.wreg, data_ok | data_already_ok, mem2_o.waddr, mem2_o.wdata};

    always_ff @(posedge clk) begin
        if (rst) data_already_ok <= 0;
        else if (advance | flush) data_already_ok <= 0;
        else if (data_ok) data_already_ok <= 1;
    end

    // DCache
    assign cache_data = cache_data_delay | cache_data_i;
    always_ff @(posedge clk) begin
        if (rst) cache_data_delay <= 0;
        else if (advance | flush) cache_data_delay <= 0;
        else if (data_ok) cache_data_delay <= cache_data_i;
    end
    assign mem_valid = ~instr_info.excp & instr_info.valid;

    assign advance_ready = (mem_load_op & mem1_i.mem_access_valid & (data_ok | data_already_ok)) | ~(mem_load_op  & mem1_i.mem_access_valid);

    always_comb begin
        mem2_o.instr_info = instr_info;
        mem2_o.wreg = mem1_i.wreg;
        mem2_o.waddr = mem1_i.waddr;
        mem2_o.wdata = mem1_i.wdata;
        mem2_o.LLbit_we = mem1_i.LLbit_we;
        mem2_o.LLbit_value = mem1_i.LLbit_value;
        mem2_o.mem_addr = mem1_i.mem_addr;
        mem2_o.aluop = mem1_i.aluop;
        mem2_o.csr_signal = mem1_i.csr_signal;
        mem2_o.inv_i = mem1_i.inv_i;
        mem2_o.difftest_mem_info = mem1_i.difftest_mem_info;
        if (mem_load_op)
            case (aluop_i)
                `EXE_LD_B_OP: begin
                    case (mem_addr[1:0])
                        2'b11: begin
                            mem2_o.wdata = {{24{cache_data[31]}}, cache_data[31:24]};
                        end
                        2'b10: begin
                            mem2_o.wdata = {{24{cache_data[23]}}, cache_data[23:16]};
                        end
                        2'b01: begin
                            mem2_o.wdata = {{24{cache_data[15]}}, cache_data[15:8]};
                        end
                        2'b00: begin
                            mem2_o.wdata = {{24{cache_data[7]}}, cache_data[7:0]};
                        end
                    endcase
                end
                `EXE_LD_H_OP: begin
                    case (mem_addr[1:0])
                        2'b10: begin
                            mem2_o.wdata = {{16{cache_data[31]}}, cache_data[31:16]};
                        end

                        2'b00: begin
                            mem2_o.wdata = {{16{cache_data[15]}}, cache_data[15:0]};
                        end
                        default: begin
                            mem2_o.wdata = 0;
                        end
                    endcase
                end
                `EXE_LD_W_OP: begin
                    mem2_o.wdata = cache_data;
                end
                `EXE_LD_BU_OP: begin
                    case (mem_addr[1:0])
                        2'b11: begin
                            mem2_o.wdata = {{24{1'b0}}, cache_data[31:24]};
                        end
                        2'b10: begin
                            mem2_o.wdata = {{24{1'b0}}, cache_data[23:16]};
                        end
                        2'b01: begin
                            mem2_o.wdata = {{24{1'b0}}, cache_data[15:8]};
                        end
                        2'b00: begin
                            mem2_o.wdata = {{24{1'b0}}, cache_data[7:0]};
                        end
                    endcase
                end
                `EXE_LD_HU_OP: begin
                    case (mem_addr[1:0])
                        2'b10: begin
                            mem2_o.wdata = {{16{1'b0}}, cache_data[31:16]};
                        end

                        2'b00: begin
                            mem2_o.wdata = {{16{1'b0}}, cache_data[15:0]};
                        end
                        default: begin
                            mem2_o.wdata = 0;
                        end
                    endcase
                end
                `EXE_LL_OP: begin
                    mem2_o.wdata = cache_data;
                end
                default: begin

                end
            endcase
    end

    always_ff @(posedge clk) begin
        if (rst) mem2_o_buffer <= 0;
        else if (flush | clear) mem2_o_buffer <= 0;
        else if (advance) mem2_o_buffer <= mem2_o;
    end

`ifdef SIMU
    logic [ADDR_WIDTH-1:0] debug_pc = instr_info.pc;
`endif


endmodule
