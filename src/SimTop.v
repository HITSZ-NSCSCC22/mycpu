`include "vsrc/defines.v"
`include "ram.v"

module SimTop(
    input clock,
    input reset,
    input[63:0] io_logCtrl_log_begin,
    input[63:0] io_logCtrl_log_end,
    input[63:0] io_logCtrl_log_level,
    input io_perfInfo_clean,
    input io_perfInfo_dump,
    output io_uart_out_valid,
    output[7:0]io_uart_out_ch,
    output io_uart_in_valid,
    input[7:0]io_uart_in_ch
  );

  wire chip_enable;
  wire[`RegBus] ram_raddr;
  wire[`RegBus] ram_rdata;
  wire[`RegBus] ram_waddr;
  wire[`RegBus] ram_wdata;
  wire ram_wen;

  wire dram_ce;
  wire dram_we;
  wire[`DataAddrBus] dram_addr;
  wire[3:0] dram_sel;
  wire[`DataBus] dram_data_i;
  wire[`DataBus] dram_data_o;

  wire [`RegBus] debug_commit_pc;
  wire debug_commit_valid;
  wire[`InstBus] debug_commit_instr;
  wire debug_commit_wreg;
  wire [`RegAddrBus] debug_commit_reg_waddr;
  wire [`RegBus] debug_commit_reg_wdata;
  wire[1023:0] debug_reg;
  wire Instram_branch_flag;
  cpu_top u_cpu_top(
            .clk(clock),
            .rst(reset),
            .dram_data_i(dram_data_i),
            .ram_rdata_i(ram_rdata),

            .ram_raddr_o(ram_raddr),
            .ram_wdata_o(ram_wdata),
            .ram_waddr_o(ram_waddr),
            .ram_wen_o (ram_wen),
            .ram_en_o (chip_enable),

            .dram_addr_o(dram_addr),
            .dram_data_o(dram_data_o),
            .dram_we_o(dram_we),
            .dram_sel_o(dram_sel),
            .dram_ce_o(dram_ce),

            .debug_commit_pc(debug_commit_pc        ),
            .debug_commit_valid(debug_commit_valid     ),
            .debug_commit_instr(debug_commit_instr     ),
            .debug_commit_wreg(debug_commit_wreg      ),
            .debug_commit_reg_waddr(debug_commit_reg_waddr ),
            .debug_commit_reg_wdata(debug_commit_reg_wdata ),
            .debug_reg(debug_reg   ),
            .Instram_branch_flag(Instram_branch_flag)
          );

`ifdef DUMP_WAVEFORM

  initial
    begin
      $dumpfile("wave.vcd");
      $dumpvars(0,u_cpu_top);
    end

`endif

`ifndef DIFFTEST

  ram u_ram(
        .clock (clock ),
        .reset (reset ),
        .ce    (chip_enable),
        .raddr (ram_raddr ),
        .rdata (ram_rdata ),
        .waddr (ram_waddr ),
        .wdata (ram_wdata ),
        .wen   (ram_wen   ),
        .branch_flag_i(Instram_branch_flag)
      );
`endif


data_ram u_data_ram(
    .clk(clock), 
    .ce(dram_ce),
    .we(dram_we),
    .addr(dram_addr),
    .sel(dram_sel),
    .data_i(dram_data_i),
    .data_o(dram_data_o)    
);


`ifdef DIFFTEST

  reg coreid = 0;
  reg [7:0] index = 0;
  wire reset_n;
  assign reset_n = ~reset;
  wire [63:0] ram_rdata;



  wire[31:0] ram_rIdx = (ram_raddr - 32'h1c000000) >> 2;

  reg [63:0] cycleCnt;
  reg [63:0] instrCnt;

  always @(posedge clock or negedge reset_n)
    begin
      if (!reset_n)
        begin
          cycleCnt <= 0;
          instrCnt <= 0;
        end
      else
        begin
          cycleCnt <= cycleCnt + 1;
          instrCnt <= instrCnt + debug_commit_valid;
        end
    end

  DifftestTrapEvent difftest_trap_event(
                      .clock(clock),
                      .coreid(coreid),
                      .valid(),
                      .code(),
                      .pc(debug_commit_pc),
                      .cycleCnt(cycleCnt),
                      .instrCnt(instrCnt)
                    );

  RAMHelper ram_helper(
              .clk(clock),
              .en(chip_enable),
              .rIdx(ram_rIdx),
              .rdata(ram_rdata),
              .wIdx(),
              .wdata(),
              .wmask(),
              .wen()
            );

  DifftestInstrCommit difftest_instr_commit(
                        .clock(clock),
                        .coreid(coreid),
                        .index(index),
                        .valid(debug_commit_valid), // Non-zero means valid, checked per-cycle, if valid, instr count as as commit
                        .pc(debug_commit_pc),
                        .instr(debug_commit_instr),
                        .skip(),
                        .is_TLBFILL(),
                        .TLBFILL_index(),
                        .is_CNTinst(),
                        .timer_64_value(),
                        .wen(debug_commit_wreg),
                        .wdest(debug_commit_reg_waddr),
                        .wdata(debug_commit_reg_wdata)
                      );

  DifftestArchIntRegState difftest_arch_int_reg_state(
                            .clock(clock),
                            .coreid(coreid),
                            .gpr_0(debug_reg[31:0]),
                            .gpr_1(debug_reg[63:32]),
                            .gpr_2(debug_reg[95:64]),
                            .gpr_3(debug_reg[127:96]),
                            .gpr_4(debug_reg[159:128]),
                            .gpr_5(debug_reg[191:160]),
                            .gpr_6(debug_reg[223:192]),
                            .gpr_7(debug_reg[255:224]),
                            .gpr_8(debug_reg[287:256]),
                            .gpr_9(debug_reg[319:288]),
                            .gpr_10(debug_reg[351:320]),
                            .gpr_11(debug_reg[383:352]),
                            .gpr_12(debug_reg[415:384]),
                            .gpr_13(debug_reg[447:416]),
                            .gpr_14(debug_reg[479:448]),
                            .gpr_15(debug_reg[511:480]),
                            .gpr_16(debug_reg[543:512]),
                            .gpr_17(debug_reg[575:544]),
                            .gpr_18(debug_reg[607:576]),
                            .gpr_19(debug_reg[639:608]),
                            .gpr_20(debug_reg[671:640]),
                            .gpr_21(debug_reg[703:672]),
                            .gpr_22(debug_reg[735:704]),
                            .gpr_23(debug_reg[767:736]),
                            .gpr_24(debug_reg[799:768]),
                            .gpr_25(debug_reg[831:800]),
                            .gpr_26(debug_reg[863:832]),
                            .gpr_27(debug_reg[895:864]),
                            .gpr_28(debug_reg[927:896]),
                            .gpr_29(debug_reg[959:928]),
                            .gpr_30(debug_reg[991:960]),
                            .gpr_31(debug_reg[1023:992])
                          );
`endif
endmodule
