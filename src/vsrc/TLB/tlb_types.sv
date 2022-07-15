`ifndef TLB_TYPES_SV
`define TLB_TYPES_SV

`include "core_config.sv"

package tlb_types;

    import core_config::*;

    //TLB-ENTRY parameter
    `define ENTRY_LEN 89 
    `define ENTRYWAYLEN 26
    `define ENTRY_E 0
    `define ENTRY_ASID 10:1
    `define ENTRY_G 11
    `define ENTRY_PS 17:12
    `define ENTRY_VPPN 36:18
    `define ENTRY_VPPN_H0 36:27
    `define ENTRY_VPPN_H1 36:28
    `define ENTRY_V0 37
    `define ENTRY_D0 38
    `define ENTRY_MAT0 40:39
    `define ENTRY_PLV0 42:41
    `define ENTRY_PPN0 62:43
    `define ENTRY_V1 63
    `define ENTRY_D1 64
    `define ENTRY_MAT1 66:65
    `define ENTRY_PLV1 68:67
    `define ENTRY_PPN1 88:69

    // Frontend -> TLB
    typedef struct packed {
        logic fetch;
        logic trans_en;
        logic dmw0_en;
        logic dmw1_en;
        logic [31:0] vaddr;
    } inst_tlb_t;

    // TLB -> Frontend
    // TLB -> ICache
    typedef struct packed {
        logic [7:0] index;
        logic [19:0] tag;
        logic [3:0] offset;
        logic tlb_found;
        logic tlb_v;
        logic tlb_d;
        logic [1:0] tlb_mat;
        logic [1:0] tlb_plv;
    } tlb_inst_t;


    typedef struct packed {
        logic fetch;
        logic trans_en;
        logic dmw0_en;
        logic dmw1_en;
        logic tlbsrch_en;
        logic cacop_op_mode_di;
        logic [ADDR_WIDTH-1:0] vaddr;
    } data_tlb_rreq_t;

    typedef struct packed {
        logic [7:0] index;
        logic [19:0] tag;
        logic [3:0] offset;
        logic found;
        logic [4:0] tlb_index;
        logic tlb_v;
        logic tlb_d;
        logic [1:0] tlb_mat;
        logic [1:0] tlb_plv;
    } tlb_data_t;

    typedef struct packed {
        logic tlbfill_en;
        logic tlbwr_en;
        logic [4:0] rand_index;
        logic [31:0] tlbehi;
        logic [31:0] tlbelo0;
        logic [31:0] tlbelo1;
        logic [31:0] tlbidx;
        logic [5:0] ecode;
    } tlb_write_in_struct;

    typedef struct packed {
        logic [31:0] tlbehi;
        logic [31:0] tlbelo0;
        logic [31:0] tlbelo1;
        logic [31:0] tlbidx;
        logic [9:0]  asid;
    } tlb_read_out_struct;

    typedef struct packed {
        logic en;
        logic [9:0] asid;
        logic [18:0] vpn;
        logic [4:0] op;
    } tlb_inv_t;

    typedef struct packed {
        logic e;
        logic [9:0] asid;
        logic g;
        logic [5:0] ps;
        logic [18:0] vppn;
        logic v0;
        logic d0;
        logic [1:0] mat0;
        logic [1:0] plv0;
        logic [19:0] ppn0;
        logic v1;
        logic d1;
        logic [1:0] mat1;
        logic [1:0] plv1;
        logic [19:0] ppn1;
    } tlb_wr_port;

    typedef struct packed {logic x;} tlb_search_port;

endpackage
`endif
