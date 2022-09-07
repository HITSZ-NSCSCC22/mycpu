`ifndef RENAME_TYPES_SV
`define RENAME_TYPES_SV
`include "core_config.sv"

package rename_types;

    import core_config::*;

    typedef struct packed {
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd;
        logic wen;
    } rename_req_t;

    typedef struct packed {
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd;
        logic wen;
        logic [$clog2(PHYREG)-1:0] prd;
    } rename_map_t;

    typedef struct packed {
        logic [$clog2(PHYREG)-1:0] prs1;
        logic [$clog2(PHYREG)-1:0] prs2;
    } rename_map_out_t;

    typedef struct packed {
        logic valid;
        logic wen;
        logic [4:0] rd;
        logic [$clog2(PHYREG)-1:0] prs1;
        logic [$clog2(PHYREG)-1:0] prs2;
        logic [$clog2(PHYREG)-1:0] prd;
    } commit_map_t;

endpackage

`endif
