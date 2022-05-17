`include "pipeline_defines.sv"

module ex (
    input logic rst,

    // <- Dispatch
    // Information from dispatch
    input dispatch_ex_struct dispatch_i,

    input logic [18:0] csr_vppn,

    // -> MEM
    output ex_mem_struct ex_o,

    output logic stallreq,

    output logic branch_flag,
    output logic [`RegBus] branch_target_address,

    output ex_dispatch_struct ex_data_forward

);

    reg [`RegBus] logicout;
    reg [`RegBus] shiftout;
    reg [`RegBus] moveout;
    reg [`RegBus] arithout;
    reg [`RegBus] csr_out;
    assign csr_out = reg2_i;

    // Assign input
    logic [`AluOpBus] aluop_i;
    logic [`AluSelBus] alusel_i;
    assign aluop_i  = dispatch_i.aluop;
    assign alusel_i = dispatch_i.alusel;

    logic [`RegBus] reg1_i, reg2_i, imm;
    assign reg1_i = dispatch_i.oprand1;
    assign reg2_i = dispatch_i.oprand2;
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
    assign ex_o.mem_addr = reg1_i + {{20{inst_i[21]}}, inst_i[21:10]};
    assign ex_o.reg2 = reg2_i;

    assign ex_data_forward = {ex_o.wreg, ex_o.waddr, ex_o.wdata, ex_o.aluop};

    csr_write_signal csr_signal_i;
    assign csr_signal_i = dispatch_i.csr_signal;

    //写入csr的数据，对csrxchg指令进行掩码处理
    assign ex_o.csr_signal.we = csr_signal_i.we;
    assign ex_o.csr_signal.addr = csr_signal_i.addr;
    assign ex_o.csr_signal.data = (aluop_i ==`EXE_CSRXCHG_OP) ?((reg1_i & reg2_i) | (~reg1_i & csr_signal_i.data)) : csr_signal_i.data;

    logic excp_ale, excp_i;
    logic [9:0] excp_num;
    assign excp_ale = 1'b0;
    assign excp_num = {excp_ale, dispatch_i.excp_num};
    assign excp_i = dispatch_i.excp || excp_ale;
    assign ex_o.excp = excp_i;
    assign ex_o.excp_num = excp_num;
    assign ex_o.refetch = dispatch_i.refetch;

    always @(*) begin
        if (rst == `RstEnable) begin
            logicout = `ZeroWord;
        end else begin
            case (aluop_i)
                `EXE_OR_OP: begin
                    logicout = reg1_i | reg2_i;
                end
                `EXE_AND_OP: begin
                    logicout = reg1_i & reg2_i;
                end
                `EXE_XOR_OP: begin
                    logicout = reg1_i ^ reg2_i;
                end
                `EXE_NOR_OP: begin
                    logicout = ~(reg1_i | reg2_i);
                end
                default: begin
                    logicout = `ZeroWord;
                end
            endcase
        end
    end

    always @(*) begin
        if (rst == `RstEnable) begin
            shiftout = `ZeroWord;
        end else begin
            case (aluop_i)
                `EXE_SLL_OP: begin
                    shiftout = reg1_i << reg2_i[4:0];
                end
                `EXE_SRL_OP: begin
                    shiftout = reg1_i >> reg2_i[4:0];
                end
                `EXE_SRA_OP: begin
                    shiftout = ({32{reg1_i[31]}} << (6'd32-{1'b0,reg2_i[4:0]})) | reg1_i >> reg2_i[4:0];
                end
                default: begin
                    shiftout = `ZeroWord;
                end
            endcase
        end
    end

    //比较模块
    logic reg1_lt_reg2;
    logic [`RegBus] reg2_i_mux;
    logic [`RegBus] result_compare;

    assign reg2_i_mux = (aluop_i == `EXE_SLT_OP) ? ~reg2_i + 32'b1 : reg2_i; // shifted encoding when signed comparison
    assign result_compare = reg1_i + reg2_i_mux;
    assign reg1_lt_reg2  = (aluop_i == `EXE_SLT_OP) ? ((reg1_i[31] && !reg2_i[31]) || (!reg1_i[31] && !reg2_i[31] && result_compare[31])||
			               (reg1_i[31] && reg2_i[31] && result_compare[31])) : (reg1_i < reg2_i);


    //乘法模块

    logic [`RegBus] opdata1_mul;
    logic [`RegBus] opdata2_mul;
    logic [`DoubleRegBus] hilo_temp;
    reg [`DoubleRegBus] mulres;

    assign opdata1_mul = (((aluop_i == `EXE_MUL_OP) || (aluop_i == `EXE_MULH_OP))
                        && (reg1_i[31] == 1'b1)) ? (~reg1_i + 1) : reg1_i;

    assign opdata2_mul = (((aluop_i == `EXE_MUL_OP) || (aluop_i == `EXE_MULH_OP))
                        && (reg2_i[31] == 1'b1)) ? (~reg2_i + 1) : reg1_i;

    assign hilo_temp = opdata1_mul * opdata2_mul;

    always @(*) begin
        if (rst == `RstEnable) mulres = {`ZeroWord, `ZeroWord};
        else if ((aluop_i == `EXE_MUL_OP) || (aluop_i == `EXE_MULH_OP)) begin
            if (reg1_i[31] ^ reg2_i[31] == 1'b1) mulres = ~hilo_temp + 1;
            else mulres = hilo_temp;
        end else mulres = hilo_temp;
    end


    always @(*) begin
        if (rst == `RstEnable) begin
            arithout = `ZeroWord;
        end else begin
            case (aluop_i)
                `EXE_ADD_OP: arithout = reg1_i + reg2_i;
                `EXE_SUB_OP: arithout = reg1_i - reg2_i;
                `EXE_MUL_OP: arithout = mulres[31:0];
                `EXE_MULH_OP, `EXE_MULHU_OP: arithout = mulres[63:32];
                `EXE_DIV_OP: arithout = reg1_i / reg2_i;
                `EXE_MOD_OP: arithout = reg1_i % reg2_i;
                `EXE_SLT_OP, `EXE_SLTU_OP: arithout = {31'b0, reg1_lt_reg2};
                default: begin
                    arithout = `ZeroWord;
                end
            endcase
        end
    end

    always @(*) begin
        if (rst == `RstEnable) begin
            branch_flag = 1'b0;
            branch_target_address = `ZeroWord;
        end else begin
            // Default is not branching
            branch_flag = 1'b0;
            branch_target_address = `ZeroWord;
            case (aluop_i)
                `EXE_B_OP, `EXE_BL_OP: begin
                    branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_JIRL_OP: begin
                    branch_flag = 1'b1;
                    branch_target_address = reg1_i + imm;
                end
                `EXE_BEQ_OP: begin
                    if (dispatch_i.branch_com_result[0]) branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_BNE_OP: begin
                    if (dispatch_i.branch_com_result[1]) branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_BLT_OP: begin
                    if (dispatch_i.branch_com_result[2]) branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_BGE_OP: begin
                    if (dispatch_i.branch_com_result[3]) branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_BLTU_OP: begin
                    if (dispatch_i.branch_com_result[4]) branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                `EXE_BGEU_OP: begin
                    if (dispatch_i.branch_com_result[5]) branch_flag = 1'b1;
                    branch_target_address = inst_pc_i + imm;
                end
                default: begin

                end
            endcase
        end
    end

    always @(*) begin
        if (rst == `RstEnable) begin
            moveout = `ZeroWord;
        end else begin
            //   inst_pc_o = inst_pc_i;
            //   inst_valid_o = inst_valid_i;
            case (aluop_i)
                `EXE_LUI_OP: begin
                    moveout = reg2_i;
                end
                `EXE_PCADD_OP: begin
                    moveout = reg2_i + ex_o.instr_info.pc;
                end
                default: begin
                    moveout = `ZeroWord;
                end
            endcase
        end
    end

    always @(*) begin
        ex_o.instr_info = dispatch_i.instr_info;
        ex_o.waddr = wd_i;
        ex_o.wreg = wreg_i;
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
            `EXE_RES_CSR:begin
                 ex_o.wdata = reg2_i;
            end
            default: begin
                ex_o.wdata = `ZeroWord;
            end
        endcase
    end

endmodule
