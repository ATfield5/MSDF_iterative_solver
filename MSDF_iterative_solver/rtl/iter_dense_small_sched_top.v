`timescale 1ns / 1ps

// Scheduler-integrated dense small ping-pong top.
//
// This top replaces the hand-expanded source-row/coefficient interface with a
// template-oriented fixed-degree row scheduler.

module iter_dense_small_sched_top #(
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
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows)
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_start_iter,
    input                                               i_commit_iter,
    input      [num_clusters - 1 : 0]                   i_use_replay_clusters,
    input      [$clog2(data_width) - 1 : 0]             i_replay_digit_idx,
    input      [num_clusters * num_rows * degree - 1 : 0] i_term_valid_mask_clusters,
    input      [num_clusters * num_rows * degree * row_idx_width - 1 : 0] i_src_row_idx_clusters,
    input      [num_clusters * num_rows * degree * bit_width - 1 : 0] i_coeff_p_terms_clusters,
    input      [num_clusters * num_rows * degree * bit_width - 1 : 0] i_coeff_n_terms_clusters,
    input      [num_clusters * num_rows * (bit_width + 2) - 1 : 0] i_bias_vec_p_rows_clusters,
    input      [num_clusters * num_rows * (bit_width + 2) - 1 : 0] i_bias_vec_n_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_issue_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x0_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x0_n_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x1_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x1_n_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x2_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x2_n_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x3_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x3_n_rows_clusters,
    input      [num_clusters * bound_width - 1 : 0]     i_tail_bound_clusters,
    input      [num_clusters * num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights_clusters,
    input      [num_clusters * acc_width - 1 : 0]       i_eta_clusters,
    output     [num_clusters * num_rows - 1 : 0]        o_sched_row_active_clusters,
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
    output     [num_clusters * num_rows * data_width - 1 : 0] o_x_old_p_rows_clusters,
    output     [num_clusters * num_rows * data_width - 1 : 0] o_x_old_n_rows_clusters,
    output                                              o_iter_done,
    output                                              o_iter_converged,
    output                                              o_iter_continue,
    output     [num_clusters - 1 : 0]                   o_seen_mask,
    output     [num_clusters - 1 : 0]                   o_cert_mask
);

    wire [num_clusters * num_rows - 1 : 0] w_sched_row_active_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_ena_rows_clusters;
    wire [num_clusters * num_rows * degree * row_idx_width - 1 : 0] w_src_row_idx_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff0_vec_p_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff0_vec_n_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff1_vec_p_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff1_vec_n_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff2_vec_p_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff2_vec_n_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff3_vec_p_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff3_vec_n_rows_clusters;
    wire [num_clusters * num_rows * (bit_width + 2) - 1 : 0] w_bias_vec_p_rows_clusters;
    wire [num_clusters * num_rows * (bit_width + 2) - 1 : 0] w_bias_vec_n_rows_clusters;

    genvar gi;
    generate
        for (gi = 0; gi < num_clusters; gi = gi + 1) begin : gen_sched
            iter_fixed_degree_row_scheduler #(
                .num_rows(num_rows),
                .degree(degree),
                .bit_width(bit_width),
                .bias_width(bit_width + 2),
                .row_idx_width(row_idx_width)
            ) row_sched (
                .i_term_valid_mask(i_term_valid_mask_clusters[(gi + 1) * num_rows * degree - 1 -: num_rows * degree]),
                .i_src_row_idx(i_src_row_idx_clusters[(gi + 1) * num_rows * degree * row_idx_width - 1 -: num_rows * degree * row_idx_width]),
                .i_coeff_p_terms(i_coeff_p_terms_clusters[(gi + 1) * num_rows * degree * bit_width - 1 -: num_rows * degree * bit_width]),
                .i_coeff_n_terms(i_coeff_n_terms_clusters[(gi + 1) * num_rows * degree * bit_width - 1 -: num_rows * degree * bit_width]),
                .i_bias_vec_p_rows(i_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                .i_bias_vec_n_rows(i_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                .o_row_active_mask(w_sched_row_active_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .o_src_row_idx(w_src_row_idx_clusters[(gi + 1) * num_rows * degree * row_idx_width - 1 -: num_rows * degree * row_idx_width]),
                .o_coeff0_vec_p_rows(w_coeff0_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff0_vec_n_rows(w_coeff0_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff1_vec_p_rows(w_coeff1_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff1_vec_n_rows(w_coeff1_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff2_vec_p_rows(w_coeff2_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff2_vec_n_rows(w_coeff2_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff3_vec_p_rows(w_coeff3_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff3_vec_n_rows(w_coeff3_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_bias_vec_p_rows(w_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                .o_bias_vec_n_rows(w_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)])
            );

            assign w_ena_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] =
                i_issue_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] &
                w_sched_row_active_clusters[(gi + 1) * num_rows - 1 -: num_rows];
        end
    endgenerate

    iter_dense_small_ping_pong_top #(
        .num_clusters(num_clusters),
        .num_rows(num_rows),
        .degree(degree),
        .bit_width(bit_width),
        .bound_width(bound_width),
        .coeff_width(coeff_width),
        .acc_width(acc_width),
        .block_size(block_size),
        .num_blocks(num_blocks),
        .data_width(data_width),
        .row_idx_width(row_idx_width)
    ) core (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start_iter(i_start_iter),
        .i_commit_iter(i_commit_iter),
        .i_load_state_clusters({num_clusters{1'b0}}),
        .i_load_state_bank_sel(1'b0),
        .i_load_state_row_idx({row_idx_width{1'b0}}),
        .i_load_state_p({data_width{1'b0}}),
        .i_load_state_n({data_width{1'b0}}),
        .i_use_replay_clusters(i_use_replay_clusters),
        .i_replay_digit_idx(i_replay_digit_idx),
        .i_src_row_idx_clusters(w_src_row_idx_clusters),
        .i_ena_rows_clusters(w_ena_rows_clusters),
        .i_x0_p_rows_clusters(i_x0_p_rows_clusters),
        .i_x0_n_rows_clusters(i_x0_n_rows_clusters),
        .i_x1_p_rows_clusters(i_x1_p_rows_clusters),
        .i_x1_n_rows_clusters(i_x1_n_rows_clusters),
        .i_x2_p_rows_clusters(i_x2_p_rows_clusters),
        .i_x2_n_rows_clusters(i_x2_n_rows_clusters),
        .i_x3_p_rows_clusters(i_x3_p_rows_clusters),
        .i_x3_n_rows_clusters(i_x3_n_rows_clusters),
        .i_coeff0_vec_p_rows_clusters(w_coeff0_vec_p_rows_clusters),
        .i_coeff0_vec_n_rows_clusters(w_coeff0_vec_n_rows_clusters),
        .i_coeff1_vec_p_rows_clusters(w_coeff1_vec_p_rows_clusters),
        .i_coeff1_vec_n_rows_clusters(w_coeff1_vec_n_rows_clusters),
        .i_coeff2_vec_p_rows_clusters(w_coeff2_vec_p_rows_clusters),
        .i_coeff2_vec_n_rows_clusters(w_coeff2_vec_n_rows_clusters),
        .i_coeff3_vec_p_rows_clusters(w_coeff3_vec_p_rows_clusters),
        .i_coeff3_vec_n_rows_clusters(w_coeff3_vec_n_rows_clusters),
        .i_bias_vec_p_rows_clusters(w_bias_vec_p_rows_clusters),
        .i_bias_vec_n_rows_clusters(w_bias_vec_n_rows_clusters),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_block_weights_clusters(i_block_weights_clusters),
        .i_eta_clusters(i_eta_clusters),
        .o_read_bank_sel_clusters(o_read_bank_sel_clusters),
        .o_drv_x0_p_rows_clusters(o_drv_x0_p_rows_clusters),
        .o_drv_x0_n_rows_clusters(o_drv_x0_n_rows_clusters),
        .o_drv_x1_p_rows_clusters(o_drv_x1_p_rows_clusters),
        .o_drv_x1_n_rows_clusters(o_drv_x1_n_rows_clusters),
        .o_drv_x2_p_rows_clusters(o_drv_x2_p_rows_clusters),
        .o_drv_x2_n_rows_clusters(o_drv_x2_n_rows_clusters),
        .o_drv_x3_p_rows_clusters(o_drv_x3_p_rows_clusters),
        .o_drv_x3_n_rows_clusters(o_drv_x3_n_rows_clusters),
        .o_cluster_valid(o_cluster_valid),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error),
        .o_x_old_p_rows_clusters(o_x_old_p_rows_clusters),
        .o_x_old_n_rows_clusters(o_x_old_n_rows_clusters),
        .o_iter_done(o_iter_done),
        .o_iter_converged(o_iter_converged),
        .o_iter_continue(o_iter_continue),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask(o_cert_mask)
    );

    assign o_sched_row_active_clusters = w_sched_row_active_clusters;

endmodule
