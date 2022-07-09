`include "core_types.sv"
`include "core_config.sv"
`include "csr_defines.sv"
`include "muldiv/mul.sv"
`include "pipeline/3_execution/alu.sv"

module ex
    import core_types::*;
    import core_config::*;
    import csr_defines::*;
(
    input logic clk,
    input logic rst,

    // <- Dispatch
    // Information from dispatch
    input dispatch_ex_struct dispatch_i,

    // <- MEM 


    input logic [18:0] csr_vppn,
    input logic llbit,

    // -> MEM
    output ex_mem_struct ex_o_buffer,

    // <- CSR
    input [63:0] timer_64,
    input [31:0] tid,
    input csr_to_mem_struct csr_ex_signal,

    // Multi-cycle ALU stallreq
    output logic stallreq,

    // -> Ctrl
    // Redirect is only triggered when mispredict happens
    output logic ex_redirect_o,
    output logic [ADDR_WIDTH-1:0] ex_redirect_target_o,
    output logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] ex_redirect_ftq_id_o,

    output ex_dispatch_struct ex_data_forward,

    // ->TLB
    output ex_to_tlb_struct ex_tlb_signal,

    // <-> Cache
    output logic icacop_op_en,
    input logic icacop_op_ack_i,
    output logic dcacop_op_en,
    output logic [1:0] cacop_op_mode,

    input logic excp_flush,
    input logic ertn_flush,

    // Stall & flush
    input logic [1:0] stall,  // {mem_wb, ex}
    input logic flush

);
    ex_mem_struct ex_o;

    reg [`RegBus] logicout;
    reg [`RegBus] shiftout;
    reg [`RegBus] moveout;
    reg [63:0] arithout;

    // Assign input /////////////////////////////
    instr_info_t instr_info;
    special_info_t special_info;
    assign instr_info   = dispatch_i.instr_info;
    assign special_info = dispatch_i.instr_info.special_info;

    // ALU 
    logic [ `AluOpBus] aluop_i;
    logic [`AluSelBus] alusel_i;
    assign aluop_i  = dispatch_i.aluop;
    assign alusel_i = dispatch_i.alusel;

    logic [1:0][`RegAddrBus] read_reg_addr;
    assign read_reg_addr = dispatch_i.read_reg_addr;

    // Determine oprands
    logic [`RegBus] oprand1, oprand2, imm;
    assign oprand1 = dispatch_i.oprand1;
    assign oprand2 = dispatch_i.use_imm ? dispatch_i.imm : dispatch_i.oprand2;
    assign imm = dispatch_i.imm;

    logic [`RegBus] inst_i, inst_pc_i;
    assign inst_i = dispatch_i.instr_info.instr;
    assign inst_pc_i = dispatch_i.instr_info.pc;

    logic wreg_i;
    logic [`RegAddrBus] wd_i;
    assign wd_i = dispatch_i.reg_write_addr;
    assign wreg_i = dispatch_i.reg_write_valid;

    assign ex_o.aluop = aluop_i;
    logic [`InstAddrBus] debug_mem_addr_o;
    assign debug_mem_addr_o = ex_o.mem_addr;

    // TODO:fix vppn select
    assign ex_o.mem_addr = oprand1 + imm;
    assign ex_o.reg2 = oprand2;

    assign ex_data_forward = {ex_o.wreg & !mem_load_op, ex_o.waddr, ex_o.wdata, ex_o.aluop};

    csr_write_signal csr_signal_i, csr_test;
    assign csr_signal_i = dispatch_i.csr_signal;
    assign csr_test = ex_o.csr_signal;

    //写入csr的数据，对csrxchg指令进行掩码处理
    assign ex_o.csr_signal.we = csr_signal_i.we;
    assign ex_o.csr_signal.addr = csr_signal_i.addr;
    assign ex_o.csr_signal.data = (aluop_i ==`EXE_CSRXCHG_OP) ? ((oprand1 & oprand2) | (~oprand2 & dispatch_i.csr_reg_data)) : oprand1;

    logic [`RegBus] csr_reg_data;
    assign csr_reg_data = aluop_i == `EXE_RDCNTID_OP ? tid :
                          aluop_i == `EXE_RDCNTVL_OP ? timer_64[31:0] :
                          aluop_i == `EXE_RDCNTVH_OP ? timer_64[63:32] :
                          dispatch_i.csr_reg_data;


    //cache ins
    logic cacop_instr, icacop_inst, dcacop_inst;
    logic [4:0] cacop_op;
    assign cacop_op = inst_i[4:0];
    assign cacop_instr = aluop_i == `EXE_CACOP_OP;
    assign icacop_inst = cacop_instr && (cacop_op[2:0] == 3'b0);
    assign icacop_op_en = icacop_inst && !excp && !(flush | excp_flush | ertn_flush);
    assign dcacop_inst = cacop_instr && (cacop_op[2:0] == 3'b1);
    assign dcacop_op_en = dcacop_inst && !excp && !(flush | excp_flush | ertn_flush);
    assign cacop_op_mode = cacop_op[4:3];

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

    logic dmw0_en, dmw1_en, tlbsrch_en_o, data_fetch, data_addr_trans_en;
    logic [`RegBus] tlb_vaddr;
    assign dmw0_en = ((csr_ex_signal.csr_dmw0[`PLV0] && csr_ex_signal.csr_plv == 2'd0) || (csr_ex_signal.csr_dmw0[`PLV3] && csr_ex_signal.csr_plv == 2'd3)) && (tlb_vaddr[31:29] == csr_ex_signal.csr_dmw0[`VSEG]);
    assign dmw1_en = ((csr_ex_signal.csr_dmw1[`PLV0] && csr_ex_signal.csr_plv == 2'd0) || (csr_ex_signal.csr_dmw1[`PLV3] && csr_ex_signal.csr_plv == 2'd3)) && (tlb_vaddr[31:29] == csr_ex_signal.csr_dmw1[`VSEG]);

    assign pg_mode = !csr_ex_signal.csr_da && csr_ex_signal.csr_pg;
    assign da_mode = csr_ex_signal.csr_da && !csr_ex_signal.csr_pg;

    assign tlbsrch_en_o = aluop_i == `EXE_TLBSRCH_OP;
    assign data_fetch = access_mem | tlbsrch_en_o;

    assign tlb_vaddr = ex_o.mem_addr;

    // Addr translate mode for DCache, pull down if instr is invalid
    assign cacop_op_mode_di = dcacop_op_en && ((cacop_op_mode == 2'b0) || (cacop_op_mode == 2'b1));
    assign data_addr_trans_en = access_mem && pg_mode && !dmw0_en && !dmw1_en && !cacop_op_mode_di && dispatch_i.instr_info.valid;

    always_comb begin
        if (rst) ex_tlb_signal = 0;
        else if (flush) ex_tlb_signal = 0;
        else if (stall[0] | stall[1]) ex_tlb_signal = 0;
        else
            ex_tlb_signal = {
                data_addr_trans_en, dmw0_en, dmw1_en, data_fetch, tlbsrch_en_o, tlb_vaddr
            };
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
        .branch_target_address(ex_redirect_target_o)
    );

    //比较模块
    logic reg1_lt_reg2;
    logic [`RegBus] oprand2_mux;
    logic [`RegBus] result_compare;

    assign oprand2_mux = (aluop_i == `EXE_SLT_OP) ? ~oprand2 + 32'b1 : oprand2; // shifted encoding when signed comparison
    assign result_compare = oprand1 + oprand2_mux;
    assign reg1_lt_reg2  = (aluop_i == `EXE_SLT_OP) ? ((oprand1[31] && !oprand2[31]) || (!oprand1[31] && !oprand2[31] && result_compare[31])||
			               (oprand1[31] && oprand2[31] && result_compare[31])) : (oprand1 < oprand2);


    // Divider and Multiplier
    // Multi-cycle
    // logic muldiv_op;  // High effective
    // always_comb begin
    //     case (aluop_i)
    //         `EXE_DIV_OP, `EXE_DIVU_OP, `EXE_MODU_OP, `EXE_MOD_OP: begin
    //             muldiv_op = 1;
    //         end
    //         default: begin
    //             muldiv_op = 0;
    //         end
    //     endcase
    // end
    // logic [2:0] muldiv_para;  // 0-7 muldiv mode selection
    // always_comb begin
    //     case (aluop_i)
    //         `EXE_MUL_OP:   muldiv_para = 3'h0;
    //         `EXE_MULH_OP:  muldiv_para = 3'h1;
    //         `EXE_MULHU_OP: muldiv_para = 3'h3;
    //         `EXE_DIV_OP:   muldiv_para = 3'h4;
    //         `EXE_DIVU_OP:  muldiv_para = 3'h5;
    //         `EXE_MOD_OP:   muldiv_para = 3'h6;
    //         `EXE_MODU_OP:  muldiv_para = 3'h7;
    //         default: begin
    //             muldiv_para = 0;
    //         end
    //     endcase
    // end
    // logic [31:0] muldiv_result;
    // logic muldiv_finished;
    // logic muldiv_ack;
    // logic muldiv_busy_r;
    // logic muldiv_init;
    // logic muldiv_busy;  // Low means busy
    // always_ff @(posedge clk) begin
    //     if (rst) muldiv_busy_r <= 0;
    //     else if (flush | excp_flush | ertn_flush) muldiv_busy_r <= 0;
    //     else if (muldiv_init) muldiv_busy_r <= 1;
    //     else if (muldiv_ack) muldiv_busy_r <= 0;
    // end
    // always_comb begin
    //     muldiv_init = muldiv_op & ~muldiv_busy_r & ~stall[1];
    //     muldiv_ack  = muldiv_finished & muldiv_op & ~stall[1];
    // end
    // mul u_mul (
    //     .clk           (clk),
    //     .rst           (rst),
    //     .clear_pipeline(flush),
    //     .mul_para      (muldiv_para),
    //     .mul_initial   (muldiv_init),
    //     .mul_rs0       (oprand1),
    //     .mul_rs1       (oprand2 == 0 ? 1 : oprand2),
    //     .mul_ready     (muldiv_busy),
    //     .mul_finished  (muldiv_finished),             // 1 means finished
    //     .mul_data      (muldiv_result),
    //     .mul_ack       (muldiv_ack)
    // );


    // assign stallreq = (muldiv_op & ~muldiv_finished) | // Multiply & Division
    //             (icacop_inst & ~icacop_op_ack_i); // CACOP

    always @(*) begin
        if (rst == `RstEnable) begin
            arithout = 0;
        end else begin
            case (aluop_i)
                `EXE_ADD_OP: arithout = oprand1 + oprand2;
                `EXE_SUB_OP: arithout = oprand1 - oprand2;
                // `EXE_DIV_OP, `EXE_DIVU_OP, `EXE_MODU_OP, `EXE_MOD_OP: begin
                //     // Select result from multi-cycle divider
                //     arithout = muldiv_result;
                // end

                `EXE_MUL_OP: arithout = $signed(oprand1) * $signed(oprand2);
                `EXE_MULH_OP: arithout = ($signed(oprand1) * $signed(oprand2)) >> 32;
                `EXE_MULHU_OP: arithout = ($unsigned(oprand1) * $unsigned(oprand2)) >> 32;
                `EXE_DIV_OP: begin
                    if (oprand2 == 0) arithout = $signed(oprand1);
                    else arithout = ($signed(oprand1) / $signed(oprand2));
                end
                `EXE_DIVU_OP: begin
                    if (oprand2 == 0) arithout = $unsigned(oprand1);
                    else arithout = ($unsigned(oprand1) / $unsigned(oprand2));
                end
                `EXE_MODU_OP: arithout = ($unsigned(oprand1) % $unsigned(oprand2));
                `EXE_MOD_OP: begin
                    arithout = ($signed(oprand1) % $signed(oprand2));
                end
                `EXE_SLT_OP, `EXE_SLTU_OP: arithout = {31'b0, reg1_lt_reg2};
                default: begin
                    arithout = 0;
                end
            endcase
        end
    end


    // Only when taken & not predicted taken can ex do redirect
    assign ex_redirect_o = branch_flag && ~special_info.predicted_taken && ~stall[0];
    assign ex_redirect_ftq_id_o = ex_redirect_o ? instr_info.ftq_id : 0;


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
    logic [31:0] wdata;
    assign wdata = ex_o.wdata;

    always_comb begin
        ex_o.instr_info = stallreq ? 0 : dispatch_i.instr_info;
        ex_o.instr_info.excp = excp;
        ex_o.instr_info.excp_num = excp_num;

        // If the branch taken, then this basic block should be ended
        if (branch_flag) ex_o.instr_info.is_last_in_block = 1;

        ex_o.aluop = aluop_i;
        ex_o.waddr = wd_i;
        ex_o.wreg = wreg_i;
        ex_o.timer_64 = timer_64;
        ex_o.cacop_en = cacop_instr;
        ex_o.icache_op_en = icacop_op_en;
        ex_o.cacop_op = cacop_op;
        ex_o.data_addr_trans_en = data_addr_trans_en;
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
                ex_o.wdata = `ZeroWord;
            end
        endcase
    end



    always_ff @(posedge clk) begin
        if (rst) ex_o_buffer <= 0;
        else if (flush) ex_o_buffer <= 0;
        else if (stall[0] | stall[1]) ex_o_buffer <= ex_o_buffer;
        else ex_o_buffer <= ex_o;
    end


endmodule
