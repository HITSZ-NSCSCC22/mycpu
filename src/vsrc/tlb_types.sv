`ifndef TLB_TYPES_SV
`define TLB_TYPES_SV

package tlb_types;

    parameter TLBNUM = 32;

    // Frontend -> TLB
    typedef struct packed {
        logic fetch;
        logic [31:0] vaddr;
        logic dmw0_en;
        logic dmw1_en;
    } inst_tlb_t;

    // TLB -> Frontend
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
        logic [31:0] vaddr;
        logic dmw0_en;
        logic dmw1_en;
        logic cacop_op_mode_di;
    } data_tlb_t;

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
    } tlb_inv_in_struct;

    typedef struct packed {
        logic [18:0] vppn;
        logic [9:0] asid;
        logic g;
        logic [5:0] ps;
        logic e;
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
