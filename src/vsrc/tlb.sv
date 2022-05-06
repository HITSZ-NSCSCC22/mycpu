`include "defines.sv"
`include "csr_defines.sv"

module tlb #(
    parameter TLBNUM = 32

)
(
    input logic                  clk                  ,
    input logic  [ 9:0]          asid                 ,
    //trans mode
    input logic                  inst_addr_trans_en   ,
    input logic                  data_addr_trans_en   ,
    //inst addr trans
    input logic                  inst_fetch           ,
    input logic  [31:0]          inst_vaddr           ,
    input logic                  inst_dmw0_en         ,
    input logic                  inst_dmw1_en         ,
    output logic [ 7:0]          inst_index           ,
    output logic [19:0]          inst_tag             ,
    output logic [ 3:0]          inst_offset          ,
    output logic                 inst_tlb_found       ,
    output logic                 inst_tlb_v           ,
    output logic                 inst_tlb_d           ,
    output logic [ 1:0]          inst_tlb_mat         ,
    output logic [ 1:0]          inst_tlb_plv         ,
    //data addr trans
    input logic                  data_fetch           ,
    input logic  [31:0]          data_vaddr           ,
    input logic                  data_dmw0_en         ,
    input logic                  data_dmw1_en         ,
    input logic                  cacop_op_mode_di     ,
    output logic [ 7:0]          data_index           ,
    output logic [19:0]          data_tag             ,
    output logic [ 3:0]          data_offset          ,
    output logic                 data_tlb_found       ,
    output logic [ 4:0]          data_tlb_index       ,
    output logic                 data_tlb_v           ,
    output logic                 data_tlb_d           ,
    output logic [ 1:0]          data_tlb_mat         ,
    output logic [ 1:0]          data_tlb_plv         ,
    //tlbwi tlbwr tlb write
    input logic                  tlbfill_en           ,
    input logic                  tlbwr_en             ,
    input logic  [ 4:0]          rand_index           ,
    input logic  [31:0]          tlbehi_in            ,
    input logic  [31:0]          tlbelo0_in           ,
    input logic  [31:0]          tlbelo1_in           ,
    input logic  [31:0]          tlbidx_in            , 
    input logic  [ 5:0]          ecode_in             ,
    //tlbr tlb read
    output logic [31:0]          tlbehi_out           ,
    output logic [31:0]          tlbelo0_out          ,
    output logic [31:0]          tlbelo1_out          ,
    output logic [31:0]          tlbidx_out           ,
    output logic [ 9:0]          asid_out             ,
    //invtlb 
    input logic                  invtlb_en            ,
    input logic  [ 9:0]          invtlb_asid          ,
    input logic  [18:0]          invtlb_vpn           ,
    input logic  [ 4:0]          invtlb_op            ,
    //from csr
    input logic  [31:0]          csr_dmw0             ,
    input logic  [31:0]          csr_dmw1             ,
    input logic                  csr_da               ,
    input logic                  csr_pg               
);

logic [18:0] s0_vppn     ;
logic        s0_odd_page ;
logic [ 5:0] s0_ps       ;
logic [19:0] s0_ppn      ;

logic [18:0] s1_vppn     ;
logic        s1_odd_page ;
logic [ 5:0] s1_ps       ;
logic [19:0] s1_ppn      ;

logic        we          ;
logic [ 4:0] w_index     ;
logic [18:0] w_vppn      ;
logic        w_g         ;
logic [ 5:0] w_ps        ;
logic        w_e         ;
logic        w_v0        ;
logic        w_d0        ;
logic [ 1:0] w_mat0      ;
logic [ 1:0] w_plv0      ;
logic [19:0] w_ppn0      ;
logic        w_v1        ;
logic        w_d1        ;
logic [ 1:0] w_mat1      ;
logic [ 1:0] w_plv1      ;
logic [19:0] w_ppn1      ;

logic [ 4:0] r_index     ;
logic [18:0] r_vppn      ;
logic [ 9:0] r_asid      ;
logic        r_g         ;
logic [ 5:0] r_ps        ;
logic        r_e         ;
logic        r_v0        ;
logic        r_d0        ; 
logic [ 1:0] r_mat0      ;
logic [ 1:0] r_plv0      ;
logic [19:0] r_ppn0      ;
logic        r_v1        ;
logic        r_d1        ;
logic [ 1:0] r_mat1      ;
logic [ 1:0] r_plv1      ;
logic [19:0] r_ppn1      ;

logic  [31:0] inst_vaddr_buffer  ;
logic  [31:0] data_vaddr_buffer  ;
logic [31:0] inst_paddr;
logic [31:0] data_paddr;

logic        pg_mode;
logic        da_mode;

always @(posedge clk) begin
    inst_vaddr_buffer <= inst_vaddr;
    data_vaddr_buffer <= data_vaddr;
end

//trans search port sig
assign s0_vppn     = inst_vaddr[31:13];
assign s0_odd_page = inst_vaddr[12];

assign s1_vppn     = data_vaddr[31:13];
assign s1_odd_page = data_vaddr[12];

//trans write port sig
assign we      = tlbfill_en || tlbwr_en;
assign w_index = ({5{tlbfill_en}} & rand_index) | ({5{tlbwr_en}} & tlbidx_in[`INDEX]);
assign w_vppn  = tlbehi_in[`VPPN];
assign w_g     = tlbelo0_in[`TLB_G] && tlbelo1_in[`TLB_G];
assign w_ps    = tlbidx_in[`PS];
assign w_e     = (ecode_in == 6'h3f) ? 1'b1 : !tlbidx_in[`NE];
assign w_v0    = tlbelo0_in[`TLB_V];
assign w_d0    = tlbelo0_in[`TLB_D];
assign w_plv0  = tlbelo0_in[`TLB_PLV];
assign w_mat0  = tlbelo0_in[`TLB_MAT];
assign w_ppn0  = tlbelo0_in[`TLB_PPN_EN];
assign w_v1    = tlbelo1_in[`TLB_V];
assign w_d1    = tlbelo1_in[`TLB_D];
assign w_plv1  = tlbelo1_in[`TLB_PLV];
assign w_mat1  = tlbelo1_in[`TLB_MAT];
assign w_ppn1  = tlbelo1_in[`TLB_PPN_EN];

//trans read port sig
assign r_index      = tlbidx_in[`INDEX];
assign tlbehi_out   = {r_vppn, 13'b0};
assign tlbelo0_out  = {4'b0, r_ppn0, 1'b0, r_g, r_mat0, r_plv0, r_d0, r_v0};
assign tlbelo1_out  = {4'b0, r_ppn1, 1'b0, r_g, r_mat1, r_plv1, r_d1, r_v1};
assign tlbidx_out   = {!r_e, 1'b0, r_ps, 24'b0}; //note do not write index
assign asid_out     = r_asid;

tlb_entry tlb_entry(
    .clk            (clk            ),
    // search port 0
    .s0_fetch       (inst_fetch     ),
    .s0_vppn        (s0_vppn        ),
    .s0_odd_page    (s0_odd_page    ),
    .s0_asid        (asid           ),
    .s0_found       (inst_tlb_found ),
    .s0_index       (),
    .s0_ps          (s0_ps          ),
    .s0_ppn         (s0_ppn         ),
    .s0_v           (inst_tlb_v     ),
    .s0_d           (inst_tlb_d     ),
    .s0_mat         (inst_tlb_mat   ),
    .s0_plv         (inst_tlb_plv   ),
    // search port 1
    .s1_fetch       (data_fetch     ),
    .s1_vppn        (s1_vppn        ),
    .s1_odd_page    (s1_odd_page    ),
    .s1_asid        (asid           ),
    .s1_found       (data_tlb_found ),
    .s1_index       (data_tlb_index ),
    .s1_ps          (s1_ps          ),
    .s1_ppn         (s1_ppn         ),
    .s1_v           (data_tlb_v     ),
    .s1_d           (data_tlb_d     ),
    .s1_mat         (data_tlb_mat   ),
    .s1_plv         (data_tlb_plv   ),
    // write port 
    .we             (we             ),     
    .w_index        (w_index        ),
    .w_vppn         (w_vppn         ),
    .w_asid         (asid           ),
    .w_g            (w_g            ),
    .w_ps           (w_ps           ),
    .w_e            (w_e            ),
    .w_v0           (w_v0           ),
    .w_d0           (w_d0           ),
    .w_plv0         (w_plv0         ),
    .w_mat0         (w_mat0         ),
    .w_ppn0         (w_ppn0         ),
    .w_v1           (w_v1           ),
    .w_d1           (w_d1           ),
    .w_plv1         (w_plv1         ),
    .w_mat1         (w_mat1         ),
    .w_ppn1         (w_ppn1         ),
    //read port 
    .r_index        (r_index        ),
    .r_vppn         (r_vppn         ),
    .r_asid         (r_asid         ),
    .r_g            (r_g            ),
    .r_ps           (r_ps           ),
    .r_e            (r_e            ),
    .r_v0           (r_v0           ),
    .r_d0           (r_d0           ),
    .r_mat0         (r_mat0         ),
    .r_plv0         (r_plv0         ),
    .r_ppn0         (r_ppn0         ),
    .r_v1           (r_v1           ),
    .r_d1           (r_d1           ),
    .r_mat1         (r_mat1         ),
    .r_plv1         (r_plv1         ),
    .r_ppn1         (r_ppn1         ),
    //invalid port
    .inv_en         (invtlb_en      ),
    .inv_op         (invtlb_op      ),
    .inv_asid       (invtlb_asid    ),
    .inv_vpn        (invtlb_vpn     )
);

assign pg_mode = !csr_da &&  csr_pg;
assign da_mode =  csr_da && !csr_pg;

assign inst_paddr = (pg_mode && inst_dmw0_en) ? {csr_dmw0[`PSEG], inst_vaddr_buffer[28:0]} :
                    (pg_mode && inst_dmw1_en) ? {csr_dmw1[`PSEG], inst_vaddr_buffer[28:0]} : inst_vaddr_buffer;

assign inst_offset = inst_vaddr[3:0];
assign inst_index  = inst_vaddr[11:4];
assign inst_tag    = inst_addr_trans_en ? ((s0_ps == 6'd12) ? s0_ppn : {s0_ppn[19:10], inst_paddr[21:12]}) : inst_paddr[31:12];

assign data_paddr = (pg_mode && data_dmw0_en && !cacop_op_mode_di) ? {csr_dmw0[`PSEG], data_vaddr_buffer[28:0]} : 
                    (pg_mode && data_dmw1_en && !cacop_op_mode_di) ? {csr_dmw1[`PSEG], data_vaddr_buffer[28:0]} : data_vaddr_buffer;

assign data_offset = data_vaddr[3:0];
assign data_index  = data_vaddr[11:4];
assign data_tag    = data_addr_trans_en ? ((s1_ps == 6'd12) ? s1_ppn : {s1_ppn[19:10], data_paddr[21:12]}) : data_paddr[31:12];

endmodule