`include "core_types.sv"
`include "core_config.sv"
`include "csr_defines.sv"
`include "pipeline/3_execution/alu.sv"
`include "TLB/tlb_types.sv"
`include "muldiv/mul_unit.sv"
`include "muldiv/div_unit.sv"

module ex
    import core_types::*;
    import core_config::*;
    import csr_defines::*;
    import tlb_types::*;
(
    input logic clk,
    input logic rst,

    // Pipeline control signals
    input  logic flush,
    input  logic clear,
    input  logic advance,
    output logic advance_ready,

    // <- Dispatch
    // Information from dispatch
    input dispatch_ex_struct dispatch_i,

    // -> MEM
    output ex_mem_struct ex_o_buffer,

    // <- CSR
    input [63:0] timer_64,
    input [31:0] tid,
    input csr_to_mem_struct csr_ex_signal,

    // EX next FTQ pc query
    output logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] ftq_query_addr_o,
    input logic [ADDR_WIDTH-1:0] ftq_query_pc_i,

    // EX redirect signals
    output logic ex_redirect_o,
    output logic [ADDR_WIDTH-1:0] ex_redirect_target_o,
    output logic ex_is_branch_o,
    output logic ex_jump_target_mispredict_o,
    output logic [ADDR_WIDTH-1:0] ex_jump_target_addr_o,
    output logic [ADDR_WIDTH-1:0] ex_fall_through_addr_o,
    output logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] ex_redirect_ftq_id_o,

    // -> Dispatch
    output data_forward_t data_forward_o,

    // -> TLB
    output data_tlb_rreq_t tlb_rreq_o
);
    ex_mem_struct ex_o;

    reg [`RegBus] logicout;
    reg [`RegBus] shiftout;
    reg [`RegBus] moveout;
    reg [`RegBus] arithout;

    // Assign input /////////////////////////////
    instr_info_t instr_info;
    special_info_t special_info;
    //ALU
    logic [`AluOpBus] aluop_i;
    logic [`AluSelBus] alusel_i;

    logic [1:0][`RegAddrBus] read_reg_addr;
    // Determine oprands
    logic [`RegBus] oprand1, oprand2, imm;

    logic [`RegBus] inst_i, inst_pc_i;


    logic wreg_i;
    logic [`RegAddrBus] wd_i;

    logic [`InstAddrBus] debug_mem_addr_o;

    csr_write_signal csr_signal_i, csr_test;

    logic [`RegBus] csr_reg_data;

    //cache ins
    logic cacop_instr, icacop_inst, dcacop_inst, icacop_op_en, dcacop_op_en;
    logic [4:0] cacop_op;
    logic [1:0] cacop_op_mode;

    logic excp_ale, excp_ine, excp;
    logic [9:0] excp_num;
    logic
        access_mem,
        mem_load_op,
        mem_store_op,
        mem_b_op,
        mem_h_op,
        pg_mode,
        da_mode,
        cacop_op_mode_di;
    logic uncache_en;

    logic dmw0_en, dmw1_en, tlbsrch_en, data_fetch, trans_en;
    logic [`RegBus] tlb_vaddr;

    //比较模块
    logic reg1_lt_reg2;
    logic [`RegBus] oprand2_mux;
    logic [`RegBus] result_compare;
    logic last_instr_branch;
    logic [ADDR_WIDTH-1:0] real_next_pc;
    logic [`RegBus] pc_delay;

    // Branch Unit
    logic branch_flag;
    logic branch_direction_mispredict;
    logic branch_target_mispredict;

    //mul and div
    logic [1:0] muldiv_op;  // High effective
    logic [2:0] mul_op;
    logic [2:0] div_op;
    logic muldiv_finish, muldiv_already_finish;
    logic [`RegBus] div_result;

    logic mul_start;
    logic mul_already_start;
    logic mul_finish;
    logic mul_busy;
    logic [`RegBus] mul_result;

    logic div_start;
    logic div_already_start;
    logic div_finish;
    logic is_running;
    logic [`RegBus] quotient;
    logic [`RegBus] remainder;

    logic muldiv_stall;

    always_ff @(posedge clk) begin
        pc_delay <= inst_pc_i;
    end

    // Branch
    logic [ADDR_WIDTH-1:0] jump_target_address;
    logic [ADDR_WIDTH-1:0] fall_through_address;

    assign instr_info = dispatch_i.instr_info;
    assign special_info = dispatch_i.instr_info.special_info;

    // ALU 
    assign aluop_i = dispatch_i.aluop;
    assign alusel_i = dispatch_i.alusel;

    assign read_reg_addr = dispatch_i.read_reg_addr;

    assign oprand1 = dispatch_i.oprand1;
    assign oprand2 = dispatch_i.oprand2;
    assign imm = dispatch_i.imm;

    assign inst_i = dispatch_i.instr_info.instr;
    assign inst_pc_i = dispatch_i.instr_info.pc;


    assign wd_i = dispatch_i.reg_write_addr;
    assign wreg_i = dispatch_i.reg_write_valid;

    assign ex_o.aluop = aluop_i;

    assign debug_mem_addr_o = ex_o.mem_addr;

    // TODO:fix vppn select
    assign ex_o.mem_addr = oprand1 + imm;
    assign ex_o.reg2 = oprand2;

    // Data forwarding 
    assign data_forward_o = (muldiv_op != 0) ? {ex_o.wreg, muldiv_already_finish, ex_o.waddr, ex_o.wdata,ex_o.csr_signal} : // Mul or Div op
    {ex_o.wreg, ~mem_load_op, ex_o.waddr, ex_o.wdata,ex_o.csr_signal}; // if is mem_load_op, then data is no valid, else data is valid


    assign csr_signal_i = dispatch_i.csr_signal;
    assign csr_test = ex_o.csr_signal;

    //写入csr的数据，对csrxchg指令进行掩码处理
    assign ex_o.csr_signal.we = csr_signal_i.we;
    assign ex_o.csr_signal.addr = csr_signal_i.addr;
    assign ex_o.csr_signal.data = (aluop_i ==`EXE_CSRXCHG_OP) ? ((oprand1 & oprand2) | (~oprand2 & dispatch_i.csr_reg_data)) : oprand1;


    assign csr_reg_data = aluop_i == `EXE_RDCNTID_OP ? tid :
                          aluop_i == `EXE_RDCNTVL_OP ? timer_64[31:0] :
                          aluop_i == `EXE_RDCNTVH_OP ? timer_64[63:32] :
                          dispatch_i.csr_reg_data;

    assign cacop_op = inst_i[4:0];
    assign cacop_instr = aluop_i == `EXE_CACOP_OP;
    assign icacop_inst = cacop_instr && (cacop_op[2:0] == 3'b0);
    assign icacop_op_en = icacop_inst && !excp && !(flush);
    assign dcacop_inst = cacop_instr && (cacop_op[2:0] == 3'b1);
    assign dcacop_op_en = dcacop_inst && !excp && !(flush);
    assign cacop_op_mode = {2{dcacop_op_en}} & cacop_op[4:3];

    assign excp_ale = access_mem && ((mem_b_op & 1'b0)| (mem_h_op & ex_o.mem_addr[0])| 
                    (!(mem_b_op | mem_h_op) & (ex_o.mem_addr[0] | ex_o.mem_addr[1]))) ;
    assign excp_ine = aluop_i == `EXE_INVTLB_OP && imm > 32'd6;
    assign excp_num = {excp_ale, instr_info.excp_num[8:0] | {1'b0, excp_ine, 7'b0}};
    assign excp = instr_info.excp | excp_ale | excp_ine;

    assign access_mem = mem_load_op | mem_store_op;

    assign mem_load_op = special_info.mem_load;

    assign mem_store_op = special_info.mem_store;
    assign mem_b_op = special_info.mem_b_op;
    assign mem_h_op = special_info.mem_h_op;

    // notify ctrl is ready to advance
    assign advance_ready = ~muldiv_stall;

    //////////////////////////////////////////////////////////////////////////////////////
    // TLB request
    //////////////////////////////////////////////////////////////////////////////////////

    assign dmw0_en = ((csr_ex_signal.csr_dmw0[`PLV0] && csr_ex_signal.csr_plv == 2'd0) || (csr_ex_signal.csr_dmw0[`PLV3] && csr_ex_signal.csr_plv == 2'd3)) && (tlb_vaddr[31:29] == csr_ex_signal.csr_dmw0[`VSEG]);
    assign dmw1_en = ((csr_ex_signal.csr_dmw1[`PLV0] && csr_ex_signal.csr_plv == 2'd0) || (csr_ex_signal.csr_dmw1[`PLV3] && csr_ex_signal.csr_plv == 2'd3)) && (tlb_vaddr[31:29] == csr_ex_signal.csr_dmw1[`VSEG]);

    assign pg_mode = !csr_ex_signal.csr_da && csr_ex_signal.csr_pg;
    assign da_mode = csr_ex_signal.csr_da && !csr_ex_signal.csr_pg;

    assign tlbsrch_en = aluop_i == `EXE_TLBSRCH_OP;
    assign data_fetch = (access_mem | tlbsrch_en | icacop_op_en | dcacop_op_en) & instr_info.valid;

    assign tlb_vaddr = ex_o.mem_addr;

    // Addr translate mode for DCache, pull down if instr is invalid
    assign cacop_op_mode_di = dcacop_op_en && ((cacop_op_mode == 2'b0) || (cacop_op_mode == 2'b1));
    assign trans_en = (access_mem | icacop_op_en | dcacop_op_en) && pg_mode && !dmw0_en && !dmw1_en && !cacop_op_mode_di;
    assign uncache_en = da_mode ? csr_ex_signal.csr_datm == 0 : 
                        dmw0_en ? csr_ex_signal.csr_dmw0[`DMW_MAT] == 0 :
                        dmw1_en ? csr_ex_signal.csr_dmw1[`DMW_MAT] == 0: 0;

    always_comb begin
        if (flush) tlb_rreq_o = 0;
        else if (advance) begin
            tlb_rreq_o.fetch = data_fetch;
            tlb_rreq_o.trans_en = trans_en;
            tlb_rreq_o.dmw0_en = dmw0_en;
            tlb_rreq_o.dmw1_en = dmw1_en;
            tlb_rreq_o.tlbsrch_en = tlbsrch_en;
            tlb_rreq_o.cacop_op_mode_di = cacop_op_mode_di;
            tlb_rreq_o.vaddr = tlb_vaddr;
        end else tlb_rreq_o = 0;
    end


    alu u_alu (
        .rst(rst),

        .inst_pc_i(inst_pc_i),
        .aluop(aluop_i),
        .oprand1(oprand1),
        .oprand2(oprand2),
        .imm(imm),

        .logicout(logicout),
        .shiftout(shiftout),
        .branch_flag(branch_flag),
        .branch_target_address(jump_target_address)
    );


    assign oprand2_mux = (aluop_i == `EXE_SLT_OP) ? ~oprand2 + 32'b1 : oprand2; // shifted encoding when signed comparison
    assign result_compare = oprand1 + oprand2_mux;
    assign reg1_lt_reg2  = (aluop_i == `EXE_SLT_OP) ? ((oprand1[31] && !oprand2[31]) || (!oprand1[31] && !oprand2[31] && result_compare[31])||
			               (oprand1[31] && oprand2[31] && result_compare[31])) : (oprand1 < oprand2);

    // Divider and Multiplier
    // Multi-cycle

    assign muldiv_finish = (mul_finish & mul_already_start) | (div_finish & div_already_start);
    always_ff @(posedge clk) begin
        if (rst) begin
            muldiv_already_finish <= 0;
            div_result <= 0;
        end else if (advance) begin
            muldiv_already_finish <= 0;
            div_result <= 0;
        end else if (muldiv_finish) begin
            muldiv_already_finish <= 1;
            div_result <= arithout;
        end
    end
    always_comb begin
        case (aluop_i)
            `EXE_DIV_OP, `EXE_DIVU_OP, `EXE_MODU_OP, `EXE_MOD_OP: begin
                muldiv_op = 2'b01;
            end
            `EXE_MUL_OP, `EXE_MULH_OP, `EXE_MULHU_OP: begin
                muldiv_op = 2'b10;
            end
            default: begin
                muldiv_op = 0;
            end
        endcase
    end
    always_comb begin
        mul_op = 0;
        div_op = 0;
        case (aluop_i)
            `EXE_MUL_OP:   mul_op = 3'h1;
            `EXE_MULH_OP:  mul_op = 3'h2;
            `EXE_MULHU_OP: mul_op = 3'h3;
            `EXE_DIV_OP:   div_op = 3'h4;
            `EXE_DIVU_OP:  div_op = 3'h5;
            `EXE_MOD_OP:   div_op = 3'h6;
            `EXE_MODU_OP:  div_op = 3'h7;
            default: begin
                mul_op = 0;
                div_op = 0;
            end
        endcase
    end



    always_ff @(posedge clk) begin
        if (rst) begin
            mul_start <= 0;
            mul_already_start <= 0;
        end else if (mul_op != 3'b0 & !mul_already_start & !muldiv_already_finish & !flush) begin
            mul_start <= 1;
            mul_already_start <= 1;
        end else if (pc_delay != inst_pc_i) mul_already_start <= 0;
        else begin
            mul_start <= 0;
            mul_already_start = mul_already_start;
        end
    end

    mul_unit u_mul_unit (
        .clk(clk),
        .rst(rst),

        .start(mul_start),
        .rs1(oprand1),
        .rs2(oprand2),
        .op(mul_op[1:0]),

        .ready(mul_busy),
        .done(mul_finish),
        .mul_result(mul_result)
    );

    always_ff @(posedge clk) begin
        if (rst) div_already_start <= 0;
        else if (advance) div_already_start <= 0;
        else if (div_start) div_already_start <= 1;
    end

    always_ff @(posedge clk) begin
        if (rst) div_start <= 0;
        else if (div_start | div_already_start) div_start <= 0;
        else if (div_op != 3'b0 & !div_already_start & !muldiv_already_finish & ~flush& !is_running)
            div_start <= 1;
    end

    div_unit u_div_unit (
        .clk(clk),
        .rst(rst),

        .op(div_op[1:0]),
        .dividend(oprand1),
        .divisor((oprand2 == 0 ? 1 : oprand2)),
        .divisor_is_zero(0),
        .start(div_start),

        .is_running(is_running),
        .remainder_out(remainder),
        .quotient_out(quotient),
        .done(div_finish)
    );


    assign muldiv_stall = muldiv_op != 2'b0 & !muldiv_already_finish;  // CACOP

    always @(*) begin
        if (rst == `RstEnable) begin
            arithout = 0;
        end else begin
            case (aluop_i)
                `EXE_ADD_OP: arithout = oprand1 + oprand2;
                `EXE_SUB_OP: arithout = oprand1 - oprand2;
                `EXE_MUL_OP, `EXE_MULH_OP, `EXE_MULHU_OP: arithout = mul_result;
                `EXE_DIV_OP, `EXE_DIVU_OP: begin
                    arithout = muldiv_finish ? quotient : div_result;
                end
                `EXE_MODU_OP, `EXE_MOD_OP: begin
                    arithout = muldiv_finish ? remainder : div_result;
                end
                `EXE_SLT_OP, `EXE_SLTU_OP: arithout = {31'b0, reg1_lt_reg2};
                default: begin
                    arithout = 0;
                end
            endcase
        end
    end

    ///////////////////////////////////////////////////////////////////////////////////
    // Branch Unit
    ///////////////////////////////////////////////////////////////////////////////////
    // FTQ query
    assign ftq_query_addr_o = $clog2(FRONTEND_FTQ_SIZE)'(instr_info.ftq_id + 1);

    // Any mispredict will trigger a redirection
    // Mispredict is defined as:
    // 1. branch direction mispredict
    // 2. jump target mispredict
    assign branch_direction_mispredict = branch_flag ^ special_info.predicted_taken;
    assign branch_target_mispredict = (branch_flag & special_info.predicted_taken & (jump_target_address != ftq_query_pc_i))  | (~branch_flag & ~special_info.predicted_taken &  instr_info.is_last_in_block & (fall_through_address != ftq_query_pc_i));

    // Redirect is triggered when any of the mispredict happens
    assign ex_redirect_o = (branch_direction_mispredict | branch_target_mispredict) && advance;
    assign ex_redirect_target_o = branch_flag ? jump_target_address : fall_through_address;

    // BPU meta is feedback to FTQ whenever a branch is executed
    assign ex_is_branch_o = special_info.is_branch;
    assign ex_jump_target_mispredict_o = branch_target_mispredict | (branch_flag & ~instr_info.is_last_in_block);
    assign ex_redirect_ftq_id_o = instr_info.ftq_id;
    assign ex_jump_target_addr_o = jump_target_address;
    assign ex_fall_through_addr_o = fall_through_address;
    assign fall_through_address = inst_pc_i + 4;

    ////////////////////////////////////////////////////////////////////////////////////


    always @(*) begin
        if (rst == `RstEnable) begin
            moveout = `ZeroWord;
        end else begin
            case (aluop_i)
                `EXE_LUI_OP: begin
                    moveout = oprand2;
                end
                `EXE_PCADD_OP: begin
                    moveout = oprand2 + ex_o.instr_info.pc;
                end
                default: begin
                    moveout = `ZeroWord;
                end
            endcase
        end
    end

    always_comb begin
        ex_o.instr_info = instr_info;
        ex_o.instr_info.excp = excp;
        ex_o.instr_info.excp_num = excp_num;

        // If the branch taken, then this basic block should be ended
        if (branch_flag) begin
            ex_o.instr_info.is_last_in_block = 1;
            ex_o.instr_info.special_info.is_taken = 1;
        end

        ex_o.aluop = aluop_i;
        ex_o.waddr = wd_i;
        ex_o.wreg = wreg_i;
        ex_o.timer_64 = timer_64;
        ex_o.cacop_en = cacop_instr;
        ex_o.icache_op_en = icacop_op_en;
        ex_o.dcache_op_en = dcacop_op_en;
        ex_o.cacop_op = cacop_op;
        ex_o.data_addr_trans_en = trans_en;
        ex_o.data_uncache_en = uncache_en;
        ex_o.dmw0_en = dmw0_en;
        ex_o.dmw1_en = dmw1_en;
        ex_o.cacop_op_mode_di = cacop_op_mode_di;
        ex_o.inv_i = aluop_i == `EXE_INVTLB_OP ? {1'b1, oprand1[9:0], oprand2[31:13], imm[4:0]} : 0;
        case (alusel_i)
            `EXE_RES_LOGIC: begin
                ex_o.wdata = logicout;
            end
            `EXE_RES_SHIFT: begin
                ex_o.wdata = shiftout;
            end
            `EXE_RES_MOVE: begin
                ex_o.wdata = moveout;
            end
            `EXE_RES_ARITH: begin
                ex_o.wdata = arithout;
            end
            `EXE_RES_JUMP: begin
                ex_o.wdata = inst_pc_i + 4;
            end
            `EXE_RES_CSR: begin
                ex_o.wdata = csr_reg_data;
            end
            default: begin
                ex_o.wdata = 0;
            end
        endcase
    end



    always_ff @(posedge clk) begin
        if (rst) ex_o_buffer <= 0;
        else if (flush | clear) ex_o_buffer <= 0;
        else if (advance) ex_o_buffer <= ex_o;
    end

`ifdef SIMU
    logic [31:0] wdata;
    assign wdata = ex_o.wdata;
`endif
endmodule
