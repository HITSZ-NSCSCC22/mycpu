`include "core_types.sv"
`include "core_config.sv"

module mem2
    import core_types::*;
    import core_config::*;
(
    input logic clk,
    input logic rst,
    input logic stall,
    input logic flush,

    input mem1_mem2_struct mem1_i,

    output mem2_data_forward_t mem2_data_forward,

    output mem2_wb_struct mem2_o_buffer,

    output logic stallreq,
    input logic data_ok,
    input logic [`RegBus] cache_data_i

);
    mem2_wb_struct mem2_o;

    logic [`AluOpBus] aluop_i;
    assign aluop_i = mem1_i.aluop;

    logic mem_load_op;
    assign mem_load_op = aluop_i == `EXE_LD_B_OP || aluop_i == `EXE_LD_BU_OP || aluop_i == `EXE_LD_H_OP || aluop_i == `EXE_LD_HU_OP ||
                       aluop_i == `EXE_LD_W_OP || aluop_i == `EXE_LL_OP ;

    assign mem2_data_forward = !mem_load_op ? {1'b0,1'b0,mem1_i.wreg, mem1_i.waddr, mem1_i.wdata} :
      (data_ok | data_ok_delay) ? {
        mem_load_op, data_ok | data_ok_delay, mem2_o.wreg, mem2_o.waddr, mem2_o.wdata
    } : 0;

    logic [`RegBus] mem_addr, pc, pc_delay;
    assign pc = mem1_i.instr_info.pc;
    assign mem_addr = mem1_i.mem_addr;
    always_ff @(posedge clk) begin
        pc_delay <= pc;
    end

    logic data_already_ok;
    always_comb begin
        if (rst) data_already_ok = 0;
        else if (pc != pc_delay) data_already_ok = 0;
        else if (data_ok) data_already_ok = 1;
        else data_already_ok = data_already_ok;
    end

    logic data_ok_delay;
    logic [`RegBus] cache_data_delay, cache_data;
    assign cache_data = cache_data_delay | cache_data_i;
    always_ff @(posedge clk) begin
        cache_data_delay <= cache_data_i;
        data_ok_delay <= data_ok;
    end

    logic excp = mem1_i.excp;
    assign stallreq = mem_load_op & !excp & !data_ok & !data_already_ok;

    logic [`RegBus] debug_wdata;
    assign debug_wdata = mem2_o.wdata;

    always_comb begin
        if (rst) mem2_o = 0;
        else begin
            mem2_o = mem1_i;
            if (mem_load_op & (data_ok | data_ok_delay))
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
                            default: begin
                                mem2_o.wdata = `ZeroWord;
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
                                mem2_o.wdata = `ZeroWord;
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
                            default: begin
                                mem2_o.wdata = `ZeroWord;
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
                                mem2_o.wdata = `ZeroWord;
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
    end

    always_ff @(posedge clk) begin
        if (rst) mem2_o_buffer <= 0;
        else if (flush) mem2_o_buffer <= 0;
        else if (stall) begin
            mem2_o_buffer <= mem2_o_buffer;
        end else mem2_o_buffer <= mem2_o;
    end



endmodule
