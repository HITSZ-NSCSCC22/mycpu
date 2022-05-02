`include "defines.v"
`include "csr_defines.v"

module tlb #(
    parameter TLBNUM = 32
)
(
    input wire                  clk                  ,
    input wire  [ 9:0]          asid                 ,
    //trans mode
    input wire                  inst_addr_trans_en   ,
    input wire                  data_addr_trans_en   ,
    //inst addr trans
    input wire                  inst_fetch           ,
    input wire  [31:0]          inst_vaddr           ,
    input wire                  inst_dmw0_en         ,
    input wire                  inst_dmw1_en         ,
    output wire [ 7:0]          inst_index           ,
    output wire [19:0]          inst_tag             ,
    output wire [ 3:0]          inst_offset          ,
    output wire                 inst_tlb_found       ,
    output wire                 inst_tlb_v           ,
    output wire                 inst_tlb_d           ,
    output wire [ 1:0]          inst_tlb_mat         ,
    output wire [ 1:0]          inst_tlb_plv         ,
    //data addr trans
    input wire                  data_fetch           ,
    input wire  [31:0]          data_vaddr           ,
    input wire                  data_dmw0_en         ,
    input wire                  data_dmw1_en         ,
    input wire                  cacop_op_mode_di     ,
    output wire [ 7:0]          data_index           ,
    output wire [19:0]          data_tag             ,
    output wire [ 3:0]          data_offset          ,
    output wire                 data_tlb_found       ,
    output wire [ 4:0]          data_tlb_index       ,
    output wire                 data_tlb_v           ,
    output wire                 data_tlb_d           ,
    output wire [ 1:0]          data_tlb_mat         ,
    output wire [ 1:0]          data_tlb_plv         ,
    //tlbwi tlbwr tlb write
    input wire                  tlbfill_en           ,
    input wire                  tlbwr_en             ,
    input wire  [ 4:0]          rand_index           ,
    input wire  [31:0]          tlbehi_in            ,
    input wire  [31:0]          tlbelo0_in           ,
    input wire  [31:0]          tlbelo1_in           ,
    input wire  [31:0]          tlbidx_in            , 
    input wire  [ 5:0]          ecode_in             ,
    //tlbr tlb read
    output wire [31:0]          tlbehi_out           ,
    output wire [31:0]          tlbelo0_out          ,
    output wire [31:0]          tlbelo1_out          ,
    output wire [31:0]          tlbidx_out           ,
    output wire [ 9:0]          asid_out             ,
    //invtlb 
    input wire                  invtlb_en            ,
    input wire  [ 9:0]          invtlb_asid          ,
    input wire  [18:0]          invtlb_vpn           ,
    input wire  [ 4:0]          invtlb_op            ,
    //from csr
    input wire  [31:0]          csr_dmw0             ,
    input wire  [31:0]          csr_dmw1             ,
    input wire                  csr_da               ,
    input wire                  csr_pg               
);

wire [18:0] s0_vppn     ;
wire        s0_odd_page ;
wire [ 5:0] s0_ps       ;
wire [19:0] s0_ppn      ;

wire [18:0] s1_vppn     ;
wire        s1_odd_page ;
wire [ 5:0] s1_ps       ;
wire [19:0] s1_ppn      ;

wire        we          ;
wire [ 4:0] w_index     ;
wire [18:0] w_vppn      ;
wire        w_g         ;
wire [ 5:0] w_ps        ;
wire        w_e         ;
wire        w_v0        ;
wire        w_d0        ;
wire [ 1:0] w_mat0      ;
wire [ 1:0] w_plv0      ;
wire [19:0] w_ppn0      ;
wire        w_v1        ;
wire        w_d1        ;
wire [ 1:0] w_mat1      ;
wire [ 1:0] w_plv1      ;
wire [19:0] w_ppn1      ;

wire [ 4:0] r_index     ;
wire [18:0] r_vppn      ;
wire [ 9:0] r_asid      ;
wire        r_g         ;
wire [ 5:0] r_ps        ;
wire        r_e         ;
wire        r_v0        ;
wire        r_d0        ; 
wire [ 1:0] r_mat0      ;
wire [ 1:0] r_plv0      ;
wire [19:0] r_ppn0      ;
wire        r_v1        ;
wire        r_d1        ;
wire [ 1:0] r_mat1      ;
wire [ 1:0] r_plv1      ;
wire [19:0] r_ppn1      ;

reg  [31:0] inst_vaddr_buffer  ;
reg  [31:0] data_vaddr_buffer  ;
wire [31:0] inst_paddr;
wire [31:0] data_paddr;

wire        pg_mode;
wire        da_mode;

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