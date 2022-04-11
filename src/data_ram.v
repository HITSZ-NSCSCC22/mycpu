`include "vsrc/defines.v"

module data_ram(
    input wire clk,

    input wire ce_1,
    input wire we_1,
    input wire[`InstAddrBus] pc_1,
    input wire[`DataAddrBus] addr_1,
    input wire[3:0]	sel_1,
    input wire[`DataBus] data_i_1,
    output reg[`DataBus] data_o_1,

    input wire ce_2,
    input wire we_2,
    input wire[`InstAddrBus] pc_2,
    input wire[`DataAddrBus] addr_2,
    input wire[3:0]	sel_2,
    input wire[`DataBus] data_i_2,
    output reg[`DataBus] data_o_2

  );

  reg[`ByteWidth]  data_mem0[0:`DataMemNum-1];
  reg[`ByteWidth]  data_mem1[0:`DataMemNum-1];
  reg[`ByteWidth]  data_mem2[0:`DataMemNum-1];
  reg[`ByteWidth]  data_mem3[0:`DataMemNum-1];

  always @ (posedge clk)
    begin
      if(we_1 == `WriteEnable && we_2 == `WriteEnable && addr_1 == addr_2)
        begin
          if(pc_1 > pc_2)
            begin
              if (sel_1[3] == 1'b1)
                data_mem3[addr_1[`DataMemNumLog2+1:2]] <= data_i_1[31:24];
              if (sel_1[2] == 1'b1)
                data_mem2[addr_1[`DataMemNumLog2+1:2]] <= data_i_1[23:16];
              if (sel_1[1] == 1'b1)
                data_mem1[addr_1[`DataMemNumLog2+1:2]] <= data_i_1[15:8];
              if (sel_1[0] == 1'b1)
                data_mem0[addr_1[`DataMemNumLog2+1:2]] <= data_i_1[7:0];
            end
          else 
            begin
              if (sel_2[3] == 1'b1)
                data_mem3[addr_2[`DataMemNumLog2+1:2]] <= data_i_2[31:24];
              if (sel_2[2] == 1'b1)
                data_mem2[addr_2[`DataMemNumLog2+1:2]] <= data_i_2[23:16];
              if (sel_2[1] == 1'b1)
                data_mem1[addr_2[`DataMemNumLog2+1:2]] <= data_i_2[15:8];
              if (sel_2[0] == 1'b1)
                data_mem0[addr_2[`DataMemNumLog2+1:2]] <= data_i_2[7:0];
            end
        end
      else 
        begin
          if(we_1 == `WriteEnable)
            begin
              if (sel_1[3] == 1'b1)
                data_mem3[addr_1[`DataMemNumLog2+1:2]] <= data_i_1[31:24];
              if (sel_1[2] == 1'b1)
                data_mem2[addr_1[`DataMemNumLog2+1:2]] <= data_i_1[23:16];
              if (sel_1[1] == 1'b1)
                data_mem1[addr_1[`DataMemNumLog2+1:2]] <= data_i_1[15:8];
              if (sel_1[0] == 1'b1)
                data_mem0[addr_1[`DataMemNumLog2+1:2]] <= data_i_1[7:0];
            end
          if(we_2 == `WriteEnable)
            begin
              if (sel_2[3] == 1'b1)
                data_mem3[addr_2[`DataMemNumLog2+1:2]] <= data_i_2[31:24];
              if (sel_2[2] == 1'b1)
                data_mem2[addr_2[`DataMemNumLog2+1:2]] <= data_i_2[23:16];
              if (sel_2[1] == 1'b1)
                data_mem1[addr_2[`DataMemNumLog2+1:2]] <= data_i_2[15:8];
              if (sel_2[0] == 1'b1)
                data_mem0[addr_2[`DataMemNumLog2+1:2]] <= data_i_2[7:0];
            end
        end
    end


  always @ (posedge clk)
    begin
      if (ce_1 == `ChipDisable)
        data_o_1 <= `ZeroWord;
      else
        data_o_1 <= {data_mem3[addr_1[`DataMemNumLog2+1:2]],
                   data_mem2[addr_1[`DataMemNumLog2+1:2]],
                   data_mem1[addr_1[`DataMemNumLog2+1:2]],
                   data_mem0[addr_1[`DataMemNumLog2+1:2]]};

    end

  always @ (posedge clk)
    begin
      if (ce_2 == `ChipDisable)
        data_o_2 <= `ZeroWord;
      else
        data_o_2 <= {data_mem3[addr_2[`DataMemNumLog2+1:2]],
                   data_mem2[addr_2[`DataMemNumLog2+1:2]],
                   data_mem1[addr_2[`DataMemNumLog2+1:2]],
                   data_mem0[addr_2[`DataMemNumLog2+1:2]]};

    end

endmodule
