// BPU is the Branch Predicting Unit
// BPU does the following things:
// 1. accept update info from FTQ
// 2. provide update to tage predictor
// 3. send pc into tage predictor and generate FTQ block

`include "core_config.sv"
`include "core_types.sv"
`include "BPU/include/bpu_types.sv"
`include "frontend/frontend_defines.sv"

`include "BPU/components/ftb.sv"
`include "BPU/tage_predictor.sv"
`include "BPU/ras.sv"


module bpu
    import core_config::*;
    import core_types::*;
    import bpu_types::*;
(
    input logic clk,
    input logic rst,

    // Backend flush
    input logic backend_flush_i,

    // FTQ
    // Predict
    input [ADDR_WIDTH-1:0] pc_i,
    input logic ftq_full_i,
    output ftq_block_t ftq_p0_o,
    output ftq_block_t ftq_p1_o,
    output bpu_ftq_meta_t ftq_meta_o,
    // Train
    input ftq_bpu_meta_t ftq_meta_i,

    // PC
    output logic main_redirect_o,
    output logic [ADDR_WIDTH-1:0] main_redirect_pc_o

    // PMU
    // TODO: use PMU to monitor miss-prediction rate and each component useful rate

);
    // Parameters
    localparam BASE_CTR_WIDTH = BPU_COMPONENT_CTR_WIDTH[0];

    // P1 signals
    logic [ADDR_WIDTH-1:0] p1_pc;
    logic main_redirect;
    // FTB
    logic ftb_hit;
    logic [$clog2(FTB_NWAY)-1:0] ftb_hit_index;
    ftb_entry_t ftb_entry;
    // TAGE
    logic predict_taken, predict_valid;
    // RAS
    logic [ADDR_WIDTH-1:0] ras_top_addr;

    logic flush_delay, ftq_full_delay;
    always_ff @(posedge clk) begin
        flush_delay <= backend_flush_i | (main_redirect & ~ftq_full_delay);
        ftq_full_delay <= ftq_full_i;
    end


    ////////////////////////////////////////////////////////////////////////////////////
    // Query logic
    ////////////////////////////////////////////////////////////////////////////////////
    bpu_ftq_meta_t tage_meta, bpu_meta;

    // P0 
    // FTQ Output generate
    logic is_cross_page;
    assign is_cross_page = pc_i[11:0] > 12'hff0;  // if 4 instr already cross the page limit
    always_comb begin
        if (ftq_full_i) begin
            ftq_p0_o = 0;
        end else begin  // P0 generate a next-line prediction
            if (is_cross_page) begin
                ftq_p0_o.length = (12'h000 - pc_i[11:0]) >> 2;
            end else begin
                ftq_p0_o.length = 4;
            end
            ftq_p0_o.start_pc = pc_i;
            ftq_p0_o.valid = 1;
            // If cross page, length will be cut, so ensures no cacheline cross
            ftq_p0_o.is_cross_cacheline = (pc_i[3:2] != 2'b00) & ~is_cross_page;
            ftq_p0_o.predicted_taken = 0;
            ftq_p0_o.predict_valid = 0;
        end
    end




    // P1
    assign main_redirect = ftb_hit & ~flush_delay & ~ftq_full_delay;
    always_ff @(posedge clk) begin
        p1_pc <= pc_i;
    end
    // P1 FTQ output
    always_comb begin
        if (main_redirect) begin  // Main BPU generate a redirect in P1
            ftq_p1_o.valid = 1;
            ftq_p1_o.is_cross_cacheline = ftb_entry.is_cross_cacheline;
            ftq_p1_o.start_pc = p1_pc;
            ftq_p1_o.length = ftb_entry.fall_through_address[2+$clog2(FETCH_WIDTH):2] -
                p1_pc[2+$clog2(FETCH_WIDTH):2];  // Use 3bit minus to ensure no overflow
            ftq_p1_o.predict_valid = 1;
            case (ftb_entry.branch_type)
                BRANCH_TYPE_COND: begin
                    ftq_p1_o.predicted_taken = predict_taken;
                end
                BRANCH_TYPE_CALL, BRANCH_TYPE_RET, BRANCH_TYPE_UNCOND: begin
                    ftq_p1_o.predicted_taken = 1;
                end
            endcase
        end else ftq_p1_o = 0;

    end



    // DEBUG
    logic [ADDR_WIDTH-1:0] bpu_pc;
    logic [1:0] ftb_branch_type;
    assign bpu_pc = ftq_p0_o.start_pc;
    assign ftb_branch_type = ftb_entry.branch_type;

    // PC output
    always_comb begin
        main_redirect_o = main_redirect;
        case (ftb_entry.branch_type)
            BRANCH_TYPE_COND:
            main_redirect_pc_o = predict_taken ? ftb_entry.jump_target_address : ftb_entry.fall_through_address;
            BRANCH_TYPE_CALL, BRANCH_TYPE_UNCOND:
            main_redirect_pc_o = ftb_entry.jump_target_address;
            BRANCH_TYPE_RET: main_redirect_pc_o = ras_top_addr;
        endcase
    end
    // FTQ meta output
    assign bpu_meta.ftb_hit = ftb_hit;
    assign bpu_meta.ftb_hit_index = ftb_hit_index;
    assign bpu_meta.valid = ftb_hit;
    assign ftq_meta_o = bpu_meta | tage_meta;




    ////////////////////////////////////////////////////////////////////
    // Update Logic
    ////////////////////////////////////////////////////////////////////
    logic mispredict;
    logic ftb_update_valid;
    tage_predictor_update_info_t tage_update_info;
    ftb_entry_t ftb_entry_update;
    logic ras_push;
    logic ras_pop;
    logic [ADDR_WIDTH-1:0] ras_push_addr;
    assign ras_push = ftq_meta_i.valid & (ftq_meta_i.branch_type == BRANCH_TYPE_CALL);
    assign ras_push_addr = ftq_meta_i.fall_through_address;
    assign ras_pop = ftq_meta_i.valid & (ftq_meta_i.branch_type == BRANCH_TYPE_RET);
    assign mispredict = ftq_meta_i.predicted_taken ^ ftq_meta_i.is_taken;
    // Only following conditions will trigger a FTB update:
    // 1. This is a conditional branch
    // 2. First time a branch jumped
    // 3. A FTB pollution is detected
    assign ftb_update_valid = ftq_meta_i.valid & ((mispredict & ~ftq_meta_i.ftb_hit)| (ftq_meta_i.ftb_dirty & ftq_meta_i.ftb_hit));
    always_comb begin
        // Direction preditor update policy:
        tage_update_info.valid = ftq_meta_i.valid;
        tage_update_info.predict_correct = ftq_meta_i.valid & ~mispredict;
        tage_update_info.is_conditional = ftq_meta_i.branch_type == BRANCH_TYPE_COND;
        tage_update_info.branch_taken = ftq_meta_i.is_taken;
        tage_update_info.bpu_meta = ftq_meta_i.bpu_meta;
        // Override CTR bits if first occur
        // if (ftq_meta_i.ftb_hit)
        // tage_update_info.bpu_meta.provider_ctr_bits = {1'b1, {(BASE_CTR_WIDTH - 1) {1'b0}}};
    end

    always_comb begin
        ftb_entry_update.valid = ~(ftq_meta_i.ftb_dirty & ftq_meta_i.ftb_hit);
        ftb_entry_update.tag = ftq_meta_i.start_pc[ADDR_WIDTH-1:$clog2(FTB_NSET)+2];
        ftb_entry_update.branch_type = ftq_meta_i.branch_type;
        ftb_entry_update.is_cross_cacheline = ftq_meta_i.is_cross_cacheline;
        ftb_entry_update.jump_target_address = ftq_meta_i.jump_target_address;
        ftb_entry_update.fall_through_address = ftq_meta_i.fall_through_address;
    end
    // assign ftb_hit = 0;
    ftb u_ftb (
        .clk(clk),
        .rst(rst),

        // Query
        .query_pc_i(pc_i),
        .query_entry_o(ftb_entry),
        .hit(ftb_hit),
        .hit_index_o(ftb_hit_index),

        // Update
        .update_pc_i(ftq_meta_i.start_pc),
        .update_way_index_i(ftq_meta_i.ftb_hit_index),
        .update_valid_i(ftb_update_valid),
        .update_dirty_i(ftq_meta_i.ftb_dirty & ftq_meta_i.ftb_hit),
        .update_entry_i(ftb_entry_update)
    );

    tage_predictor u_tage_predictor (
        .clk                   (clk),
        .rst                   (rst),
        .pc_i                  (pc_i),
        .bpu_meta_o            (tage_meta),
        .predict_branch_taken_o(predict_taken),
        .predict_valid_o       (predict_valid),
        .update_pc_i           (ftq_meta_i.start_pc),
        .update_info_i         (tage_update_info),
        .perf_tag_hit_counter  ()
    );

    ras u_ras (
        .clk        (clk),
        .rst        (rst),
        .push_i     (ras_push),
        .call_addr_i(ras_push_addr),
        .pop_i      (ras_pop),
        .top_addr_o (ras_top_addr)
    );



`ifdef SIMULATION
    // Performance counter
    integer ftb_first_time_branch;
    integer ftb_update_cnt;
    always_ff @(posedge clk) begin
        ftb_first_time_branch <= ftb_first_time_branch + (ftb_update_valid & ~ftq_meta_i.ftb_hit);
        ftb_update_cnt <= ftb_update_cnt + ftb_update_valid;
    end
`endif


endmodule
