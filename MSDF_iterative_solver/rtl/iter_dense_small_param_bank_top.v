`timescale 1ns / 1ps

// Template-bank and cert-parameter-bank integrated top.
//
// This is the first top where both fixed-degree row templates and block-H
// certification parameters come from memory-friendly packed banks.

module iter_dense_small_param_bank_top #(
    parameter integer num_total_clusters = 2,
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
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer cluster_addr_width = (num_total_clusters <= 2) ? 1 : $clog2(num_total_clusters),
    parameter integer bias_width = bit_width + 2,
    parameter integer valid_width = num_rows * degree,
    parameter integer src_width = num_rows * degree * row_idx_width,
    parameter integer coeff_terms_width = num_rows * degree * bit_width,
    parameter integer bias_vec_width = num_rows * bias_width,
    parameter integer template_payload_width = valid_width + src_width + 2 * coeff_terms_width + 2 * bias_vec_width,
    parameter integer block_weights_width = num_rows * num_blocks * coeff_width,
    parameter integer cert_payload_width = block_weights_width + acc_width,
    parameter template_mem_init = "MSDF_iterative_solver/generated/blockdiag8_fixed4_templates.memh",
    parameter cert_param_mem_init = "MSDF_iterative_solver/generated/blockdiag8_cert_params.memh"
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_start_iter,
    input                                               i_commit_iter,
    input      [cluster_addr_width - 1 : 0]             i_base_cluster_idx,
    input      [num_clusters - 1 : 0]                   i_use_replay_clusters,
    input      [$clog2(data_width) - 1 : 0]             i_replay_digit_idx,
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
    output     [num_clusters * template_payload_width - 1 : 0] o_template_words_clusters,
    output     [num_clusters * cert_payload_width - 1 : 0]     o_cert_param_words_clusters,
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

    wire [num_clusters * valid_width - 1 : 0] w_term_valid_mask_clusters;
    wire [num_clusters * src_width - 1 : 0] w_src_row_idx_clusters;
    wire [num_clusters * coeff_terms_width - 1 : 0] w_coeff_p_terms_clusters;
    wire [num_clusters * coeff_terms_width - 1 : 0] w_coeff_n_terms_clusters;
    wire [num_clusters * bias_vec_width - 1 : 0] w_bias_vec_p_rows_clusters;
    wire [num_clusters * bias_vec_width - 1 : 0] w_bias_vec_n_rows_clusters;
    wire [num_clusters * block_weights_width - 1 : 0] w_block_weights_clusters;
    wire [num_clusters * acc_width - 1 : 0] w_eta_clusters;

    iter_fixed_degree_template_bank #(
        .num_total_clusters(num_total_clusters),
        .num_clusters(num_clusters),
        .payload_width(template_payload_width),
        .cluster_addr_width(cluster_addr_width),
        .template_mem_init(template_mem_init)
    ) template_bank (
        .i_base_cluster_idx(i_base_cluster_idx),
        .o_template_words_clusters(o_template_words_clusters)
    );

    iter_fixed_degree_template_unpack #(
        .num_clusters(num_clusters),
        .num_rows(num_rows),
        .degree(degree),
        .bit_width(bit_width),
        .bias_width(bias_width),
        .row_idx_width(row_idx_width),
        .valid_width(valid_width),
        .src_width(src_width),
        .coeff_terms_width(coeff_terms_width),
        .bias_vec_width(bias_vec_width),
        .payload_width(template_payload_width)
    ) template_unpack (
        .i_template_words_clusters(o_template_words_clusters),
        .o_term_valid_mask_clusters(w_term_valid_mask_clusters),
        .o_src_row_idx_clusters(w_src_row_idx_clusters),
        .o_coeff_p_terms_clusters(w_coeff_p_terms_clusters),
        .o_coeff_n_terms_clusters(w_coeff_n_terms_clusters),
        .o_bias_vec_p_rows_clusters(w_bias_vec_p_rows_clusters),
        .o_bias_vec_n_rows_clusters(w_bias_vec_n_rows_clusters)
    );

    iter_cert_param_bank #(
        .num_total_clusters(num_total_clusters),
        .num_clusters(num_clusters),
        .payload_width(cert_payload_width),
        .cluster_addr_width(cluster_addr_width),
        .cert_param_mem_init(cert_param_mem_init)
    ) cert_param_bank (
        .i_base_cluster_idx(i_base_cluster_idx),
        .o_cert_param_words_clusters(o_cert_param_words_clusters)
    );

    iter_cert_param_unpack #(
        .num_clusters(num_clusters),
        .num_rows(num_rows),
        .num_blocks(num_blocks),
        .coeff_width(coeff_width),
        .acc_width(acc_width),
        .block_weights_width(block_weights_width),
        .payload_width(cert_payload_width)
    ) cert_param_unpack (
        .i_cert_param_words_clusters(o_cert_param_words_clusters),
        .o_block_weights_clusters(w_block_weights_clusters),
        .o_eta_clusters(w_eta_clusters)
    );

    iter_dense_small_sched_top #(
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
        .i_use_replay_clusters(i_use_replay_clusters),
        .i_replay_digit_idx(i_replay_digit_idx),
        .i_term_valid_mask_clusters(w_term_valid_mask_clusters),
        .i_src_row_idx_clusters(w_src_row_idx_clusters),
        .i_coeff_p_terms_clusters(w_coeff_p_terms_clusters),
        .i_coeff_n_terms_clusters(w_coeff_n_terms_clusters),
        .i_bias_vec_p_rows_clusters(w_bias_vec_p_rows_clusters),
        .i_bias_vec_n_rows_clusters(w_bias_vec_n_rows_clusters),
        .i_issue_rows_clusters(i_issue_rows_clusters),
        .i_x0_p_rows_clusters(i_x0_p_rows_clusters),
        .i_x0_n_rows_clusters(i_x0_n_rows_clusters),
        .i_x1_p_rows_clusters(i_x1_p_rows_clusters),
        .i_x1_n_rows_clusters(i_x1_n_rows_clusters),
        .i_x2_p_rows_clusters(i_x2_p_rows_clusters),
        .i_x2_n_rows_clusters(i_x2_n_rows_clusters),
        .i_x3_p_rows_clusters(i_x3_p_rows_clusters),
        .i_x3_n_rows_clusters(i_x3_n_rows_clusters),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_block_weights_clusters(w_block_weights_clusters),
        .i_eta_clusters(w_eta_clusters),
        .o_sched_row_active_clusters(o_sched_row_active_clusters),
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

endmodule
