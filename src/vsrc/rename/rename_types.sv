`ifndef RENAME_TYPES_SV
`define RENAME_TYPES_SV
`include "core_config.sv"

package rename_types;

    import core_config::*;

    typedef struct packed {
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd;
        logic [$clog2(PHYREG)-1:0] prf;
    } rename_map_t;

    typedef struct packed {
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd;
        logic [$clog2(PHYREG)-1:0] prf;
    } commit_map_t;

endpackage

`endif
