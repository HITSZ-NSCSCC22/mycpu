`timescale 1ns / 1ns

`include "vsrc/defines.v"
`include "ram.v"

module SimTop (
    input clock,
    input reset,
    input [63:0] io_logCtrl_log_begin,
    input [63:0] io_logCtrl_log_end,
    input [63:0] io_logCtrl_log_level,
    input io_perfInfo_clean,
    input io_perfInfo_dump,
    output io_uart_out_valid,
    output [7:0] io_uart_out_ch,
    output io_uart_in_valid,
    input [7:0] io_uart_in_ch
);

    wire chip_enable;
    wire [`RegBus] ram_raddr_1;
    wire [`RegBus] ram_raddr_2;
    wire [`RegBus] ram_rdata_1;
    wire [`RegBus] ram_rdata_2;
    wire [`RegBus] ramhelper_rdata;
    wire [`RegBus] ram_waddr;
    wire [`RegBus] ram_wdata;
    wire ram_wen;

    wire dram_ce_1;
    wire dram_we_1;
    wire [`DataAddrBus] dram_addr_1;
    wire [3:0] dram_sel_1;
    wire [`DataBus] dram_data_i_1;
    wire [`DataBus] dram_data_o_1;
    wire [`InstAddrBus] dram_pc_1;

    wire dram_ce_2;
    wire dram_we_2;
    wire [`DataAddrBus] dram_addr_2;
    wire [3:0] dram_sel_2;
    wire [`DataBus] dram_data_i_2;
    wire [`DataBus] dram_data_o_2;
    wire [`InstAddrBus] dram_pc_2;

    wire [`RegBus] debug_commit_pc_o_1;
    wire debug_commit_valid_o_1;
    wire [`InstBus] debug_commit_instr_o_1;
    wire debug_commit_wreg_o_1;
    wire [`RegAddrBus] debug_commit_reg_waddr_o_1;
    wire [`RegBus] debug_commit_reg_wdata_o_1;
    wire [`RegBus] debug_commit_pc_o_2;
    wire debug_commit_valid_o_2;
    wire [`InstBus] debug_commit_instr_o_2;
    wire debug_commit_wreg_o_2;
    wire [`RegAddrBus] debug_commit_reg_waddr_o_2;
    wire [`RegBus] debug_commit_reg_wdata_o_2;
    wire [1023:0] debug_reg;
    wire Instram_branch_flag;
    wire [831:0] csr_diff;
    cpu_top u_cpu_top (
        .clk(clock),
        .rst(reset),

        .dram_data_i_1(dram_data_o_1),
        .dram_data_i_2(dram_data_o_2),
        .ram_rdata_i_1(ram_rdata_1),
        .ram_rdata_i_2(ram_rdata_2),

        .ram_raddr_o_1(ram_raddr_1),
        .ram_raddr_o_2(ram_raddr_2),
        .ram_wdata_o(ram_wdata),
        .ram_waddr_o(ram_waddr),
        .ram_wen_o(ram_wen),
        .ram_en_o(chip_enable),

        .dram_addr_o_1(dram_addr_1),
        .dram_data_o_1(dram_data_i_1),
        .dram_we_o_1  (dram_we_1),
        .dram_sel_o_1 (dram_sel_1),
        .dram_ce_o_1  (dram_ce_1),
        .dram_pc_o_1  (dram_pc_1),

        .dram_addr_o_2(dram_addr_2),
        .dram_data_o_2(dram_data_i_2),
        .dram_we_o_2  (dram_we_2),
        .dram_sel_o_2 (dram_sel_2),
        .dram_ce_o_2  (dram_ce_2),
        .dram_pc_o_2  (dram_pc_2),

        .debug_commit_pc_1       (debug_commit_pc_o_1),
        .debug_commit_valid_1    (debug_commit_valid_o_1),
        .debug_commit_instr_1    (debug_commit_instr_o_1),
        .debug_commit_wreg_1     (debug_commit_wreg_o_1),
        .debug_commit_reg_waddr_1(debug_commit_reg_waddr_o_1),
        .debug_commit_reg_wdata_1(debug_commit_reg_wdata_o_1),
        .debug_commit_pc_2       (debug_commit_pc_o_2),
        .debug_commit_valid_2    (debug_commit_valid_o_2),
        .debug_commit_instr_2    (debug_commit_instr_o_2),
        .debug_commit_wreg_2     (debug_commit_wreg_o_2),
        .debug_commit_reg_waddr_2(debug_commit_reg_waddr_o_2),
        .debug_commit_reg_wdata_2(debug_commit_reg_wdata_o_2),
        .debug_reg               (debug_reg),
        .csr_diff                (csr_diff),
        .Instram_branch_flag     (Instram_branch_flag)
    );

`ifdef DUMP_WAVEFORM

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, u_cpu_top);
    end

`endif

`ifndef DIFFTEST

    ram u_ram (
        .clock        (clock),
        .reset        (reset),
        .ce           (chip_enable),
        .raddr_1      (ram_raddr_1),
        .rdata_1      (ram_rdata_1),
        .raddr_2      (ram_raddr_2),
        .rdata_2      (ram_rdata_2),
        .waddr        (ram_waddr),
        .wdata        (ram_wdata),
        .wen          (ram_wen),
        .branch_flag_i(Instram_branch_flag)
    );
`endif


    data_ram u_data_ram (
        .clk(clock),
        .ce_1(dram_ce_1),
        .we_1(dram_we_1),
        .pc_1(dram_pc_1),
        .addr_1(dram_addr_1),
        .sel_1(dram_sel_1),
        .data_i_1(dram_data_i_1),
        .data_o_1(dram_data_o_1),
        .ce_2(dram_ce_2),
        .we_2(dram_we_2),
        .pc_2(dram_pc_2),
        .addr_2(dram_addr_2),
        .sel_2(dram_sel_2),
        .data_i_2(dram_data_i_2),
        .data_o_2(dram_data_o_2)
    );


    //dual_data_rom u_dual_data_rom(
    //            .clka(clock),
    //           .rsta(reset),
    //            .wea(dram_sel_1),
    //            .addra(dram_addr_1),
    //            .dina(dram_data_i_1),
    //            .douta(dram_data_o_1),
    //            .clkb(clock),
    //            .rstb(reset),
    //            .enb(1'b1),
    //            .web(dram_sel_2),
    //           .addrb(dram_addr_2),
    //            .dinb(dram_data_i_2),
    //            .doutb(dram_data_o_2)

    //);

`ifdef DIFFTEST

    reg coreid = 0;
    reg [7:0] index = 0;
    wire reset_n;
    assign reset_n = ~reset;



    wire [31:0] ram_rIdx = (ram_raddr - 32'h1c000000) >> 2;

    reg [63:0] cycleCnt;
    reg [63:0] instrCnt;

    reg [`RegBus] debug_commit_pc_i_1;
    reg debug_commit_valid_i_1;
    reg [`InstBus] debug_commit_instr_i_1;
    reg debug_commit_wreg_i_1;
    reg [`RegAddrBus] debug_commit_reg_waddr_i_1;
    reg [`RegBus] debug_commit_reg_wdata_i_1;

    reg [`RegBus] debug_commit_pc_i_2;
    reg debug_commit_valid_i_2;
    reg [`InstBus] debug_commit_instr_i_2;
    reg debug_commit_wreg_i_2;
    reg [`RegAddrBus] debug_commit_reg_waddr_i_2;
    reg [`RegBus] debug_commit_reg_wdata_i_2;

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            cycleCnt <= 0;
            instrCnt <= 0;
            debug_commit_instr_i_1 <= 0;
            debug_commit_valid_i_1 <= 0;
            debug_commit_pc_i_1 <= 0;
            debug_commit_wreg_i_1 <= 0;
            debug_commit_reg_waddr_i_1 <= 0;
            debug_commit_reg_wdata_i_1 <= 0;
            debug_commit_instr_i_2 <= 0;
            debug_commit_valid_i_2 <= 0;
            debug_commit_pc_i_2 <= 0;
            debug_commit_wreg_i_2 <= 0;
            debug_commit_reg_waddr_i_2 <= 0;
            debug_commit_reg_wdata_i_2 <= 0;
        end else begin
            cycleCnt <= cycleCnt + 1;
            instrCnt <= instrCnt + debug_commit_valid__i1 + debug_commit_valid_i_2;
            debug_commit_instr_i_1 <= debug_commit_instr_o_1;
            debug_commit_valid_i_1 <= debug_commit_valid_o_1 & chip_enable;
            debug_commit_pc_i_1 <= debug_commit_pc_o_1;
            debug_commit_wreg_i_1 <= debug_commit_wreg_o_1;
            debug_commit_reg_waddr_i_1 <= debug_commit_reg_waddr_o_1;
            debug_commit_reg_wdata_i_1 <= debug_commit_reg_wdata_o_1;
            debug_commit_instr_i_2 <= debug_commit_instr_o_2;
            debug_commit_valid_i_2 <= debug_commit_valid_o_2 & chip_enable;
            debug_commit_pc_i_2 <= debug_commit_pc_o_2;
            debug_commit_wreg_i_2 <= debug_commit_wreg_o_2;
            debug_commit_reg_waddr_i_2 <= debug_commit_reg_waddr_o_2;
            debug_commit_reg_wdata_i_2 <= debug_commit_reg_wdata_o_2;
            ram_rdata <= ramhelper_rdata;
        end
    end

    DifftestTrapEvent difftest_trap_event (
        .clock(clock),
        .coreid(coreid),
        .valid(),
        .code(),
        .pc(debug_commit_pc),
        .cycleCnt(cycleCnt),
        .instrCnt(instrCnt)
    );

    RAMHelper ram_helper (
        .clk(clock),
        .en(chip_enable),
        .rIdx(ram_rIdx),
        .rdata(ramhelper_rdata),
        .wIdx(),
        .wdata(),
        .wmask(),
        .wen()
    );

    DifftestInstrCommit difftest_instr_commit_1 (
        .clock(clock),
        .coreid(coreid),
        .index(index),
        .valid(debug_commit_valid_i_1), // Non-zero means valid, checked per-cycle, if valid, instr count as as commit
        .pc(debug_commit_pc_i_1),
        .instr(debug_commit_instr_i_1),
        .skip(),
        .is_TLBFILL(),
        .TLBFILL_index(),
        .is_CNTinst(),
        .timer_64_value(),
        .wen(debug_commit_wreg_i_1),
        .wdest(debug_commit_reg_waddr_i_1),
        .wdata(debug_commit_reg_wdata_i_1)
    );

    DifftestInstrCommit difftest_instr_commit_2 (
        .clock(clock),
        .coreid(coreid),
        .index(index),
        .valid(debug_commit_valid_i_2), // Non-zero means valid, checked per-cycle, if valid, instr count as as commit
        .pc(debug_commit_pc_i_2),
        .instr(debug_commit_instr_i_2),
        .skip(),
        .is_TLBFILL(),
        .TLBFILL_index(),
        .is_CNTinst(),
        .timer_64_value(),
        .wen(debug_commit_wreg_i_2),
        .wdest(debug_commit_reg_waddr_i_2),
        .wdata(debug_commit_reg_wdata_i_2)
    );

    DifftestArchIntRegState difftest_arch_int_reg_state (
        .clock (clock),
        .coreid(coreid),
        .gpr_0 (debug_reg[31:0]),
        .gpr_1 (debug_reg[63:32]),
        .gpr_2 (debug_reg[95:64]),
        .gpr_3 (debug_reg[127:96]),
        .gpr_4 (debug_reg[159:128]),
        .gpr_5 (debug_reg[191:160]),
        .gpr_6 (debug_reg[223:192]),
        .gpr_7 (debug_reg[255:224]),
        .gpr_8 (debug_reg[287:256]),
        .gpr_9 (debug_reg[319:288]),
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
