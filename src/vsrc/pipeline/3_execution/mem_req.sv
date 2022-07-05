`include "core_types.sv"
`include "csr_defines.sv"

module mem_req
    import core_types::*;
    import csr_defines::*;
(

    input logic [`AluOpBus] aluop,
    input logic [`RegBus] mem_addr,
    input logic [`RegBus] mem_data,
    input logic llbit,

    output mem_cache_struct signal_cache_o


);

    always_comb begin
        signal_cache_o = 0;
        signal_cache_o.rd_type = 0;
        signal_cache_o.wr_type = 0;
        case (aluop)
            `EXE_LD_B_OP: begin
                signal_cache_o.addr = mem_addr;
                signal_cache_o.ce = `ChipEnable;
                signal_cache_o.sel = 4'b1111;
                signal_cache_o.rd_type = 0;
                case (mem_addr[1:0])
                    2'b11: begin
                        signal_cache_o.sel = 4'b1000;
                    end
                    2'b10: begin
                        signal_cache_o.sel = 4'b0100;
                    end
                    2'b01: begin
                        signal_cache_o.sel = 4'b0010;
                    end
                    2'b00: begin
                        signal_cache_o.sel = 4'b0001;
                    end
                    default: begin
                        signal_cache_o.sel = 4'b0000;
                    end
                endcase
            end
            `EXE_LD_H_OP: begin
                signal_cache_o.addr = mem_addr;
                signal_cache_o.ce = `ChipEnable;
                signal_cache_o.rd_type = 3'b001;
                case (mem_addr[1:0])
                    2'b10: begin
                        signal_cache_o.sel = 4'b1100;
                    end

                    2'b00: begin
                        signal_cache_o.sel = 4'b0011;
                    end

                    default: begin
                        signal_cache_o.sel = 4'b0001;
                    end
                endcase
            end
            `EXE_LD_W_OP: begin
                signal_cache_o.addr = mem_addr;
                signal_cache_o.ce = `ChipEnable;
                signal_cache_o.sel = 4'b1111;
                signal_cache_o.rd_type = 3'b010;
            end
            `EXE_LD_BU_OP: begin
                signal_cache_o.addr = mem_addr;
                signal_cache_o.ce = `ChipEnable;
                signal_cache_o.rd_type = 3'b000;
                case (mem_addr[1:0])
                    2'b11: begin
                        signal_cache_o.sel = 4'b1000;
                    end
                    2'b10: begin
                        signal_cache_o.sel = 4'b0100;
                    end
                    2'b01: begin
                        signal_cache_o.sel = 4'b0010;
                    end
                    2'b00: begin
                        signal_cache_o.sel = 4'b0001;
                    end
                    default: begin
                        signal_cache_o.sel = 4'b0000;
                    end
                endcase
            end
            `EXE_LD_HU_OP: begin
                signal_cache_o.addr = mem_addr;
                signal_cache_o.ce = `ChipEnable;
                signal_cache_o.rd_type = 3'b001;
                case (mem_addr[1:0])
                    2'b10: begin
                        signal_cache_o.sel = 4'b1100;
                    end
                    2'b00: begin
                        signal_cache_o.sel = 4'b0011;
                    end
                    default: begin
                        signal_cache_o.sel = 4'b0000;
                    end
                endcase
            end
            `EXE_ST_B_OP: begin
                signal_cache_o.addr = mem_addr;
                signal_cache_o.we = `WriteEnable;
                signal_cache_o.ce = `ChipEnable;
                signal_cache_o.wr_type = 3'b000;
                signal_cache_o.data = {mem_data[7:0], mem_data[7:0], mem_data[7:0], mem_data[7:0]};
                case (mem_addr[1:0])
                    2'b11: begin
                        signal_cache_o.sel = 4'b1000;
                    end
                    2'b10: begin
                        signal_cache_o.sel = 4'b0100;
                    end
                    2'b01: begin
                        signal_cache_o.sel = 4'b0010;
                    end
                    2'b00: begin
                        signal_cache_o.sel = 4'b0001;
                    end
                endcase
            end
            `EXE_ST_H_OP: begin
                signal_cache_o.addr = mem_addr;
                signal_cache_o.we = `WriteEnable;
                signal_cache_o.ce = `ChipEnable;
                signal_cache_o.wr_type = 3'b001;
                signal_cache_o.data = {mem_data[15:0], mem_data[15:0]};
                case (mem_addr[1:0])
                    2'b10: begin
                        signal_cache_o.sel = 4'b1100;
                    end
                    2'b00: begin
                        signal_cache_o.sel = 4'b0011;
                    end
                    default: begin
                        signal_cache_o.sel = 4'b0000;
                    end
                endcase
            end
            `EXE_ST_W_OP: begin
                signal_cache_o.addr = mem_addr;
                signal_cache_o.we = `WriteEnable;
                signal_cache_o.ce = `ChipEnable;
                signal_cache_o.wr_type = 3'b010;
                signal_cache_o.data = mem_data;
                signal_cache_o.sel = 4'b1111;
            end
            `EXE_LL_OP: begin
                signal_cache_o.addr = mem_addr;
                signal_cache_o.ce = `ChipEnable;
                signal_cache_o.sel = 4'b1111;
                signal_cache_o.rd_type = 3'b010;
            end
            `EXE_SC_OP: begin
                if (llbit == 1'b1) begin
                    signal_cache_o.addr = mem_addr;
                    signal_cache_o.we = `WriteEnable;
                    signal_cache_o.ce = `ChipEnable;
                    signal_cache_o.data = mem_data;
                    signal_cache_o.sel = 4'b1111;
                    signal_cache_o.wr_type = 3'b010;
                end else begin
                    signal_cache_o = 0;
                    signal_cache_o.wr_type = 3'b000;
                end
            end
            default: begin
                // Reset AXI signals, IMPORTANT!
                signal_cache_o = 0;
            end
        endcase
    end

endmodule
