`timescale 1ns / 1ps

// Dense small top with explicit x_old/x_new ping-pong state banks.
//
// Compared with the replay top:
// - state replay is still fixed-degree and externally indexed;
// - but the stored state now truly alternates between read and write banks
//   across iterations.

module iter_dense_small_ping_pong_top #(
    parameter integer num_clusters = 2,
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer bound_width = bit_width + 5,
    parameter integer coeff_width = 16,
    parameter integer acc_width = 40,
    parameter integer block_size = 2,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size,
    parameter integer data_width = bit_width + 3,
    parameter integer row_datapath_mode = 0,
    parameter integer mac_acc_width = 32,
    parameter integer conv_mac_pipeline = 0,
    parameter integer conv_product_shift = 0,
    parameter integer conv_round_pipeline = 0,
    // Physical width used only by the conventional DSP-MAC baseline.  The
    // PageRank fixture can still expose degree=4 valid terms, but setting this
    // to 8 pads four zero terms so the baseline reserves the same 8 input slots
    // as the prior MSDF_MUL_ADD_8 operator.
    parameter integer conv_baseline_degree = 8,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer src_idx_width = row_idx_width,
    parameter integer global_source_replay = 0,
    parameter integer halo_source_replay = 0,
    parameter integer halo_cluster_radius = 1,
    parameter integer halo_replay_mode = 0,
    parameter integer halo_replay_output_register = 0,
    parameter integer enable_prefix_cert = 0,
    parameter integer cert_product_pipeline = 0,
    parameter integer cert_operand_pipeline = 0,
    parameter integer cert_compare_pipeline = 0,
    // When enabled, the per-cluster certification engines are interpreted as
    // local L1(delta) reducers.  The top-level iteration decision sums all
    // cluster max_error values and compares the result against eta[0].
    parameter integer global_l1_cert = 0,
    parameter integer solver_native_skip_digits = 8,
    parameter integer solver_native_affine_guard_shift = 3,
    parameter integer solver_native_sample_width = 5,
    parameter integer wavefront_superstep_stages = 4,
    parameter integer wavefront_inter_stage_delay_cycles = 0,
    parameter integer halo_source_rows = num_rows * (2 * halo_cluster_radius + 1),
    parameter integer prior_capture_unit = 1
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_start_iter,
    input                                               i_commit_iter,
    input      [num_clusters - 1 : 0]                   i_load_state_clusters,
    input                                               i_load_state_bank_sel,
    input      [row_idx_width - 1 : 0]                  i_load_state_row_idx,
    input      [data_width - 1 : 0]                     i_load_state_p,
    input      [data_width - 1 : 0]                     i_load_state_n,
    input      [num_clusters - 1 : 0]                   i_use_replay_clusters,
    input      [$clog2(data_width) - 1 : 0]             i_replay_digit_idx,
    input      [num_clusters * num_rows * degree * src_idx_width - 1 : 0] i_src_row_idx_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_ena_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x0_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x0_n_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x1_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x1_n_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x2_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x2_n_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x3_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x3_n_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff0_vec_p_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff0_vec_n_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff1_vec_p_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff1_vec_n_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff2_vec_p_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff2_vec_n_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff3_vec_p_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff3_vec_n_rows_clusters,
    input      [num_clusters * num_rows * (bit_width + 2) - 1 : 0] i_bias_vec_p_rows_clusters,
    input      [num_clusters * num_rows * (bit_width + 2) - 1 : 0] i_bias_vec_n_rows_clusters,
    input      [num_clusters * bound_width - 1 : 0]     i_tail_bound_clusters,
    input      [num_clusters * num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights_clusters,
    input      [num_clusters * acc_width - 1 : 0]       i_eta_clusters,
    output     [num_clusters - 1 : 0]                   o_read_bank_sel_clusters,
    output     [num_clusters * num_rows - 1 : 0]        o_drv_x0_p_rows_clusters,
    output     [num_clusters * num_rows - 1 : 0]        o_drv_x0_n_rows_clusters,
    output     [num_clusters * num_rows - 1 : 0]        o_drv_x1_p_rows_clusters,
    output     [num_clusters * num_rows - 1 : 0]        o_drv_x1_n_rows_clusters,
    output     [num_clusters * num_rows - 1 : 0]        o_drv_x2_p_rows_clusters,
    output     [num_clusters * num_rows - 1 : 0]        o_drv_x2_n_rows_clusters,
    output     [num_clusters * num_rows - 1 : 0]        o_drv_x3_p_rows_clusters,
    output     [num_clusters * num_rows - 1 : 0]        o_drv_x3_n_rows_clusters,
    output     [num_clusters - 1 : 0]                   o_cluster_valid,
    output     [num_clusters - 1 : 0]                   o_cluster_certified,
    output     [num_clusters * acc_width - 1 : 0]       o_cluster_max_error,
    output     [num_clusters - 1 : 0]                   o_prefix_cluster_valid,
    output     [num_clusters - 1 : 0]                   o_prefix_cluster_certified,
    output     [num_clusters * num_rows * data_width - 1 : 0] o_x_old_p_rows_clusters,
    output     [num_clusters * num_rows * data_width - 1 : 0] o_x_old_n_rows_clusters,
    output                                              o_iter_done,
    output                                              o_iter_converged,
    output                                              o_iter_continue,
    output     [num_clusters - 1 : 0]                   o_seen_mask,
    output     [num_clusters - 1 : 0]                   o_cert_mask
);

    localparam integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width);
    localparam integer conv_baseline_degree_eff =
        (conv_baseline_degree > degree) ? conv_baseline_degree : degree;
    localparam integer conv_reserved_degree =
        conv_baseline_degree_eff - degree;
    localparam integer mode4_source_rows =
        (halo_source_replay != 0) ? halo_source_rows :
        ((global_source_replay != 0) ? (num_clusters * num_rows) : num_rows);

    wire [num_clusters - 1 : 0] w_cluster_valid;
    wire [num_clusters - 1 : 0] w_cluster_certified;
    wire [num_clusters - 1 : 0] w_prefix_cluster_valid;
    wire [num_clusters - 1 : 0] w_prefix_cluster_certified;
    wire [num_clusters * acc_width - 1 : 0] w_cluster_max_error;
    wire [num_clusters * num_rows - 1 : 0] w_valid_rows_clusters;
    wire [num_clusters * num_rows * data_width - 1 : 0] w_sum_p_rows_clusters;
    wire [num_clusters * num_rows * data_width - 1 : 0] w_sum_n_rows_clusters;
    wire [num_clusters * num_rows * data_width - 1 : 0] w_x_old_p_rows_clusters;
    wire [num_clusters * num_rows * data_width - 1 : 0] w_x_old_n_rows_clusters;
    wire [num_clusters - 1 : 0] w_read_bank_sel_clusters;
    reg  [num_clusters - 1 : 0] r_cluster_certified;
    reg  [num_clusters * acc_width - 1 : 0] r_cluster_max_error;
    reg  [num_clusters - 1 : 0] r_cluster_certified_out;
    reg  [num_clusters * acc_width - 1 : 0] r_cluster_max_error_out;

    wire [num_clusters * num_rows - 1 : 0] w_drv_x0_p_rows_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_drv_x0_n_rows_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_drv_x1_p_rows_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_drv_x1_n_rows_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_drv_x2_p_rows_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_drv_x2_n_rows_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_drv_x3_p_rows_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_drv_x3_n_rows_clusters;
    wire [num_clusters * wavefront_superstep_stages * num_rows - 1 : 0]
        w_mode4_stage_commit_valid_rows_clusters;
    wire [num_clusters * wavefront_superstep_stages * num_rows * digit_idx_width - 1 : 0]
        w_mode4_stage_commit_digit_idx_rows_clusters;
    wire [num_clusters * wavefront_superstep_stages * num_rows - 1 : 0]
        w_mode4_stage_commit_digit_p_rows_clusters;
    wire [num_clusters * wavefront_superstep_stages * num_rows - 1 : 0]
        w_mode4_stage_commit_digit_n_rows_clusters;
    wire [num_clusters * num_rows * degree - 1 : 0]
        w_mode7_stage0_state_p_terms_clusters;
    wire [num_clusters * num_rows * degree - 1 : 0]
        w_mode7_stage0_state_n_terms_clusters;
    wire [num_clusters * num_rows * degree * bit_width - 1 : 0]
        w_mode7_coeff_p_terms_clusters;
    wire [num_clusters * num_rows * degree * bit_width - 1 : 0]
        w_mode7_coeff_n_terms_clusters;
    wire [num_clusters * num_rows * (bit_width + 2) - 1 : 0]
        w_mode7_bias_p_rows_clusters;
    wire [num_clusters * num_rows * (bit_width + 2) - 1 : 0]
        w_mode7_bias_n_rows_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_mode7_final_valid_rows;
    wire [num_clusters * num_rows * digit_idx_width - 1 : 0]
        w_mode7_final_digit_idx_rows;
    wire [num_clusters * num_rows - 1 : 0] w_mode7_final_digit_p_rows;
    wire [num_clusters * num_rows - 1 : 0] w_mode7_final_digit_n_rows;
    wire [num_clusters * num_rows - 1 : 0] w_mode7_final_done_rows;
    wire [wavefront_superstep_stages * num_clusters * num_rows - 1 : 0]
        w_mode7_stage_valid_rows;
    wire [wavefront_superstep_stages * num_clusters * num_rows *
        digit_idx_width - 1 : 0] w_mode7_stage_digit_idx_rows;
    wire [wavefront_superstep_stages * num_clusters * num_rows - 1 : 0]
        w_mode7_stage_digit_p_rows;
    wire [wavefront_superstep_stages * num_clusters * num_rows - 1 : 0]
        w_mode7_stage_digit_n_rows;
    wire [wavefront_superstep_stages * num_clusters * num_rows - 1 : 0]
        w_mode7_stage_done_rows;
    wire [wavefront_superstep_stages - 1 : 0] w_mode7_stage_done;
    wire [wavefront_superstep_stages - 2 : 0] w_mode7_stage_started_before_prev_done;
    wire w_iter_done_base;
    wire w_iter_converged_base;
    wire w_iter_continue_base;
    reg [acc_width - 1 : 0] r_global_l1_sum_next;
    reg [acc_width - 1 : 0] r_global_l1_term;
    wire [acc_width - 1 : 0] w_global_l1_eta;
    wire w_global_l1_converged;

    integer ri;
    integer oi;
    integer li;
    genvar gi;
    genvar msi;
    genvar mhi;
    genvar mgi;
    generate
        for (gi = 0; gi < num_clusters; gi = gi + 1) begin : gen_clusters
            wire [num_rows * bound_width - 1 : 0] w_abs_upper_rows_unused;
            wire [num_blocks * bound_width - 1 : 0] w_block_bounds_unused;
            wire [num_rows - 1 : 0] w_replay_x0_p;
            wire [num_rows - 1 : 0] w_replay_x0_n;
            wire [num_rows - 1 : 0] w_replay_x1_p;
            wire [num_rows - 1 : 0] w_replay_x1_n;
            wire [num_rows - 1 : 0] w_replay_x2_p;
            wire [num_rows - 1 : 0] w_replay_x2_n;
            wire [num_rows - 1 : 0] w_replay_x3_p;
            wire [num_rows - 1 : 0] w_replay_x3_n;
            wire [num_rows - 1 : 0] w_drv_x0_p;
            wire [num_rows - 1 : 0] w_drv_x0_n;
            wire [num_rows - 1 : 0] w_drv_x1_p;
            wire [num_rows - 1 : 0] w_drv_x1_n;
            wire [num_rows - 1 : 0] w_drv_x2_p;
            wire [num_rows - 1 : 0] w_drv_x2_n;
            wire [num_rows - 1 : 0] w_drv_x3_p;
            wire [num_rows - 1 : 0] w_drv_x3_n;
            wire [num_rows - 1 : 0] w_replay_sel_x0_p;
            wire [num_rows - 1 : 0] w_replay_sel_x0_n;
            wire [num_rows - 1 : 0] w_replay_sel_x1_p;
            wire [num_rows - 1 : 0] w_replay_sel_x1_n;
            wire [num_rows - 1 : 0] w_replay_sel_x2_p;
            wire [num_rows - 1 : 0] w_replay_sel_x2_n;
            wire [num_rows - 1 : 0] w_replay_sel_x3_p;
            wire [num_rows - 1 : 0] w_replay_sel_x3_n;
            wire [num_rows * degree * data_width - 1 : 0] w_replay_state_p_terms;
            wire [num_rows * degree * data_width - 1 : 0] w_replay_state_n_terms;
            wire [num_rows * degree * data_width - 1 : 0] w_replay_sel_state_p_terms;
            wire [num_rows * degree * data_width - 1 : 0] w_replay_sel_state_n_terms;
            wire [num_rows * degree * data_width - 1 : 0] w_ext_state_p_terms;
            wire [num_rows * degree * data_width - 1 : 0] w_ext_state_n_terms;
            wire [num_rows * degree * data_width - 1 : 0] w_conv_state_p_terms;
            wire [num_rows * degree * data_width - 1 : 0] w_conv_state_n_terms;
            wire [num_rows * degree * bit_width - 1 : 0] w_conv_coeff_p_terms;
            wire [num_rows * degree * bit_width - 1 : 0] w_conv_coeff_n_terms;
            wire [num_rows * conv_baseline_degree_eff * data_width - 1 : 0]
                w_conv_state_p_terms_baseline;
            wire [num_rows * conv_baseline_degree_eff * data_width - 1 : 0]
                w_conv_state_n_terms_baseline;
            wire [num_rows * conv_baseline_degree_eff * bit_width - 1 : 0]
                w_conv_coeff_p_terms_baseline;
            wire [num_rows * conv_baseline_degree_eff * bit_width - 1 : 0]
                w_conv_coeff_n_terms_baseline;
            wire [num_rows * degree - 1 : 0] w_full_digit_state_p_terms;
            wire [num_rows * degree - 1 : 0] w_full_digit_state_n_terms;
            wire [num_rows - 1 : 0] w_conv_ena_rows;
            reg  [num_rows - 1 : 0] r_replay_x0_p;
            reg  [num_rows - 1 : 0] r_replay_x0_n;
            reg  [num_rows - 1 : 0] r_replay_x1_p;
            reg  [num_rows - 1 : 0] r_replay_x1_n;
            reg  [num_rows - 1 : 0] r_replay_x2_p;
            reg  [num_rows - 1 : 0] r_replay_x2_n;
            reg  [num_rows - 1 : 0] r_replay_x3_p;
            reg  [num_rows - 1 : 0] r_replay_x3_n;
            reg  [num_rows * degree * data_width - 1 : 0] r_replay_state_p_terms;
            reg  [num_rows * degree * data_width - 1 : 0] r_replay_state_n_terms;
            reg  [num_rows - 1 : 0] r_replay_ena_rows;
            reg  [$clog2(data_width) - 1 : 0] r_replay_digit_idx;
            wire [num_rows - 1 : 0] w_full_digit_ena_rows;
            wire [$clog2(data_width) - 1 : 0] w_full_digit_digit_idx;
            wire [num_rows - 1 : 0] w_solver_native_write_done_rows;

            if (global_source_replay) begin : gen_global_replay
                iter_fixed_degree_state_replay #(
                    .num_rows(num_rows),
                    .source_rows(num_clusters * num_rows),
                    .degree(degree),
                    .data_width(data_width),
                    .msb_first(1),
                    .row_idx_width(src_idx_width)
                ) replay_sched (
                    .i_state_p_rows(w_x_old_p_rows_clusters),
                    .i_state_n_rows(w_x_old_n_rows_clusters),
                    .i_digit_idx(i_replay_digit_idx),
                    .i_src_row_idx(i_src_row_idx_clusters[(gi + 1) * num_rows * degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                    .o_x0_p_rows(w_replay_x0_p),
                    .o_x0_n_rows(w_replay_x0_n),
                    .o_x1_p_rows(w_replay_x1_p),
                    .o_x1_n_rows(w_replay_x1_n),
                    .o_x2_p_rows(w_replay_x2_p),
                    .o_x2_n_rows(w_replay_x2_n),
                    .o_x3_p_rows(w_replay_x3_p),
                    .o_x3_n_rows(w_replay_x3_n)
                );
                iter_fixed_degree_state_word_replay #(
                    .num_rows(num_rows),
                    .source_rows(num_clusters * num_rows),
                    .degree(degree),
                    .data_width(data_width),
                    .row_idx_width(src_idx_width)
                ) replay_word_sched (
                    .i_state_p_rows(w_x_old_p_rows_clusters),
                    .i_state_n_rows(w_x_old_n_rows_clusters),
                    .i_src_row_idx(i_src_row_idx_clusters[(gi + 1) * num_rows * degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                    .o_state_p_terms(w_replay_state_p_terms),
                    .o_state_n_terms(w_replay_state_n_terms)
                );
            end else if (halo_source_replay) begin : gen_halo_replay
                wire [halo_source_rows * data_width - 1 : 0] w_halo_state_p_rows;
                wire [halo_source_rows * data_width - 1 : 0] w_halo_state_n_rows;

                genvar hi;
                for (hi = 0; hi < (2 * halo_cluster_radius + 1); hi = hi + 1) begin : gen_halo_slots
                    localparam integer src_cluster = gi + hi - halo_cluster_radius;
                    if (src_cluster >= 0 && src_cluster < num_clusters) begin : gen_valid_halo_slot
                        assign w_halo_state_p_rows[(hi + 1) * num_rows * data_width - 1 -: num_rows * data_width] =
                            w_x_old_p_rows_clusters[(src_cluster + 1) * num_rows * data_width - 1 -: num_rows * data_width];
                        assign w_halo_state_n_rows[(hi + 1) * num_rows * data_width - 1 -: num_rows * data_width] =
                            w_x_old_n_rows_clusters[(src_cluster + 1) * num_rows * data_width - 1 -: num_rows * data_width];
                    end else begin : gen_zero_halo_slot
                        assign w_halo_state_p_rows[(hi + 1) * num_rows * data_width - 1 -: num_rows * data_width] =
                            {num_rows * data_width{1'b0}};
                        assign w_halo_state_n_rows[(hi + 1) * num_rows * data_width - 1 -: num_rows * data_width] =
                            {num_rows * data_width{1'b0}};
                    end
                end

                if (halo_replay_mode == 1 && halo_cluster_radius == 1) begin : gen_stencil_halo_r1
                    iter_fixed_degree_state_replay_halo_r1 #(
                        .num_rows(num_rows),
                        .degree(degree),
                        .data_width(data_width),
                        .msb_first(1),
                        .row_idx_width(src_idx_width)
                    ) replay_sched (
                        .i_prev_state_p_rows(w_halo_state_p_rows[num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_prev_state_n_rows(w_halo_state_n_rows[num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_curr_state_p_rows(w_halo_state_p_rows[2 * num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_curr_state_n_rows(w_halo_state_n_rows[2 * num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_next_state_p_rows(w_halo_state_p_rows[3 * num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_next_state_n_rows(w_halo_state_n_rows[3 * num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_digit_idx(i_replay_digit_idx),
                        .i_src_row_idx(i_src_row_idx_clusters[(gi + 1) * num_rows * degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                        .o_x0_p_rows(w_replay_x0_p),
                        .o_x0_n_rows(w_replay_x0_n),
                        .o_x1_p_rows(w_replay_x1_p),
                        .o_x1_n_rows(w_replay_x1_n),
                        .o_x2_p_rows(w_replay_x2_p),
                        .o_x2_n_rows(w_replay_x2_n),
                        .o_x3_p_rows(w_replay_x3_p),
                        .o_x3_n_rows(w_replay_x3_n)
                    );
                    iter_fixed_degree_state_word_replay_halo_r1 #(
                        .num_rows(num_rows),
                        .degree(degree),
                        .data_width(data_width),
                        .row_idx_width(src_idx_width)
                    ) replay_word_sched (
                        .i_prev_state_p_rows(w_halo_state_p_rows[num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_prev_state_n_rows(w_halo_state_n_rows[num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_curr_state_p_rows(w_halo_state_p_rows[2 * num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_curr_state_n_rows(w_halo_state_n_rows[2 * num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_next_state_p_rows(w_halo_state_p_rows[3 * num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_next_state_n_rows(w_halo_state_n_rows[3 * num_rows * data_width - 1 -: num_rows * data_width]),
                        .i_src_row_idx(i_src_row_idx_clusters[(gi + 1) * num_rows * degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                        .o_state_p_terms(w_replay_state_p_terms),
                        .o_state_n_terms(w_replay_state_n_terms)
                    );
                end else begin : gen_generic_halo
                    iter_fixed_degree_state_replay #(
                        .num_rows(num_rows),
                        .source_rows(halo_source_rows),
                        .degree(degree),
                        .data_width(data_width),
                        .msb_first(1),
                        .row_idx_width(src_idx_width)
                    ) replay_sched (
                        .i_state_p_rows(w_halo_state_p_rows),
                        .i_state_n_rows(w_halo_state_n_rows),
                        .i_digit_idx(i_replay_digit_idx),
                        .i_src_row_idx(i_src_row_idx_clusters[(gi + 1) * num_rows * degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                        .o_x0_p_rows(w_replay_x0_p),
                        .o_x0_n_rows(w_replay_x0_n),
                        .o_x1_p_rows(w_replay_x1_p),
                        .o_x1_n_rows(w_replay_x1_n),
                        .o_x2_p_rows(w_replay_x2_p),
                        .o_x2_n_rows(w_replay_x2_n),
                        .o_x3_p_rows(w_replay_x3_p),
                        .o_x3_n_rows(w_replay_x3_n)
                    );
                    iter_fixed_degree_state_word_replay #(
                        .num_rows(num_rows),
                        .source_rows(halo_source_rows),
                        .degree(degree),
                        .data_width(data_width),
                        .row_idx_width(src_idx_width)
                    ) replay_word_sched (
                        .i_state_p_rows(w_halo_state_p_rows),
                        .i_state_n_rows(w_halo_state_n_rows),
                        .i_src_row_idx(i_src_row_idx_clusters[(gi + 1) * num_rows * degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                        .o_state_p_terms(w_replay_state_p_terms),
                        .o_state_n_terms(w_replay_state_n_terms)
                    );
                end
            end else begin : gen_local_replay
                iter_fixed_degree_state_replay #(
                    .num_rows(num_rows),
                    .source_rows(num_rows),
                    .degree(degree),
                    .data_width(data_width),
                    .msb_first(1),
                    .row_idx_width(src_idx_width)
                ) replay_sched (
                    .i_state_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_state_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_digit_idx(i_replay_digit_idx),
                    .i_src_row_idx(i_src_row_idx_clusters[(gi + 1) * num_rows * degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                    .o_x0_p_rows(w_replay_x0_p),
                    .o_x0_n_rows(w_replay_x0_n),
                    .o_x1_p_rows(w_replay_x1_p),
                    .o_x1_n_rows(w_replay_x1_n),
                    .o_x2_p_rows(w_replay_x2_p),
                    .o_x2_n_rows(w_replay_x2_n),
                    .o_x3_p_rows(w_replay_x3_p),
                    .o_x3_n_rows(w_replay_x3_n)
                );
                iter_fixed_degree_state_word_replay #(
                    .num_rows(num_rows),
                    .source_rows(num_rows),
                    .degree(degree),
                    .data_width(data_width),
                    .row_idx_width(src_idx_width)
                ) replay_word_sched (
                    .i_state_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_state_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_src_row_idx(i_src_row_idx_clusters[(gi + 1) * num_rows * degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                    .o_state_p_terms(w_replay_state_p_terms),
                    .o_state_n_terms(w_replay_state_n_terms)
                );
            end

            always @(posedge i_clk) begin
                if (i_rst) begin
                    r_replay_x0_p <= {num_rows{1'b0}};
                    r_replay_x0_n <= {num_rows{1'b0}};
                    r_replay_x1_p <= {num_rows{1'b0}};
                    r_replay_x1_n <= {num_rows{1'b0}};
                    r_replay_x2_p <= {num_rows{1'b0}};
                    r_replay_x2_n <= {num_rows{1'b0}};
                    r_replay_x3_p <= {num_rows{1'b0}};
                    r_replay_x3_n <= {num_rows{1'b0}};
                    r_replay_state_p_terms <= {num_rows * degree * data_width{1'b0}};
                    r_replay_state_n_terms <= {num_rows * degree * data_width{1'b0}};
                    r_replay_ena_rows <= {num_rows{1'b0}};
                    r_replay_digit_idx <= {$clog2(data_width){1'b0}};
                end else begin
                    r_replay_x0_p <= w_replay_x0_p;
                    r_replay_x0_n <= w_replay_x0_n;
                    r_replay_x1_p <= w_replay_x1_p;
                    r_replay_x1_n <= w_replay_x1_n;
                    r_replay_x2_p <= w_replay_x2_p;
                    r_replay_x2_n <= w_replay_x2_n;
                    r_replay_x3_p <= w_replay_x3_p;
                    r_replay_x3_n <= w_replay_x3_n;
                    r_replay_state_p_terms <= w_replay_state_p_terms;
                    r_replay_state_n_terms <= w_replay_state_n_terms;
                    r_replay_ena_rows <= i_ena_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];
                    r_replay_digit_idx <= i_replay_digit_idx;
                end
            end

            assign w_replay_sel_x0_p = halo_replay_output_register ? r_replay_x0_p : w_replay_x0_p;
            assign w_replay_sel_x0_n = halo_replay_output_register ? r_replay_x0_n : w_replay_x0_n;
            assign w_replay_sel_x1_p = halo_replay_output_register ? r_replay_x1_p : w_replay_x1_p;
            assign w_replay_sel_x1_n = halo_replay_output_register ? r_replay_x1_n : w_replay_x1_n;
            assign w_replay_sel_x2_p = halo_replay_output_register ? r_replay_x2_p : w_replay_x2_p;
            assign w_replay_sel_x2_n = halo_replay_output_register ? r_replay_x2_n : w_replay_x2_n;
            assign w_replay_sel_x3_p = halo_replay_output_register ? r_replay_x3_p : w_replay_x3_p;
            assign w_replay_sel_x3_n = halo_replay_output_register ? r_replay_x3_n : w_replay_x3_n;
            assign w_replay_sel_state_p_terms = halo_replay_output_register
                ? r_replay_state_p_terms
                : w_replay_state_p_terms;
            assign w_replay_sel_state_n_terms = halo_replay_output_register
                ? r_replay_state_n_terms
                : w_replay_state_n_terms;
            assign w_full_digit_ena_rows = halo_replay_output_register
                ? r_replay_ena_rows
                : i_ena_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];
            assign w_full_digit_digit_idx = halo_replay_output_register
                ? r_replay_digit_idx
                : i_replay_digit_idx;
            assign w_conv_ena_rows =
                (i_use_replay_clusters[gi] && halo_replay_output_register)
                    ? r_replay_ena_rows
                    : i_ena_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];

            assign w_drv_x0_p = i_use_replay_clusters[gi]
                ? w_replay_sel_x0_p
                : i_x0_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];
            assign w_drv_x0_n = i_use_replay_clusters[gi]
                ? w_replay_sel_x0_n
                : i_x0_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];
            assign w_drv_x1_p = i_use_replay_clusters[gi]
                ? w_replay_sel_x1_p
                : i_x1_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];
            assign w_drv_x1_n = i_use_replay_clusters[gi]
                ? w_replay_sel_x1_n
                : i_x1_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];
            assign w_drv_x2_p = i_use_replay_clusters[gi]
                ? w_replay_sel_x2_p
                : i_x2_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];
            assign w_drv_x2_n = i_use_replay_clusters[gi]
                ? w_replay_sel_x2_n
                : i_x2_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];
            assign w_drv_x3_p = i_use_replay_clusters[gi]
                ? w_replay_sel_x3_p
                : i_x3_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];
            assign w_drv_x3_n = i_use_replay_clusters[gi]
                ? w_replay_sel_x3_n
                : i_x3_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows];

            assign w_drv_x0_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] = w_drv_x0_p;
            assign w_drv_x0_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] = w_drv_x0_n;
            assign w_drv_x1_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] = w_drv_x1_p;
            assign w_drv_x1_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] = w_drv_x1_n;
            assign w_drv_x2_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] = w_drv_x2_p;
            assign w_drv_x2_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] = w_drv_x2_n;
            assign w_drv_x3_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] = w_drv_x3_p;
            assign w_drv_x3_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] = w_drv_x3_n;

            genvar wi;
            for (wi = 0; wi < num_rows; wi = wi + 1) begin : gen_conv_pack
                assign w_full_digit_state_p_terms[wi * degree + 0] = w_drv_x0_p[wi];
                assign w_full_digit_state_n_terms[wi * degree + 0] = w_drv_x0_n[wi];
                assign w_full_digit_state_p_terms[wi * degree + 1] = w_drv_x1_p[wi];
                assign w_full_digit_state_n_terms[wi * degree + 1] = w_drv_x1_n[wi];
                assign w_full_digit_state_p_terms[wi * degree + 2] = w_drv_x2_p[wi];
                assign w_full_digit_state_n_terms[wi * degree + 2] = w_drv_x2_n[wi];
                assign w_full_digit_state_p_terms[wi * degree + 3] = w_drv_x3_p[wi];
                assign w_full_digit_state_n_terms[wi * degree + 3] = w_drv_x3_n[wi];
                assign w_mode7_stage0_state_p_terms_clusters[
                    (gi * num_rows + wi) * degree + 0] = w_drv_x0_p[wi];
                assign w_mode7_stage0_state_n_terms_clusters[
                    (gi * num_rows + wi) * degree + 0] = w_drv_x0_n[wi];
                assign w_mode7_stage0_state_p_terms_clusters[
                    (gi * num_rows + wi) * degree + 1] = w_drv_x1_p[wi];
                assign w_mode7_stage0_state_n_terms_clusters[
                    (gi * num_rows + wi) * degree + 1] = w_drv_x1_n[wi];
                assign w_mode7_stage0_state_p_terms_clusters[
                    (gi * num_rows + wi) * degree + 2] = w_drv_x2_p[wi];
                assign w_mode7_stage0_state_n_terms_clusters[
                    (gi * num_rows + wi) * degree + 2] = w_drv_x2_n[wi];
                assign w_mode7_stage0_state_p_terms_clusters[
                    (gi * num_rows + wi) * degree + 3] = w_drv_x3_p[wi];
                assign w_mode7_stage0_state_n_terms_clusters[
                    (gi * num_rows + wi) * degree + 3] = w_drv_x3_n[wi];

                assign w_ext_state_p_terms[((wi * degree + 0) + 1) * data_width - 1 -: data_width] =
                    {{(data_width - 1){1'b0}}, i_x0_p_rows_clusters[gi * num_rows + wi]};
                assign w_ext_state_n_terms[((wi * degree + 0) + 1) * data_width - 1 -: data_width] =
                    {{(data_width - 1){1'b0}}, i_x0_n_rows_clusters[gi * num_rows + wi]};
                assign w_ext_state_p_terms[((wi * degree + 1) + 1) * data_width - 1 -: data_width] =
                    {{(data_width - 1){1'b0}}, i_x1_p_rows_clusters[gi * num_rows + wi]};
                assign w_ext_state_n_terms[((wi * degree + 1) + 1) * data_width - 1 -: data_width] =
                    {{(data_width - 1){1'b0}}, i_x1_n_rows_clusters[gi * num_rows + wi]};
                assign w_ext_state_p_terms[((wi * degree + 2) + 1) * data_width - 1 -: data_width] =
                    {{(data_width - 1){1'b0}}, i_x2_p_rows_clusters[gi * num_rows + wi]};
                assign w_ext_state_n_terms[((wi * degree + 2) + 1) * data_width - 1 -: data_width] =
                    {{(data_width - 1){1'b0}}, i_x2_n_rows_clusters[gi * num_rows + wi]};
                assign w_ext_state_p_terms[((wi * degree + 3) + 1) * data_width - 1 -: data_width] =
                    {{(data_width - 1){1'b0}}, i_x3_p_rows_clusters[gi * num_rows + wi]};
                assign w_ext_state_n_terms[((wi * degree + 3) + 1) * data_width - 1 -: data_width] =
                    {{(data_width - 1){1'b0}}, i_x3_n_rows_clusters[gi * num_rows + wi]};

                assign w_conv_coeff_p_terms[((wi * degree + 0) + 1) * bit_width - 1 -: bit_width] =
                    i_coeff0_vec_p_rows_clusters[(gi * num_rows + wi + 1) * bit_width - 1 -: bit_width];
                assign w_conv_coeff_n_terms[((wi * degree + 0) + 1) * bit_width - 1 -: bit_width] =
                    i_coeff0_vec_n_rows_clusters[(gi * num_rows + wi + 1) * bit_width - 1 -: bit_width];
                assign w_conv_coeff_p_terms[((wi * degree + 1) + 1) * bit_width - 1 -: bit_width] =
                    i_coeff1_vec_p_rows_clusters[(gi * num_rows + wi + 1) * bit_width - 1 -: bit_width];
                assign w_conv_coeff_n_terms[((wi * degree + 1) + 1) * bit_width - 1 -: bit_width] =
                    i_coeff1_vec_n_rows_clusters[(gi * num_rows + wi + 1) * bit_width - 1 -: bit_width];
                assign w_conv_coeff_p_terms[((wi * degree + 2) + 1) * bit_width - 1 -: bit_width] =
                    i_coeff2_vec_p_rows_clusters[(gi * num_rows + wi + 1) * bit_width - 1 -: bit_width];
                assign w_conv_coeff_n_terms[((wi * degree + 2) + 1) * bit_width - 1 -: bit_width] =
                    i_coeff2_vec_n_rows_clusters[(gi * num_rows + wi + 1) * bit_width - 1 -: bit_width];
                assign w_conv_coeff_p_terms[((wi * degree + 3) + 1) * bit_width - 1 -: bit_width] =
                    i_coeff3_vec_p_rows_clusters[(gi * num_rows + wi + 1) * bit_width - 1 -: bit_width];
                assign w_conv_coeff_n_terms[((wi * degree + 3) + 1) * bit_width - 1 -: bit_width] =
                    i_coeff3_vec_n_rows_clusters[(gi * num_rows + wi + 1) * bit_width - 1 -: bit_width];
            end

            assign w_conv_state_p_terms = i_use_replay_clusters[gi]
                ? w_replay_sel_state_p_terms
                : w_ext_state_p_terms;
            assign w_conv_state_n_terms = i_use_replay_clusters[gi]
                ? w_replay_sel_state_n_terms
                : w_ext_state_n_terms;

            // Keep the mathematical workload degree unchanged, but make the
            // conventional baseline reserve the configured physical MAC slots.
            // Terms beyond the fixture degree are explicit zero products.
            genvar cwi;
            genvar cti;
            for (cwi = 0; cwi < num_rows; cwi = cwi + 1) begin : gen_conv_baseline_pad_rows
                for (cti = 0; cti < conv_baseline_degree_eff; cti = cti + 1) begin : gen_conv_baseline_pad_terms
                    if (cti < degree) begin : gen_live_term
                        assign w_conv_state_p_terms_baseline[
                            ((cwi * conv_baseline_degree_eff + cti) + 1) *
                            data_width - 1 -: data_width] =
                            w_conv_state_p_terms[((cwi * degree + cti) + 1) *
                            data_width - 1 -: data_width];
                        assign w_conv_state_n_terms_baseline[
                            ((cwi * conv_baseline_degree_eff + cti) + 1) *
                            data_width - 1 -: data_width] =
                            w_conv_state_n_terms[((cwi * degree + cti) + 1) *
                            data_width - 1 -: data_width];
                        assign w_conv_coeff_p_terms_baseline[
                            ((cwi * conv_baseline_degree_eff + cti) + 1) *
                            bit_width - 1 -: bit_width] =
                            w_conv_coeff_p_terms[((cwi * degree + cti) + 1) *
                            bit_width - 1 -: bit_width];
                        assign w_conv_coeff_n_terms_baseline[
                            ((cwi * conv_baseline_degree_eff + cti) + 1) *
                            bit_width - 1 -: bit_width] =
                            w_conv_coeff_n_terms[((cwi * degree + cti) + 1) *
                            bit_width - 1 -: bit_width];
                    end else begin : gen_zero_term
                        assign w_conv_state_p_terms_baseline[
                            ((cwi * conv_baseline_degree_eff + cti) + 1) *
                            data_width - 1 -: data_width] =
                            {data_width{1'b0}};
                        assign w_conv_state_n_terms_baseline[
                            ((cwi * conv_baseline_degree_eff + cti) + 1) *
                            data_width - 1 -: data_width] =
                            {data_width{1'b0}};
                        assign w_conv_coeff_p_terms_baseline[
                            ((cwi * conv_baseline_degree_eff + cti) + 1) *
                            bit_width - 1 -: bit_width] =
                            {bit_width{1'b0}};
                        assign w_conv_coeff_n_terms_baseline[
                            ((cwi * conv_baseline_degree_eff + cti) + 1) *
                            bit_width - 1 -: bit_width] =
                            {bit_width{1'b0}};
                    end
                end
            end

            assign w_mode7_coeff_p_terms_clusters[gi * num_rows * degree *
                bit_width +: num_rows * degree * bit_width] = w_conv_coeff_p_terms;
            assign w_mode7_coeff_n_terms_clusters[gi * num_rows * degree *
                bit_width +: num_rows * degree * bit_width] = w_conv_coeff_n_terms;
            assign w_mode7_bias_p_rows_clusters[gi * num_rows * (bit_width + 2)
                +: num_rows * (bit_width + 2)] =
                i_bias_vec_p_rows_clusters[(gi + 1) * num_rows *
                (bit_width + 2) - 1 -: num_rows * (bit_width + 2)];
            assign w_mode7_bias_n_rows_clusters[gi * num_rows * (bit_width + 2)
                +: num_rows * (bit_width + 2)] =
                i_bias_vec_n_rows_clusters[(gi + 1) * num_rows *
                (bit_width + 2) - 1 -: num_rows * (bit_width + 2)];

            if (row_datapath_mode == 0) begin : gen_online_datapath
                online_row_cluster_delta_cert #(
                    .num_rows(num_rows),
                    .bit_width(bit_width),
                    .bound_width(bound_width),
                    .coeff_width(coeff_width),
                    .acc_width(acc_width),
                    .block_size(block_size),
                    .num_blocks(num_blocks),
                    .cert_product_pipeline(cert_product_pipeline),
                    .cert_operand_pipeline(cert_operand_pipeline),
                    .cert_compare_pipeline(cert_compare_pipeline)
                ) cluster_datapath (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_ena_rows(i_ena_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                    .i_x0_p_rows(w_drv_x0_p),
                    .i_x0_n_rows(w_drv_x0_n),
                    .i_x1_p_rows(w_drv_x1_p),
                    .i_x1_n_rows(w_drv_x1_n),
                    .i_x2_p_rows(w_drv_x2_p),
                    .i_x2_n_rows(w_drv_x2_n),
                    .i_x3_p_rows(w_drv_x3_p),
                    .i_x3_n_rows(w_drv_x3_n),
                    .i_coeff0_vec_p_rows(i_coeff0_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                    .i_coeff0_vec_n_rows(i_coeff0_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                    .i_coeff1_vec_p_rows(i_coeff1_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                    .i_coeff1_vec_n_rows(i_coeff1_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                    .i_coeff2_vec_p_rows(i_coeff2_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                    .i_coeff2_vec_n_rows(i_coeff2_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                    .i_coeff3_vec_p_rows(i_coeff3_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                    .i_coeff3_vec_n_rows(i_coeff3_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                    .i_bias_vec_p_rows(i_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_bias_vec_n_rows(i_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_x_old_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_x_old_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_tail_bound(i_tail_bound_clusters[(gi + 1) * bound_width - 1 -: bound_width]),
                    .i_block_weights(i_block_weights_clusters[(gi + 1) * num_rows * num_blocks * coeff_width - 1 -: num_rows * num_blocks * coeff_width]),
                    .i_eta(i_eta_clusters[(gi + 1) * acc_width - 1 -: acc_width]),
                    .o_valid_rows(w_valid_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                    .o_sum_p_rows(w_sum_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_sum_n_rows(w_sum_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_abs_upper_rows(w_abs_upper_rows_unused),
                    .o_block_bounds(w_block_bounds_unused),
                    .o_cluster_valid(w_cluster_valid[gi]),
                    .o_cluster_certified(w_cluster_certified[gi]),
                    .o_cluster_max_error(w_cluster_max_error[(gi + 1) * acc_width - 1 -: acc_width])
                );
                assign w_prefix_cluster_valid[gi] = w_cluster_valid[gi];
                assign w_prefix_cluster_certified[gi] = w_cluster_certified[gi];
            end else if (row_datapath_mode == 2) begin : gen_full_digit_datapath
                iter_digit_serial_full_row_cluster_delta_cert #(
                    .num_rows(num_rows),
                    .degree(degree),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .bias_width(bit_width + 2),
                    .bound_width(bound_width),
                    .coeff_width(coeff_width),
                    .acc_width(acc_width),
                    .mac_acc_width(mac_acc_width),
                    .block_size(block_size),
                    .num_blocks(num_blocks),
                    .cert_product_pipeline(cert_product_pipeline),
                    .cert_operand_pipeline(cert_operand_pipeline),
                    .cert_compare_pipeline(cert_compare_pipeline),
                    .enable_prefix_cert(enable_prefix_cert),
                    .product_shift(conv_product_shift)
                ) cluster_datapath (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_start((|w_full_digit_ena_rows) &&
                             (w_full_digit_digit_idx == {$clog2(data_width){1'b0}})),
                    .i_valid_digit(|w_full_digit_ena_rows),
                    .i_last_digit((|w_full_digit_ena_rows) &&
                                  (w_full_digit_digit_idx == data_width - 1)),
                    .i_digit_idx(w_full_digit_digit_idx),
                    .i_state_digit_p_terms_rows(w_full_digit_state_p_terms),
                    .i_state_digit_n_terms_rows(w_full_digit_state_n_terms),
                    .i_coeff_p_terms_rows(w_conv_coeff_p_terms),
                    .i_coeff_n_terms_rows(w_conv_coeff_n_terms),
                    .i_bias_p_rows(i_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_bias_n_rows(i_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_old_state_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_old_state_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_tail_bound(i_tail_bound_clusters[(gi + 1) * bound_width - 1 -: bound_width]),
                    .i_block_weights(i_block_weights_clusters[(gi + 1) * num_rows * num_blocks * coeff_width - 1 -: num_rows * num_blocks * coeff_width]),
                    .i_eta(i_eta_clusters[(gi + 1) * acc_width - 1 -: acc_width]),
                    .o_valid_rows(w_valid_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                    .o_sum_rows(),
                    .o_sum_p_rows(w_sum_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_sum_n_rows(w_sum_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_abs_upper_rows(w_abs_upper_rows_unused),
                    .o_prefix_abs_upper_rows(),
                    .o_block_bounds(w_block_bounds_unused),
                    .o_cluster_valid(w_cluster_valid[gi]),
                    .o_cluster_certified(w_cluster_certified[gi]),
                    .o_cluster_max_error(w_cluster_max_error[(gi + 1) * acc_width - 1 -: acc_width]),
                    .o_prefix_cluster_valid(w_prefix_cluster_valid[gi]),
                    .o_prefix_cluster_certified(w_prefix_cluster_certified[gi]),
                    .o_prefix_cluster_max_error()
                );
            end else if (row_datapath_mode == 3) begin : gen_solver_native_digit_stream_datapath
                iter_solver_native_cluster_delta_cert_top #(
                    .num_rows(num_rows),
                    .degree(degree),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .bias_width(bit_width + 2),
                    .bound_width(bound_width),
                    .coeff_width(coeff_width),
                    .acc_width(acc_width),
                    .block_size(block_size),
                    .num_blocks(num_blocks),
                    .skip_digits(solver_native_skip_digits),
                    .affine_guard_shift(solver_native_affine_guard_shift),
                    .sample_width(solver_native_sample_width),
                    .row_idx_width(row_idx_width),
                    .digit_idx_width($clog2(data_width)),
                    .cert_product_pipeline(cert_product_pipeline),
                    .cert_operand_pipeline(cert_operand_pipeline),
                    .cert_compare_pipeline(cert_compare_pipeline)
                ) cluster_datapath (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_start((|w_full_digit_ena_rows) &&
                             (w_full_digit_digit_idx == {$clog2(data_width){1'b0}})),
                    .i_valid_digit(|w_full_digit_ena_rows),
                    .i_ena_rows(w_full_digit_ena_rows),
                    .i_digit_idx(w_full_digit_digit_idx),
                    .i_use_replay(1'b0),
                    .i_clear_write_bank(i_start_iter),
                    .i_commit_swap(i_commit_iter),
                    .i_load_state(i_load_state_clusters[gi]),
                    .i_load_bank_sel(i_load_state_bank_sel),
                    .i_load_row_idx(i_load_state_row_idx),
                    .i_load_state_p(i_load_state_p),
                    .i_load_state_n(i_load_state_n),
                    .i_src_row_idx({num_rows * degree * row_idx_width{1'b0}}),
                    .i_ext_x0_p_rows(w_drv_x0_p),
                    .i_ext_x0_n_rows(w_drv_x0_n),
                    .i_ext_x1_p_rows(w_drv_x1_p),
                    .i_ext_x1_n_rows(w_drv_x1_n),
                    .i_ext_x2_p_rows(w_drv_x2_p),
                    .i_ext_x2_n_rows(w_drv_x2_n),
                    .i_ext_x3_p_rows(w_drv_x3_p),
                    .i_ext_x3_n_rows(w_drv_x3_n),
                    .i_coeff_p_terms_rows(w_conv_coeff_p_terms),
                    .i_coeff_n_terms_rows(w_conv_coeff_n_terms),
                    .i_bias_p_rows(i_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_bias_n_rows(i_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_block_weights(i_block_weights_clusters[(gi + 1) * num_rows * num_blocks * coeff_width - 1 -: num_rows * num_blocks * coeff_width]),
                    .i_eta(i_eta_clusters[(gi + 1) * acc_width - 1 -: acc_width]),
                    .i_tail_bound(i_tail_bound_clusters[(gi + 1) * bound_width - 1 -: bound_width]),
                    .o_replay_x0_p_rows(),
                    .o_replay_x0_n_rows(),
                    .o_replay_x1_p_rows(),
                    .o_replay_x1_n_rows(),
                    .o_write_done_rows(w_solver_native_write_done_rows),
                    .o_abs_upper_rows(w_abs_upper_rows_unused),
                    .o_block_bounds(w_block_bounds_unused),
                    .o_cluster_valid(w_cluster_valid[gi]),
                    .o_cluster_certified(w_cluster_certified[gi]),
                    .o_cluster_max_error(w_cluster_max_error[(gi + 1) * acc_width - 1 -: acc_width]),
                    .o_read_state_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_read_state_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width])
                );
                assign w_valid_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] =
                    w_solver_native_write_done_rows;
                assign w_sum_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width] =
                    {num_rows * data_width{1'b0}};
                assign w_sum_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width] =
                    {num_rows * data_width{1'b0}};
                assign w_prefix_cluster_valid[gi] = w_cluster_valid[gi];
                assign w_prefix_cluster_certified[gi] = w_cluster_certified[gi];
                assign w_read_bank_sel_clusters[gi] = 1'b0;
            end else if (row_datapath_mode == 4) begin : gen_wavefront_superstep_datapath
                wire [num_rows - 1 : 0] w_superstep_final_valid_rows;
                wire [num_rows * $clog2(data_width) - 1 : 0] w_superstep_final_digit_idx_rows;
                wire [num_rows - 1 : 0] w_superstep_final_digit_p_rows;
                wire [num_rows - 1 : 0] w_superstep_final_digit_n_rows;
                wire [wavefront_superstep_stages - 1 : 0] w_superstep_stage_done;
                wire [wavefront_superstep_stages * mode4_source_rows - 1 : 0]
                    w_superstep_inter_stage_source_p_rows;
                wire [wavefront_superstep_stages * mode4_source_rows - 1 : 0]
                    w_superstep_inter_stage_source_n_rows;

                if (halo_source_replay != 0) begin : gen_mode4_halo_sources
                    for (msi = 0; msi < wavefront_superstep_stages; msi = msi + 1) begin : gen_mode4_halo_stage
                        if (msi == 0) begin : gen_mode4_halo_stage0
                            assign w_superstep_inter_stage_source_p_rows[
                                msi * mode4_source_rows +: mode4_source_rows] =
                                {mode4_source_rows{1'b0}};
                            assign w_superstep_inter_stage_source_n_rows[
                                msi * mode4_source_rows +: mode4_source_rows] =
                                {mode4_source_rows{1'b0}};
                        end else begin : gen_mode4_halo_later_stage
                            for (mhi = 0; mhi < (2 * halo_cluster_radius + 1); mhi = mhi + 1) begin : gen_mode4_halo_slot
                                localparam integer src_cluster = gi + mhi - halo_cluster_radius;

                                if (src_cluster >= 0 && src_cluster < num_clusters) begin : gen_mode4_valid_halo
                                    assign w_superstep_inter_stage_source_p_rows[
                                        msi * mode4_source_rows + mhi * num_rows +: num_rows] =
                                        w_mode4_stage_commit_digit_p_rows_clusters[
                                            (src_cluster * wavefront_superstep_stages + (msi - 1)) *
                                            num_rows +: num_rows];
                                    assign w_superstep_inter_stage_source_n_rows[
                                        msi * mode4_source_rows + mhi * num_rows +: num_rows] =
                                        w_mode4_stage_commit_digit_n_rows_clusters[
                                            (src_cluster * wavefront_superstep_stages + (msi - 1)) *
                                            num_rows +: num_rows];
                                end else begin : gen_mode4_zero_halo
                                    assign w_superstep_inter_stage_source_p_rows[
                                        msi * mode4_source_rows + mhi * num_rows +: num_rows] =
                                        {num_rows{1'b0}};
                                    assign w_superstep_inter_stage_source_n_rows[
                                        msi * mode4_source_rows + mhi * num_rows +: num_rows] =
                                        {num_rows{1'b0}};
                                end
                            end
                        end
                    end
                end else if (global_source_replay != 0) begin : gen_mode4_global_sources
                    for (msi = 0; msi < wavefront_superstep_stages; msi = msi + 1) begin : gen_mode4_global_stage
                        if (msi == 0) begin : gen_mode4_global_stage0
                            assign w_superstep_inter_stage_source_p_rows[
                                msi * mode4_source_rows +: mode4_source_rows] =
                                {mode4_source_rows{1'b0}};
                            assign w_superstep_inter_stage_source_n_rows[
                                msi * mode4_source_rows +: mode4_source_rows] =
                                {mode4_source_rows{1'b0}};
                        end else begin : gen_mode4_global_later_stage
                            for (mgi = 0; mgi < num_clusters; mgi = mgi + 1) begin : gen_mode4_global_cluster
                                assign w_superstep_inter_stage_source_p_rows[
                                    msi * mode4_source_rows + mgi * num_rows +: num_rows] =
                                    w_mode4_stage_commit_digit_p_rows_clusters[
                                        (mgi * wavefront_superstep_stages + (msi - 1)) *
                                        num_rows +: num_rows];
                                assign w_superstep_inter_stage_source_n_rows[
                                    msi * mode4_source_rows + mgi * num_rows +: num_rows] =
                                    w_mode4_stage_commit_digit_n_rows_clusters[
                                        (mgi * wavefront_superstep_stages + (msi - 1)) *
                                        num_rows +: num_rows];
                            end
                        end
                    end
                end else begin : gen_mode4_no_halo_sources
                    assign w_superstep_inter_stage_source_p_rows =
                        {wavefront_superstep_stages * mode4_source_rows{1'b0}};
                    assign w_superstep_inter_stage_source_n_rows =
                        {wavefront_superstep_stages * mode4_source_rows{1'b0}};
                end

                iter_wavefront_superstep_cluster_state_top #(
                    .superstep_stages(wavefront_superstep_stages),
                    .num_rows(num_rows),
                    .degree(degree),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .bias_width(bit_width + 2),
                    .bound_width(bound_width),
                    .coeff_width(coeff_width),
                    .acc_width(acc_width),
                    .block_size(block_size),
                    .num_blocks(num_blocks),
                    .skip_digits(solver_native_skip_digits),
                    .sample_width(solver_native_sample_width),
                    .affine_guard_shift(solver_native_affine_guard_shift),
                    .row_idx_width(row_idx_width),
                    .source_rows(mode4_source_rows),
                    .src_idx_width(src_idx_width),
                    .digit_idx_width(digit_idx_width),
                    .inter_stage_delay_cycles(wavefront_inter_stage_delay_cycles),
                    .inter_stage_source_mode(
                        ((halo_source_replay != 0) || (global_source_replay != 0)) ? 2 : 1),
                    .cert_product_pipeline(cert_product_pipeline),
                    .cert_operand_pipeline(cert_operand_pipeline),
                    .cert_compare_pipeline(cert_compare_pipeline)
                ) cluster_datapath (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_start((|w_full_digit_ena_rows) &&
                             (w_full_digit_digit_idx == {$clog2(data_width){1'b0}})),
                    .i_valid_digit(|w_full_digit_ena_rows),
                    .i_digit_idx(w_full_digit_digit_idx),
                    .i_use_replay(1'b0),
                    .i_clear_write_bank(i_start_iter),
                    .i_commit_swap(i_commit_iter),
                    .i_load_state(i_load_state_clusters[gi]),
                    .i_load_bank_sel(i_load_state_bank_sel),
                    .i_load_row_idx(i_load_state_row_idx),
                    .i_load_state_p(i_load_state_p),
                    .i_load_state_n(i_load_state_n),
                    .i_src_row_idx(i_src_row_idx_clusters[(gi + 1) * num_rows *
                        degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                    .i_inter_stage_source_p_rows(w_superstep_inter_stage_source_p_rows),
                    .i_inter_stage_source_n_rows(w_superstep_inter_stage_source_n_rows),
                    .i_ext_x0_p_rows(w_drv_x0_p),
                    .i_ext_x0_n_rows(w_drv_x0_n),
                    .i_ext_x1_p_rows(w_drv_x1_p),
                    .i_ext_x1_n_rows(w_drv_x1_n),
                    .i_ext_x2_p_rows(w_drv_x2_p),
                    .i_ext_x2_n_rows(w_drv_x2_n),
                    .i_ext_x3_p_rows(w_drv_x3_p),
                    .i_ext_x3_n_rows(w_drv_x3_n),
                    .i_coeff_p_terms_rows(w_conv_coeff_p_terms),
                    .i_coeff_n_terms_rows(w_conv_coeff_n_terms),
                    .i_bias_p_rows(i_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_bias_n_rows(i_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_block_weights(i_block_weights_clusters[(gi + 1) * num_rows * num_blocks * coeff_width - 1 -: num_rows * num_blocks * coeff_width]),
                    .i_eta(i_eta_clusters[(gi + 1) * acc_width - 1 -: acc_width]),
                    .i_tail_bound(i_tail_bound_clusters[(gi + 1) * bound_width - 1 -: bound_width]),
                    .o_replay_x0_p_rows(),
                    .o_replay_x0_n_rows(),
                    .o_replay_x1_p_rows(),
                    .o_replay_x1_n_rows(),
                    .o_replay_x2_p_rows(),
                    .o_replay_x2_n_rows(),
                    .o_replay_x3_p_rows(),
                    .o_replay_x3_n_rows(),
                    .o_final_valid_rows(w_superstep_final_valid_rows),
                    .o_final_digit_idx_rows(w_superstep_final_digit_idx_rows),
                    .o_final_digit_p_rows(w_superstep_final_digit_p_rows),
                    .o_final_digit_n_rows(w_superstep_final_digit_n_rows),
                    .o_read_state_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_read_state_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_cluster_valid(w_cluster_valid[gi]),
                    .o_cluster_certified(w_cluster_certified[gi]),
                    .o_cluster_max_error(w_cluster_max_error[(gi + 1) * acc_width - 1 -: acc_width]),
                    .o_stage_commit_valid_rows(
                        w_mode4_stage_commit_valid_rows_clusters[(gi + 1) *
                        wavefront_superstep_stages * num_rows - 1 -:
                        wavefront_superstep_stages * num_rows]),
                    .o_stage_commit_digit_idx_rows(
                        w_mode4_stage_commit_digit_idx_rows_clusters[(gi + 1) *
                        wavefront_superstep_stages * num_rows * digit_idx_width - 1 -:
                        wavefront_superstep_stages * num_rows * digit_idx_width]),
                    .o_stage_commit_digit_p_rows(
                        w_mode4_stage_commit_digit_p_rows_clusters[(gi + 1) *
                        wavefront_superstep_stages * num_rows - 1 -:
                        wavefront_superstep_stages * num_rows]),
                    .o_stage_commit_digit_n_rows(
                        w_mode4_stage_commit_digit_n_rows_clusters[(gi + 1) *
                        wavefront_superstep_stages * num_rows - 1 -:
                        wavefront_superstep_stages * num_rows]),
                    .o_stage_done(w_superstep_stage_done)
                );
                assign w_valid_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] =
                    w_superstep_final_valid_rows;
                assign w_sum_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width] =
                    {num_rows * data_width{1'b0}};
                assign w_sum_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width] =
                    {num_rows * data_width{1'b0}};
                assign w_prefix_cluster_valid[gi] = w_cluster_valid[gi];
                assign w_prefix_cluster_certified[gi] = w_cluster_certified[gi];
                assign w_read_bank_sel_clusters[gi] = 1'b0;
            end else if (row_datapath_mode == 5) begin : gen_prior_online_datapath
                // Same-shell prior-online baseline hook.
                //
                // This path wraps the original MSDF_MUL_ADD_8 operator in the
                // same runtime/state/certification shell used by the new
                // solver experiments.  It intentionally keeps the prior
                // operator's full-word assembly boundary, so it is a baseline
                // for "operator-level online arithmetic inside a solver" rather
                // than the final digit-stream solver datapath.
                iter_prior_online_mma8_row_cluster_delta_cert #(
                    .num_rows(num_rows),
                    .degree(degree),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .bias_width(bit_width + 2),
                    .capture_unit(prior_capture_unit),
                    .bound_width(bound_width),
                    .coeff_width(coeff_width),
                    .acc_width(acc_width),
                    .block_size(block_size),
                    .num_blocks(num_blocks),
                    .cert_product_pipeline(cert_product_pipeline),
                    .cert_operand_pipeline(cert_operand_pipeline),
                    .cert_compare_pipeline(cert_compare_pipeline)
                ) cluster_datapath (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_start(|i_ena_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                    .i_state_p_terms_rows(w_conv_state_p_terms),
                    .i_state_n_terms_rows(w_conv_state_n_terms),
                    .i_coeff_p_terms_rows(w_conv_coeff_p_terms),
                    .i_coeff_n_terms_rows(w_conv_coeff_n_terms),
                    .i_bias_p_rows(i_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_bias_n_rows(i_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_old_state_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_old_state_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_tail_bound(i_tail_bound_clusters[(gi + 1) * bound_width - 1 -: bound_width]),
                    .i_block_weights(i_block_weights_clusters[(gi + 1) * num_rows * num_blocks * coeff_width - 1 -: num_rows * num_blocks * coeff_width]),
                    .i_eta(i_eta_clusters[(gi + 1) * acc_width - 1 -: acc_width]),
                    .o_valid_rows(w_valid_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                    .o_sum_p_rows(w_sum_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_sum_n_rows(w_sum_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_abs_upper_rows(w_abs_upper_rows_unused),
                    .o_block_bounds(w_block_bounds_unused),
                    .o_cluster_valid(w_cluster_valid[gi]),
                    .o_cluster_certified(w_cluster_certified[gi]),
                    .o_cluster_max_error(w_cluster_max_error[(gi + 1) * acc_width - 1 -: acc_width])
                );
                assign w_prefix_cluster_valid[gi] = w_cluster_valid[gi];
                assign w_prefix_cluster_certified[gi] = w_cluster_certified[gi];
            end else if (row_datapath_mode == 6) begin : gen_prior_digit_stream_datapath
                // Solver-level digit-stream version of the prior operator.
                //
                // This path keeps the original MSDF_MUL_ADD_8 recurrence but
                // removes the P2 full-word assembly boundary: output digits are
                // committed directly into the digit-stream state bank and the
                // L1 delta is computed from committed digits.
                iter_prior_online_mma8_digit_stream_cluster_delta_cert #(
                    .num_rows(num_rows),
                    .degree(degree),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .bias_width(bit_width + 2),
                    .capture_unit(prior_capture_unit),
                    .bound_width(bound_width),
                    .coeff_width(coeff_width),
                    .acc_width(acc_width),
                    .block_size(block_size),
                    .num_blocks(num_blocks),
                    .row_idx_width(row_idx_width),
                    .cert_product_pipeline(cert_product_pipeline),
                    .cert_operand_pipeline(cert_operand_pipeline),
                    .cert_compare_pipeline(cert_compare_pipeline)
                ) cluster_datapath (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_start((|w_full_digit_ena_rows) &&
                             (w_full_digit_digit_idx == {$clog2(data_width){1'b0}})),
                    .i_valid_digit(|w_full_digit_ena_rows),
                    .i_ena_rows(w_full_digit_ena_rows),
                    .i_digit_idx(w_full_digit_digit_idx),
                    .i_clear_write_bank(i_start_iter),
                    .i_commit_swap(i_commit_iter),
                    .i_load_state(i_load_state_clusters[gi]),
                    .i_load_bank_sel(i_load_state_bank_sel),
                    .i_load_row_idx(i_load_state_row_idx),
                    .i_load_state_p(i_load_state_p),
                    .i_load_state_n(i_load_state_n),
                    .i_state_p_terms_rows(w_conv_state_p_terms),
                    .i_state_n_terms_rows(w_conv_state_n_terms),
                    .i_ext_x0_p_rows(w_drv_x0_p),
                    .i_ext_x0_n_rows(w_drv_x0_n),
                    .i_ext_x1_p_rows(w_drv_x1_p),
                    .i_ext_x1_n_rows(w_drv_x1_n),
                    .i_ext_x2_p_rows(w_drv_x2_p),
                    .i_ext_x2_n_rows(w_drv_x2_n),
                    .i_ext_x3_p_rows(w_drv_x3_p),
                    .i_ext_x3_n_rows(w_drv_x3_n),
                    .i_coeff_p_terms_rows(w_conv_coeff_p_terms),
                    .i_coeff_n_terms_rows(w_conv_coeff_n_terms),
                    .i_bias_p_rows(i_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_bias_n_rows(i_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_block_weights(i_block_weights_clusters[(gi + 1) * num_rows * num_blocks * coeff_width - 1 -: num_rows * num_blocks * coeff_width]),
                    .i_eta(i_eta_clusters[(gi + 1) * acc_width - 1 -: acc_width]),
                    .i_tail_bound(i_tail_bound_clusters[(gi + 1) * bound_width - 1 -: bound_width]),
                    .o_write_done_rows(w_solver_native_write_done_rows),
                    .o_abs_upper_rows(w_abs_upper_rows_unused),
                    .o_block_bounds(w_block_bounds_unused),
                    .o_cluster_valid(w_cluster_valid[gi]),
                    .o_cluster_certified(w_cluster_certified[gi]),
                    .o_cluster_max_error(w_cluster_max_error[(gi + 1) * acc_width - 1 -: acc_width]),
                    .o_read_state_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_read_state_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width])
                );
                assign w_valid_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] =
                    w_solver_native_write_done_rows;
                assign w_sum_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width] =
                    {num_rows * data_width{1'b0}};
                assign w_sum_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width] =
                    {num_rows * data_width{1'b0}};
                assign w_prefix_cluster_valid[gi] = w_cluster_valid[gi];
                assign w_prefix_cluster_certified[gi] = w_cluster_certified[gi];
                assign w_read_bank_sel_clusters[gi] = 1'b0;
            end else if (row_datapath_mode == 7) begin : gen_prior_wavefront_datapath
                wire [num_rows - 1 : 0] w_delta_valid_rows;
                wire [num_rows - 1 : 0] w_delta_final_rows;
                wire [num_rows * bound_width - 1 : 0] w_abs_upper_rows;
                wire [num_rows * data_width - 1 : 0] w_mode7_read_state_p_rows;
                wire [num_rows * data_width - 1 : 0] w_mode7_read_state_n_rows;
                wire [digit_idx_width - 1 : 0] w_mode7_write_digit_idx;
                localparam integer mode7_prev_stage_idx =
                    wavefront_superstep_stages - 2;
                reg [num_rows * data_width - 1 : 0] r_mode7_prev_stage_p_rows;
                reg [num_rows * data_width - 1 : 0] r_mode7_prev_stage_n_rows;
                integer mode7_prev_row_seq;
                integer mode7_prev_flat_row_seq;
                integer mode7_prev_bit_sel_seq;

                assign w_mode7_write_digit_idx =
                    w_mode7_final_digit_idx_rows[gi * num_rows *
                        digit_idx_width +: digit_idx_width];

                iter_digit_stream_state_ping_pong_bank #(
                    .num_rows(num_rows),
                    .data_width(data_width),
                    .msb_first(1),
                    .row_idx_width(row_idx_width),
                    .digit_idx_width(digit_idx_width)
                ) state_pp (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_commit_swap(i_commit_iter),
                    .i_clear_write_bank(i_start_iter),
                    .i_load_state(i_load_state_clusters[gi]),
                    .i_load_bank_sel(i_load_state_bank_sel),
                    .i_load_row_idx(i_load_state_row_idx),
                    .i_load_state_p(i_load_state_p),
                    .i_load_state_n(i_load_state_n),
                    .i_write_digit_valid_rows(w_mode7_final_valid_rows[
                        gi * num_rows +: num_rows]),
                    .i_write_digit_idx(w_mode7_write_digit_idx),
                    .i_write_digit_p_rows(w_mode7_final_digit_p_rows[
                        gi * num_rows +: num_rows]),
                    .i_write_digit_n_rows(w_mode7_final_digit_n_rows[
                        gi * num_rows +: num_rows]),
                    .o_read_bank_sel(w_read_bank_sel_clusters[gi]),
                    .o_read_state_p_rows(w_mode7_read_state_p_rows),
                    .o_read_state_n_rows(w_mode7_read_state_n_rows),
                    .o_write_state_p_rows(),
                    .o_write_state_n_rows()
                );

                assign w_x_old_p_rows_clusters[(gi + 1) * num_rows *
                    data_width - 1 -: num_rows * data_width] =
                    w_mode7_read_state_p_rows;
                assign w_x_old_n_rows_clusters[(gi + 1) * num_rows *
                    data_width - 1 -: num_rows * data_width] =
                    w_mode7_read_state_n_rows;

                // Certification for a fused K-stage wavefront must compare
                // x^(k+K) against x^(k+K-1), not against the super-step input
                // x^k.  Cache the penultimate stage as a digit word so the
                // final stage can feed the existing delta-bound unit.
                always @(posedge i_clk) begin
                    if (i_rst || i_start_iter) begin
                        r_mode7_prev_stage_p_rows <= {num_rows * data_width{1'b0}};
                        r_mode7_prev_stage_n_rows <= {num_rows * data_width{1'b0}};
                    end else begin
                        for (mode7_prev_row_seq = 0;
                             mode7_prev_row_seq < num_rows;
                             mode7_prev_row_seq = mode7_prev_row_seq + 1) begin
                            mode7_prev_flat_row_seq =
                                gi * num_rows + mode7_prev_row_seq;
                            if (w_mode7_stage_valid_rows[
                                    mode7_prev_stage_idx * num_clusters *
                                    num_rows + mode7_prev_flat_row_seq]) begin
                                mode7_prev_bit_sel_seq =
                                    data_width - 1 -
                                    w_mode7_stage_digit_idx_rows[
                                        (mode7_prev_stage_idx * num_clusters *
                                         num_rows + mode7_prev_flat_row_seq) *
                                        digit_idx_width +: digit_idx_width];
                                r_mode7_prev_stage_p_rows[
                                    mode7_prev_row_seq * data_width +
                                    mode7_prev_bit_sel_seq] <=
                                    w_mode7_stage_digit_p_rows[
                                        mode7_prev_stage_idx * num_clusters *
                                        num_rows + mode7_prev_flat_row_seq];
                                r_mode7_prev_stage_n_rows[
                                    mode7_prev_row_seq * data_width +
                                    mode7_prev_bit_sel_seq] <=
                                    w_mode7_stage_digit_n_rows[
                                        mode7_prev_stage_idx * num_clusters *
                                        num_rows + mode7_prev_flat_row_seq];
                            end
                        end
                    end
                end

                for (wi = 0; wi < num_rows; wi = wi + 1) begin : gen_mode7_delta_rows
                    wire [bound_width - 1 : 0] w_abs_upper;
                    wire [bound_width : 0] w_abs_upper_with_tail;
                    wire w_prev_stage_digit_p;
                    wire w_prev_stage_digit_n;
                    integer mode7_delta_bit_sel;

                    always @(*) begin
                        mode7_delta_bit_sel =
                            data_width - 1 - w_mode7_write_digit_idx;
                    end

                    assign w_prev_stage_digit_p =
                        r_mode7_prev_stage_p_rows[wi * data_width +
                            mode7_delta_bit_sel];
                    assign w_prev_stage_digit_n =
                        r_mode7_prev_stage_n_rows[wi * data_width +
                            mode7_delta_bit_sel];

                    iter_digit_stream_delta_bound #(
                        .data_width(data_width),
                        .bound_width(bound_width),
                        .acc_width(acc_width),
                        .final_only(1),
                        .digit_idx_width(digit_idx_width)
                    ) delta_bound (
                        .i_clk(i_clk),
                        .i_rst(i_rst || i_start_iter),
                        .i_start(w_mode7_final_valid_rows[gi * num_rows + wi] &&
                                 (w_mode7_write_digit_idx == {digit_idx_width{1'b0}})),
                        .i_valid(w_mode7_final_valid_rows[gi * num_rows + wi]),
                        .i_digit_idx(w_mode7_write_digit_idx),
                        .i_new_digit_p(w_mode7_final_digit_p_rows[gi * num_rows + wi]),
                        .i_new_digit_n(w_mode7_final_digit_n_rows[gi * num_rows + wi]),
                        .i_old_digit_p(w_prev_stage_digit_p),
                        .i_old_digit_n(w_prev_stage_digit_n),
                        .o_valid(w_delta_valid_rows[wi]),
                        .o_prefix_delta(),
                        .o_abs_upper(w_abs_upper),
                        .o_final(w_delta_final_rows[wi])
                    );

                    assign w_abs_upper_with_tail =
                        {1'b0, w_abs_upper} +
                        {1'b0, i_tail_bound_clusters[(gi + 1) * bound_width -
                            1 -: bound_width]};
                    assign w_abs_upper_rows[(wi + 1) * bound_width - 1 -:
                        bound_width] =
                        w_abs_upper_with_tail[bound_width]
                            ? {bound_width{1'b1}}
                            : w_abs_upper_with_tail[bound_width - 1 : 0];
                end

                online_row_cluster_block_cert #(
                    .num_rows(num_rows),
                    .block_size(block_size),
                    .bound_width(bound_width),
                    .coeff_width(coeff_width),
                    .acc_width(acc_width),
                    .num_blocks(num_blocks),
                    .cert_product_pipeline(cert_product_pipeline),
                    .cert_operand_pipeline(cert_operand_pipeline),
                    .cert_compare_pipeline(cert_compare_pipeline),
                    .input_pipeline(0),
                    .output_pipeline(0)
                ) cluster_cert (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_valid_rows(w_delta_valid_rows & w_delta_final_rows),
                    .i_row_abs_upper(w_abs_upper_rows),
                    .i_block_weights(i_block_weights_clusters[(gi + 1) *
                        num_rows * num_blocks * coeff_width - 1 -:
                        num_rows * num_blocks * coeff_width]),
                    .i_eta(i_eta_clusters[(gi + 1) * acc_width - 1 -:
                        acc_width]),
                    .o_valid(w_cluster_valid[gi]),
                    .o_block_bounds(w_block_bounds_unused),
                    .o_certified(w_cluster_certified[gi]),
                    .o_max_error(w_cluster_max_error[(gi + 1) * acc_width -
                        1 -: acc_width])
                );

                assign w_valid_rows_clusters[(gi + 1) * num_rows - 1 -:
                    num_rows] = w_mode7_final_done_rows[gi * num_rows +:
                    num_rows];
                assign w_sum_p_rows_clusters[(gi + 1) * num_rows * data_width -
                    1 -: num_rows * data_width] =
                    {num_rows * data_width{1'b0}};
                assign w_sum_n_rows_clusters[(gi + 1) * num_rows * data_width -
                    1 -: num_rows * data_width] =
                    {num_rows * data_width{1'b0}};
                assign w_prefix_cluster_valid[gi] = w_cluster_valid[gi];
                assign w_prefix_cluster_certified[gi] = w_cluster_certified[gi];
            end else begin : gen_conv_datapath
                if (conv_reserved_degree > 0) begin : gen_reserved_mac_slots
                    (* keep = "true" *)
                    wire [num_rows * conv_reserved_degree * mac_acc_width - 1 : 0]
                        w_reserved_mac_products;

                    (* dont_touch = "true" *)
                    conv_reserved_mac_slots #(
                        .num_rows(num_rows),
                        .live_degree(degree),
                        .reserved_degree(conv_reserved_degree),
                        .data_width(data_width),
                        .bit_width(bit_width),
                        .acc_width(mac_acc_width)
                    ) reserved_mac_slots (
                        .i_clk(i_clk),
                        .i_rst(i_rst),
                        .i_valid(|w_conv_ena_rows),
                        .i_state_p_terms_rows(w_conv_state_p_terms),
                        .i_state_n_terms_rows(w_conv_state_n_terms),
                        .i_coeff_p_terms_rows(w_conv_coeff_p_terms),
                        .i_coeff_n_terms_rows(w_conv_coeff_n_terms),
                        .o_product_rows(w_reserved_mac_products)
                    );
                end

                conv_row_cluster_delta_cert #(
                    .num_rows(num_rows),
                    .degree(conv_baseline_degree_eff),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .bias_width(bit_width + 2),
                    .bound_width(bound_width),
                    .coeff_width(coeff_width),
                    .acc_width(acc_width),
                    .mac_acc_width(mac_acc_width),
                    .block_size(block_size),
                    .num_blocks(num_blocks),
                    .mac_pipeline(conv_mac_pipeline),
                    .product_shift(conv_product_shift),
                    .round_pipeline(conv_round_pipeline),
                    .cert_operand_pipeline(cert_operand_pipeline)
                ) cluster_datapath (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_valid(|w_conv_ena_rows),
                    .i_state_p_terms_rows(w_conv_state_p_terms_baseline),
                    .i_state_n_terms_rows(w_conv_state_n_terms_baseline),
                    .i_coeff_p_terms_rows(w_conv_coeff_p_terms_baseline),
                    .i_coeff_n_terms_rows(w_conv_coeff_n_terms_baseline),
                    .i_bias_p_rows(i_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_bias_n_rows(i_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                    .i_old_state_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_old_state_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_tail_bound(i_tail_bound_clusters[(gi + 1) * bound_width - 1 -: bound_width]),
                    .i_block_weights(i_block_weights_clusters[(gi + 1) * num_rows * num_blocks * coeff_width - 1 -: num_rows * num_blocks * coeff_width]),
                    .i_eta(i_eta_clusters[(gi + 1) * acc_width - 1 -: acc_width]),
                    .o_valid_rows(w_valid_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                    .o_sum_rows(),
                    .o_sum_p_rows(w_sum_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_sum_n_rows(w_sum_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_abs_upper_rows(w_abs_upper_rows_unused),
                    .o_cluster_valid(w_cluster_valid[gi]),
                    .o_cluster_certified(w_cluster_certified[gi]),
                    .o_cluster_max_error(w_cluster_max_error[(gi + 1) * acc_width - 1 -: acc_width])
                );
                assign w_block_bounds_unused = {num_blocks * bound_width{1'b0}};
                assign w_prefix_cluster_valid[gi] = w_cluster_valid[gi];
                assign w_prefix_cluster_certified[gi] = w_cluster_certified[gi];
            end

            if (row_datapath_mode != 3 && row_datapath_mode != 4 &&
                row_datapath_mode != 6 && row_datapath_mode != 7) begin : gen_full_word_state_pp
                iter_state_ping_pong_bank #(
                    .num_rows(num_rows),
                    .data_width(data_width),
                    .row_idx_width(row_idx_width)
                ) state_pp (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_commit_swap(i_commit_iter),
                    .i_load_state(i_load_state_clusters[gi]),
                    .i_load_bank_sel(i_load_state_bank_sel),
                    .i_load_row_idx(i_load_state_row_idx),
                    .i_load_state_p(i_load_state_p),
                    .i_load_state_n(i_load_state_n),
                    .i_valid_rows(w_valid_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                    .i_write_state_p_rows(w_sum_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .i_write_state_n_rows(w_sum_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_read_bank_sel(w_read_bank_sel_clusters[gi]),
                    .o_read_state_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                    .o_read_state_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width])
                );
            end
        end
    endgenerate

    generate
        if (row_datapath_mode == 7) begin : gen_mode7_global_prior_wavefront
            iter_prior_online_mma8_global_wavefront_top #(
                .num_stages(wavefront_superstep_stages),
                .num_rows(num_clusters * num_rows),
                .degree(degree),
                .bit_width(bit_width),
                .data_width(data_width),
                .bias_width(bit_width + 2),
                .src_idx_width(src_idx_width),
                .capture_unit(prior_capture_unit),
                .digit_idx_width(digit_idx_width)
            ) prior_wavefront (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_clear(i_start_iter),
                .i_start((|i_ena_rows_clusters) &&
                         (i_replay_digit_idx == {digit_idx_width{1'b0}})),
                .i_valid_digit(|i_ena_rows_clusters),
                .i_digit_idx(i_replay_digit_idx),
                .i_stage0_state_digit_p_terms_rows(
                    w_mode7_stage0_state_p_terms_clusters),
                .i_stage0_state_digit_n_terms_rows(
                    w_mode7_stage0_state_n_terms_clusters),
                .i_src_row_idx_rows(i_src_row_idx_clusters),
                .i_coeff_p_terms_rows(w_mode7_coeff_p_terms_clusters),
                .i_coeff_n_terms_rows(w_mode7_coeff_n_terms_clusters),
                .i_bias_p_rows(w_mode7_bias_p_rows_clusters),
                .i_bias_n_rows(w_mode7_bias_n_rows_clusters),
                .o_final_valid_rows(w_mode7_final_valid_rows),
                .o_final_digit_idx_rows(w_mode7_final_digit_idx_rows),
                .o_final_digit_p_rows(w_mode7_final_digit_p_rows),
                .o_final_digit_n_rows(w_mode7_final_digit_n_rows),
                .o_final_done_rows(w_mode7_final_done_rows),
                .o_stage_valid_rows(w_mode7_stage_valid_rows),
                .o_stage_digit_idx_rows(w_mode7_stage_digit_idx_rows),
                .o_stage_digit_p_rows(w_mode7_stage_digit_p_rows),
                .o_stage_digit_n_rows(w_mode7_stage_digit_n_rows),
                .o_stage_done_rows(w_mode7_stage_done_rows),
                .o_stage_valid_count(),
                .o_stage_done(w_mode7_stage_done),
                .o_stage_started_before_prev_done(
                    w_mode7_stage_started_before_prev_done)
            );
        end
    endgenerate

    iter_cluster_cert_controller #(
        .num_clusters(num_clusters)
    ) iter_controller (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start_iter(i_start_iter),
        .i_cluster_valid(w_cluster_valid),
        .i_cluster_certified(w_cluster_certified),
        .o_iter_done(w_iter_done_base),
        .o_iter_converged(w_iter_converged_base),
        .o_iter_continue(w_iter_continue_base),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask(o_cert_mask)
    );

    assign w_global_l1_eta = i_eta_clusters[acc_width - 1 : 0];
    assign w_global_l1_converged =
        w_iter_done_base && (r_global_l1_sum_next <= w_global_l1_eta);
    assign o_iter_done = w_iter_done_base;
    assign o_iter_converged =
        (global_l1_cert != 0) ? w_global_l1_converged : w_iter_converged_base;
    assign o_iter_continue =
        (global_l1_cert != 0) ? (w_iter_done_base && !w_global_l1_converged)
                              : w_iter_continue_base;

    assign o_read_bank_sel_clusters = w_read_bank_sel_clusters;
    // These ports expose the online digit replay stream for debug and legacy
    // tests.  In conventional full-word DSP-MAC mode the solver consumes only
    // w_conv_state_*_terms, so keeping the digit stream observable would force
    // Vivado to retain an online-only replay tree in the conventional baseline.
    // Tie the debug ports off in that mode so the routed baseline reflects only
    // the full-word replay + DSP-MAC datapath.
    assign o_drv_x0_p_rows_clusters = (row_datapath_mode == 0) ? w_drv_x0_p_rows_clusters : {(num_clusters * num_rows){1'b0}};
    assign o_drv_x0_n_rows_clusters = (row_datapath_mode == 0) ? w_drv_x0_n_rows_clusters : {(num_clusters * num_rows){1'b0}};
    assign o_drv_x1_p_rows_clusters = (row_datapath_mode == 0) ? w_drv_x1_p_rows_clusters : {(num_clusters * num_rows){1'b0}};
    assign o_drv_x1_n_rows_clusters = (row_datapath_mode == 0) ? w_drv_x1_n_rows_clusters : {(num_clusters * num_rows){1'b0}};
    assign o_drv_x2_p_rows_clusters = (row_datapath_mode == 0) ? w_drv_x2_p_rows_clusters : {(num_clusters * num_rows){1'b0}};
    assign o_drv_x2_n_rows_clusters = (row_datapath_mode == 0) ? w_drv_x2_n_rows_clusters : {(num_clusters * num_rows){1'b0}};
    assign o_drv_x3_p_rows_clusters = (row_datapath_mode == 0) ? w_drv_x3_p_rows_clusters : {(num_clusters * num_rows){1'b0}};
    assign o_drv_x3_n_rows_clusters = (row_datapath_mode == 0) ? w_drv_x3_n_rows_clusters : {(num_clusters * num_rows){1'b0}};
    assign o_cluster_valid = w_cluster_valid;
    assign o_cluster_certified = r_cluster_certified_out;
    assign o_cluster_max_error = r_cluster_max_error_out;
    assign o_prefix_cluster_valid = w_prefix_cluster_valid;
    assign o_prefix_cluster_certified = w_prefix_cluster_certified;
    assign o_x_old_p_rows_clusters = w_x_old_p_rows_clusters;
    assign o_x_old_n_rows_clusters = w_x_old_n_rows_clusters;

    always @(*) begin
        r_cluster_certified_out = r_cluster_certified;
        r_cluster_max_error_out = r_cluster_max_error;
        for (oi = 0; oi < num_clusters; oi = oi + 1) begin
            if (w_cluster_valid[oi]) begin
                r_cluster_certified_out[oi] = w_cluster_certified[oi];
                r_cluster_max_error_out[(oi + 1) * acc_width - 1 -: acc_width] =
                    w_cluster_max_error[(oi + 1) * acc_width - 1 -: acc_width];
            end
        end
    end

    always @(*) begin
        r_global_l1_sum_next = {acc_width{1'b0}};
        for (li = 0; li < num_clusters; li = li + 1) begin
            if (w_cluster_valid[li]) begin
                r_global_l1_term =
                    w_cluster_max_error[(li + 1) * acc_width - 1 -: acc_width];
            end else begin
                r_global_l1_term =
                    r_cluster_max_error[(li + 1) * acc_width - 1 -: acc_width];
            end
            r_global_l1_sum_next = r_global_l1_sum_next + r_global_l1_term;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst || i_start_iter) begin
            r_cluster_certified <= {num_clusters{1'b0}};
            r_cluster_max_error <= {num_clusters * acc_width{1'b0}};
        end else begin
            for (ri = 0; ri < num_clusters; ri = ri + 1) begin
                if (w_cluster_valid[ri]) begin
                    r_cluster_certified[ri] <= w_cluster_certified[ri];
                    r_cluster_max_error[(ri + 1) * acc_width - 1 -: acc_width]
                        <= w_cluster_max_error[(ri + 1) * acc_width - 1 -: acc_width];
                end
            end
        end
    end

endmodule
