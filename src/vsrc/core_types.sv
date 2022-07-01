`ifndef CORE_TYPES_SV
`define CORE_TYPES_SV
`include "defines.sv"
`include "csr_defines.sv"
`include "TLB/tlb_types.sv"
`include "core_config.sv"

package core_types;

    import tlb_types::*;
    import csr_defines::*;
    import core_config::*;

    // CSR info passed to IFU
    typedef struct packed {
        logic pg;
        logic da;
        logic [31:0] dmw0;
        logic [31:0] dmw1;
        logic [1:0] plv;
    } ifu_csr_t;

    // Instruction info types
    typedef struct packed {
        logic is_pri;
        logic is_csr;
        logic mem_load;
        logic mem_store;
        logic mem_b_op;
        logic mem_h_op;
        logic not_commit_instr;
        logic need_refetch;  // Instruction modify IF logic, any instr after it may be totaly wrong
    } special_info_t;

    typedef struct packed {
        // This instruction exists
        logic valid;
        // Exception info 
        logic excp;
        // {excp_ppi, excp_pif, excp_tlbr, excp_adef}
        logic [15:0] excp_num;

        // Frontend info
        logic [$clog2(FRONTEND_FTQ_SIZE)-1:0] ftq_id;
        logic [$clog2(FETCH_WIDTH)-1:0] ftq_block_idx;  // index within a fetch block
        logic is_last_in_block;  // Mark the last instruction in basic block

        // Special information
        special_info_t special_info;

        // 
        logic [`InstAddrBus] pc;
        logic [`InstBus] instr;
    } instr_info_t;

    typedef struct packed {
        bit valid;
        bit [`InstAddrBus] pc;
        bit taken;

        // BPU info
        bit [2:0]  bpu_useful_bits;
        bit [2:0]  bpu_ctr_bits;
        bit [2:0]  bpu_provider_id;
        bit [13:0] bpu_provider_query_index;
    } branch_update_info_t;



    typedef struct packed {
        instr_info_t instr_info;

        // Reg read info
        logic use_imm;
        logic [`RegBus] imm;
        logic [1:0] reg_read_valid;  // Read valid for 2 regs
        logic [1:0][`RegAddrBus] reg_read_addr;  // Read addr, {reg2, reg1}
        logic [`InstBus] instr;

        logic [`AluOpBus] aluop;
        logic [`AluSelBus] alusel;
        logic [`RegAddrBus] reg_write_addr;
        logic reg_write_valid;
        logic csr_we;
        csr_write_signal csr_signal;

    } id_dispatch_struct;


    typedef struct packed {
        instr_info_t instr_info;

        // Pass ID info to EX to help data forwarding
        logic [1:0][`RegAddrBus] read_reg_addr;
        logic use_imm;

        logic [`InstBus] instr;
        logic [`RegBus] oprand1;
        logic [`RegBus] oprand2;
        logic [`RegBus] imm;
        logic [`AluOpBus] aluop;
        logic [`AluSelBus] alusel;
        logic [`RegAddrBus] reg_write_addr;
        logic reg_write_valid;

        logic [`RegBus]  csr_reg_data;
        csr_write_signal csr_signal;

    } dispatch_ex_struct;

    typedef struct packed {
        logic reg_valid;
        logic [`RegAddrBus] reg_addr;
        logic [`RegBus] reg_data;
        logic [`AluOpBus] aluop_i;
    } ex_dispatch_struct;

    typedef struct packed {
        instr_info_t instr_info;

        logic wreg;
        logic [`RegAddrBus] waddr;
        logic [`AluOpBus] aluop;
        logic [`RegBus] mem_addr;
        logic [`RegBus] reg2;
        csr_write_signal csr_signal;
        logic [`RegBus] wdata;

        tlb_inv_t inv_i;
        logic [63:0] timer_64;

        logic cacop_en;
        logic icache_op_en;
        logic [4:0] cacop_op;
    } ex_mem_struct;

    // MEM stage data forwarding
    typedef struct packed {
        logic is_load_data;
        logic write_reg;
        logic [`RegAddrBus] write_reg_addr;
        logic [`RegBus] write_reg_data;
    } mem_data_forward_t;

    typedef struct packed {
        instr_info_t instr_info;

        logic [`RegAddrBus] waddr;
        logic [`RegBus] wdata;
        logic wreg;
        logic [`AluOpBus] aluop;
        csr_write_signal csr_signal;

        //load store difftest
        logic [7:0] inst_ld_en;
        logic [7:0] inst_st_en;
        logic [`DataAddrBus] load_addr;
        logic [`DataAddrBus] store_addr;
        logic [`DataAddrBus] mem_addr;
        logic [`RegBus] store_data;

        tlb_inv_t inv_i;
        logic [63:0] timer_64;

        logic cacop_en;
        logic icache_op_en;
        logic [4:0] cacop_op;
    } mem_wb_struct;

    typedef struct packed {
        logic we;
        logic ce;
        logic [3:0] sel;
        logic [`DataAddrBus] addr;
        logic [`RegBus] data;
        logic uncache_en;
        logic [2:0] rd_type;
        logic [2:0]wr_type;
    } mem_cache_struct;

    typedef struct packed {
        logic we;
        logic [`InstAddrBus] pc;
        logic [`RegAddrBus] waddr;
        logic [`RegBus] wdata;
    } wb_reg;

    // Difftest Commit Information
    // Used to submit instr info into difftest framework
    typedef struct packed {
        logic [`InstAddrBus] pc;
        logic valid;
        logic [`InstBus] instr;
        logic [7:0] inst_ld_en;
        logic [31:0] ld_paddr;
        logic [31:0] ld_vaddr;
        logic [7:0] inst_st_en;
        logic [31:0] st_paddr;
        logic [31:0] st_vaddr;
        logic [31:0] st_data;
        logic is_CNTinst;
        logic [63:0] timer_64;
    } diff_commit;

    typedef struct packed {
        logic we;
        logic value;
    } wb_llbit;

    typedef struct packed {
        logic valid;
        logic is_last_in_block;
        logic [`AluOpBus] aluop;
        wb_reg wb_reg_o;
        wb_llbit llbit_o;
        logic excp;
        logic [15:0] excp_num;
        logic fetch_flush;
        logic data_tlb_found;
        logic [`DataAddrBus] mem_addr;
        tlb_inv_t inv_i;
        logic [4:0] data_tlb_index;
        csr_write_signal csr_signal_o;
        diff_commit diff_commit_o;
        logic cacop_en;
        logic icache_op_en;
        logic [4:0] cacop_op;
        special_info_t special_instr;
    } wb_ctrl;

    typedef struct packed {
        logic csr_pg;
        logic csr_da;
        logic [`RegBus] csr_dmw0;
        logic [`RegBus] csr_dmw1;
        logic [1:0] csr_plv;
        logic [1:0] csr_datm;
    } csr_to_mem_struct;

    typedef struct packed {
        logic [19:0] tlb_tag;
        logic data_tlb_found;
        logic [4:0] data_tlb_index;
        logic data_tlb_v;
        logic data_tlb_d;
        logic [1:0] data_tlb_mat;
        logic [1:0] data_tlb_plv;
    } tlb_to_mem_struct;

endpackage
`endif
