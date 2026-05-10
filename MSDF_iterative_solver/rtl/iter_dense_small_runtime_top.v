`timescale 1ns / 1ps

// Runtime-loadable dense-small solver top.
//
// This top keeps the same specialized row-update and certification datapath as
// iter_dense_small_param_bank_top, but replaces $readmemh-only template/cert
// banks with explicit configuration writes. It also exposes a state-load path
// into the ping-pong state banks, so a host-side loader can initialize x^(k).

module iter_dense_small_runtime_top #(
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
    parameter integer row_datapath_mode = 0,
    parameter integer auto_full_digit = 0,
    parameter integer auto_prefix_gating = 0,
    parameter integer mac_acc_width = 32,
    parameter integer conv_mac_pipeline = 0,
    parameter integer conv_product_shift = 0,
    parameter integer conv_round_pipeline = 0,
    parameter integer conv_baseline_degree = 8,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer src_idx_width = row_idx_width,
    parameter integer global_source_replay = 0,
    parameter integer halo_source_replay = 0,
    parameter integer halo_cluster_radius = 1,
    parameter integer halo_replay_mode = 0,
    parameter integer halo_replay_output_register = 0,
    parameter integer cert_product_pipeline = 0,
    parameter integer cert_operand_pipeline = 0,
    parameter integer cert_compare_pipeline = 0,
    // PageRank mode: cluster datapaths report local L1(delta) as max_error;
    // the iteration decision is made by summing those values across clusters.
    // Legacy Jacobi/block-H mode keeps the original all-cluster-certified rule.
    parameter integer global_l1_cert = 0,
    parameter integer solver_native_skip_digits = 4,
    parameter integer solver_native_affine_guard_shift = 7,
    parameter integer solver_native_sample_width = 5,
    parameter integer wavefront_superstep_stages = 4,
    parameter integer wavefront_inter_stage_delay_cycles = 0,
    parameter integer prior_capture_unit = 1,
    parameter integer cluster_addr_width = (num_total_clusters <= 2) ? 1 : $clog2(num_total_clusters),
    parameter integer cluster_slot_width = (num_clusters <= 2) ? 1 : $clog2(num_clusters),
    parameter integer bias_width = bit_width + 2,
    parameter integer valid_width = num_rows * degree,
    parameter integer src_width = num_rows * degree * src_idx_width,
    parameter integer coeff_terms_width = num_rows * degree * bit_width,
    parameter integer bias_vec_width = num_rows * bias_width,
    parameter integer template_payload_width = valid_width + src_width + 2 * coeff_terms_width + 2 * bias_vec_width,
    parameter integer block_weights_width = num_rows * num_blocks * coeff_width,
    parameter integer cert_payload_width = block_weights_width + acc_width,
    parameter integer runtime_mem_style = 1
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_cfg_template_we,
    input                                               i_cfg_cert_we,
    input      [cluster_addr_width - 1 : 0]             i_cfg_cluster_addr,
    input      [template_payload_width - 1 : 0]         i_cfg_template_word,
    input      [cert_payload_width - 1 : 0]             i_cfg_cert_word,
    input                                               i_load_window,
    input                                               i_cfg_state_we,
    input      [cluster_slot_width - 1 : 0]             i_cfg_state_cluster_slot,
    input                                               i_cfg_state_bank_sel,
    input      [row_idx_width - 1 : 0]                  i_cfg_state_row_idx,
    input      [data_width - 1 : 0]                     i_cfg_state_p,
    input      [data_width - 1 : 0]                     i_cfg_state_n,
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
    input                                               i_counter_clear,
    output                                              o_window_valid,
    output                                              o_window_busy,
    output reg [31 : 0]                                 o_total_cycles,
    output reg [31 : 0]                                 o_issue_cycles,
    output reg [31 : 0]                                 o_cert_wait_cycles,
    output reg [31 : 0]                                 o_iter_count,
    output reg [31 : 0]                                 o_converged_iter,
    output reg [31 : 0]                                 o_cfg_template_write_count,
    output reg [31 : 0]                                 o_cfg_cert_write_count,
    output reg [31 : 0]                                 o_cfg_state_write_count,
    output reg [31 : 0]                                 o_window_load_count,
    output reg [31 : 0]                                 o_window_busy_cycles,
    output reg [31 : 0]                                 o_window_ready_cycles,
    output reg [31 : 0]                                 o_active_digit_cycles,
    output reg [31 : 0]                                 o_gated_digit_cycles,
    output reg [31 : 0]                                 o_cert_prefix_digit_sum,
    output reg [31 : 0]                                 o_certified_block_count,
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
    wire [num_clusters * num_rows - 1 : 0] w_sched_row_active_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_ena_rows_clusters;
    wire [num_clusters * num_rows - 1 : 0] w_core_issue_rows_clusters;
    wire [$clog2(data_width) - 1 : 0] w_core_replay_digit_idx;
    wire [num_clusters * num_rows - 1 : 0] w_auto_issue_rows_clusters;
    wire [num_clusters - 1 : 0] w_auto_active_clusters;
    wire [$clog2(data_width) - 1 : 0] w_auto_replay_digit_idx;
    wire w_auto_busy;
    wire w_auto_done;
    wire [31 : 0] w_auto_active_digit_cycles;
    wire [31 : 0] w_auto_gated_digit_cycles;
    wire [31 : 0] w_auto_cert_prefix_digit_sum;
    wire [31 : 0] w_auto_certified_block_count;
    wire [num_clusters * num_rows * degree * src_idx_width - 1 : 0] w_sched_src_row_idx_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff0_vec_p_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff0_vec_n_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff1_vec_p_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff1_vec_n_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff2_vec_p_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff2_vec_n_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff3_vec_p_rows_clusters;
    wire [num_clusters * num_rows * bit_width - 1 : 0] w_coeff3_vec_n_rows_clusters;
    wire [num_clusters * num_rows * (bit_width + 2) - 1 : 0] w_sched_bias_vec_p_rows_clusters;
    wire [num_clusters * num_rows * (bit_width + 2) - 1 : 0] w_sched_bias_vec_n_rows_clusters;
    wire [num_clusters * block_weights_width - 1 : 0] w_block_weights_clusters;
    wire [num_clusters * acc_width - 1 : 0] w_eta_clusters;
    wire w_template_window_valid;
    wire w_template_window_busy;
    wire w_cert_window_valid;
    wire w_cert_window_busy;
    wire w_iter_done;
    wire w_iter_converged;
    wire w_iter_continue;
    wire [num_clusters - 1 : 0] w_prefix_cluster_valid;
    wire [num_clusters - 1 : 0] w_prefix_cluster_certified;
    reg [num_clusters - 1 : 0] r_load_state_clusters;
    reg r_cert_wait_active;

    integer li;
    wire w_window_load_accept;

    function automatic [31 : 0] count_cluster_bits;
        input [num_clusters - 1 : 0] mask;
        integer bi;
        begin
            count_cluster_bits = 32'd0;
            for (bi = 0; bi < num_clusters; bi = bi + 1) begin
                count_cluster_bits = count_cluster_bits + mask[bi];
            end
        end
    endfunction

    assign o_window_valid = w_template_window_valid & w_cert_window_valid;
    assign o_window_busy = w_template_window_busy | w_cert_window_busy;
    assign w_window_load_accept = i_load_window && !o_window_busy;
    assign w_core_issue_rows_clusters =
        (auto_full_digit != 0) ? w_auto_issue_rows_clusters : i_issue_rows_clusters;
    assign w_core_replay_digit_idx =
        (auto_full_digit != 0) ? w_auto_replay_digit_idx : i_replay_digit_idx;

    iter_digit_prefix_scheduler #(
        .num_clusters(num_clusters),
        .num_rows(num_rows),
        .data_width(data_width),
        .digit_idx_width($clog2(data_width))
    ) auto_digit_sched (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start((auto_full_digit != 0) ? i_start_iter : 1'b0),
        .i_enable_prefix_gating((auto_prefix_gating != 0) ? 1'b1 : 1'b0),
        .i_base_issue_rows(w_sched_row_active_clusters),
        .i_cluster_valid(w_prefix_cluster_valid),
        .i_cluster_certified(w_prefix_cluster_certified),
        .o_busy(w_auto_busy),
        .o_done(w_auto_done),
        .o_digit_idx(w_auto_replay_digit_idx),
        .o_issue_rows(w_auto_issue_rows_clusters),
        .o_active_clusters(w_auto_active_clusters),
        .o_active_digit_cycles(w_auto_active_digit_cycles),
        .o_gated_digit_cycles(w_auto_gated_digit_cycles),
        .o_cert_prefix_digit_sum(w_auto_cert_prefix_digit_sum),
        .o_certified_block_count(w_auto_certified_block_count)
    );

    iter_template_field_bank #(
        .num_total_clusters(num_total_clusters),
        .num_clusters(num_clusters),
        .num_rows(num_rows),
        .degree(degree),
        .bit_width(bit_width),
        .bias_width(bias_width),
        .row_idx_width(src_idx_width),
        .cluster_addr_width(cluster_addr_width),
        .valid_width(valid_width),
        .src_width(src_width),
        .coeff_terms_width(coeff_terms_width),
        .bias_vec_width(bias_vec_width),
        .payload_width(template_payload_width),
        .mem_style(runtime_mem_style)
    ) template_bank (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_cfg_we(i_cfg_template_we),
        .i_cfg_addr(i_cfg_cluster_addr),
        .i_cfg_payload(i_cfg_template_word),
        .i_window_load(i_load_window),
        .i_base_addr(i_base_cluster_idx),
        .o_window_valid(w_template_window_valid),
        .o_window_busy(w_template_window_busy),
        .o_template_words_clusters(o_template_words_clusters)
    );

    iter_fixed_degree_template_unpack #(
        .num_clusters(num_clusters),
        .num_rows(num_rows),
        .degree(degree),
        .bit_width(bit_width),
        .bias_width(bias_width),
        .row_idx_width(src_idx_width),
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

    iter_cert_param_field_bank #(
        .num_total_clusters(num_total_clusters),
        .num_clusters(num_clusters),
        .num_rows(num_rows),
        .num_blocks(num_blocks),
        .coeff_width(coeff_width),
        .acc_width(acc_width),
        .cluster_addr_width(cluster_addr_width),
        .block_weights_width(block_weights_width),
        .payload_width(cert_payload_width),
        .mem_style(runtime_mem_style)
    ) cert_param_bank (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_cfg_we(i_cfg_cert_we),
        .i_cfg_addr(i_cfg_cluster_addr),
        .i_cfg_payload(i_cfg_cert_word),
        .i_window_load(i_load_window),
        .i_base_addr(i_base_cluster_idx),
        .o_window_valid(w_cert_window_valid),
        .o_window_busy(w_cert_window_busy),
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

    genvar gi;
    generate
        for (gi = 0; gi < num_clusters; gi = gi + 1) begin : gen_sched
            iter_fixed_degree_row_scheduler #(
                .num_rows(num_rows),
                .degree(degree),
                .bit_width(bit_width),
                .bias_width(bit_width + 2),
                .row_idx_width(src_idx_width)
            ) row_sched (
                .i_term_valid_mask(w_term_valid_mask_clusters[(gi + 1) * num_rows * degree - 1 -: num_rows * degree]),
                .i_src_row_idx(w_src_row_idx_clusters[(gi + 1) * num_rows * degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                .i_coeff_p_terms(w_coeff_p_terms_clusters[(gi + 1) * num_rows * degree * bit_width - 1 -: num_rows * degree * bit_width]),
                .i_coeff_n_terms(w_coeff_n_terms_clusters[(gi + 1) * num_rows * degree * bit_width - 1 -: num_rows * degree * bit_width]),
                .i_bias_vec_p_rows(w_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                .i_bias_vec_n_rows(w_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                .o_row_active_mask(w_sched_row_active_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .o_src_row_idx(w_sched_src_row_idx_clusters[(gi + 1) * num_rows * degree * src_idx_width - 1 -: num_rows * degree * src_idx_width]),
                .o_coeff0_vec_p_rows(w_coeff0_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff0_vec_n_rows(w_coeff0_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff1_vec_p_rows(w_coeff1_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff1_vec_n_rows(w_coeff1_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff2_vec_p_rows(w_coeff2_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff2_vec_n_rows(w_coeff2_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff3_vec_p_rows(w_coeff3_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_coeff3_vec_n_rows(w_coeff3_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .o_bias_vec_p_rows(w_sched_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                .o_bias_vec_n_rows(w_sched_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)])
            );

            assign w_ena_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] =
                w_core_issue_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows] &
                w_sched_row_active_clusters[(gi + 1) * num_rows - 1 -: num_rows];
        end
    endgenerate

    always @(*) begin
        r_load_state_clusters = {num_clusters{1'b0}};
        if (i_cfg_state_we) begin
            for (li = 0; li < num_clusters; li = li + 1) begin
                if (i_cfg_state_cluster_slot == li[cluster_slot_width - 1 : 0]) begin
                    r_load_state_clusters[li] = 1'b1;
                end
            end
        end
    end

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
        .row_datapath_mode(row_datapath_mode),
        .mac_acc_width(mac_acc_width),
        .conv_mac_pipeline(conv_mac_pipeline),
        .conv_product_shift(conv_product_shift),
        .conv_round_pipeline(conv_round_pipeline),
        .conv_baseline_degree(conv_baseline_degree),
        .row_idx_width(row_idx_width),
        .src_idx_width(src_idx_width),
        .global_source_replay(global_source_replay),
        .halo_source_replay(halo_source_replay),
        .halo_cluster_radius(halo_cluster_radius),
        .halo_replay_mode(halo_replay_mode),
        .halo_replay_output_register(halo_replay_output_register),
        .enable_prefix_cert(auto_prefix_gating),
        .cert_product_pipeline(cert_product_pipeline),
        .cert_operand_pipeline(cert_operand_pipeline),
        .cert_compare_pipeline(cert_compare_pipeline),
        .global_l1_cert(global_l1_cert),
        .solver_native_skip_digits(solver_native_skip_digits),
        .solver_native_affine_guard_shift(solver_native_affine_guard_shift),
        .solver_native_sample_width(solver_native_sample_width),
        .wavefront_superstep_stages(wavefront_superstep_stages),
        .wavefront_inter_stage_delay_cycles(wavefront_inter_stage_delay_cycles),
        .prior_capture_unit(prior_capture_unit)
    ) core (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start_iter(i_start_iter),
        .i_commit_iter(i_commit_iter),
        .i_load_state_clusters(r_load_state_clusters),
        .i_load_state_bank_sel(i_cfg_state_bank_sel),
        .i_load_state_row_idx(i_cfg_state_row_idx),
        .i_load_state_p(i_cfg_state_p),
        .i_load_state_n(i_cfg_state_n),
        .i_use_replay_clusters(i_use_replay_clusters),
        .i_replay_digit_idx(w_core_replay_digit_idx),
        .i_src_row_idx_clusters(w_sched_src_row_idx_clusters),
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
        .i_bias_vec_p_rows_clusters(w_sched_bias_vec_p_rows_clusters),
        .i_bias_vec_n_rows_clusters(w_sched_bias_vec_n_rows_clusters),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_block_weights_clusters(w_block_weights_clusters),
        .i_eta_clusters(w_eta_clusters),
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
        .o_prefix_cluster_valid(w_prefix_cluster_valid),
        .o_prefix_cluster_certified(w_prefix_cluster_certified),
        .o_x_old_p_rows_clusters(o_x_old_p_rows_clusters),
        .o_x_old_n_rows_clusters(o_x_old_n_rows_clusters),
        .o_iter_done(w_iter_done),
        .o_iter_converged(w_iter_converged),
        .o_iter_continue(w_iter_continue),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask(o_cert_mask)
    );

    assign o_sched_row_active_clusters = w_sched_row_active_clusters;
    assign o_iter_done = w_iter_done;
    assign o_iter_converged = w_iter_converged;
    assign o_iter_continue = w_iter_continue;

    always @(posedge i_clk) begin
        if (i_rst || i_counter_clear) begin
            o_total_cycles <= 32'd0;
            o_issue_cycles <= 32'd0;
            o_cert_wait_cycles <= 32'd0;
            o_iter_count <= 32'd0;
            o_converged_iter <= 32'd0;
            o_cfg_template_write_count <= 32'd0;
            o_cfg_cert_write_count <= 32'd0;
            o_cfg_state_write_count <= 32'd0;
            o_window_load_count <= 32'd0;
            o_window_busy_cycles <= 32'd0;
            o_window_ready_cycles <= 32'd0;
            o_active_digit_cycles <= 32'd0;
            o_gated_digit_cycles <= 32'd0;
            o_cert_prefix_digit_sum <= 32'd0;
            o_certified_block_count <= 32'd0;
            r_cert_wait_active <= 1'b0;
        end else begin
            o_total_cycles <= o_total_cycles + 1'b1;

            if (i_cfg_template_we) begin
                o_cfg_template_write_count <= o_cfg_template_write_count + 1'b1;
            end

            if (i_cfg_cert_we) begin
                o_cfg_cert_write_count <= o_cfg_cert_write_count + 1'b1;
            end

            if (i_cfg_state_we) begin
                o_cfg_state_write_count <= o_cfg_state_write_count + 1'b1;
            end

            if (w_window_load_accept) begin
                o_window_load_count <= o_window_load_count + 1'b1;
            end

            if (o_window_busy) begin
                o_window_busy_cycles <= o_window_busy_cycles + 1'b1;
            end

            if (o_window_valid && !o_window_busy) begin
                o_window_ready_cycles <= o_window_ready_cycles + 1'b1;
            end

            if (|w_core_issue_rows_clusters) begin
                o_issue_cycles <= o_issue_cycles + 1'b1;
                o_active_digit_cycles <= o_active_digit_cycles + 1'b1;
            end

            if (i_start_iter) begin
                r_cert_wait_active <= 1'b1;
            end else if (w_iter_done) begin
                r_cert_wait_active <= 1'b0;
            end

            if (r_cert_wait_active && !w_iter_done) begin
                o_cert_wait_cycles <= o_cert_wait_cycles + 1'b1;
            end

            if (w_iter_done) begin
                o_iter_count <= o_iter_count + 1'b1;
                o_certified_block_count <= o_certified_block_count + count_cluster_bits(o_cert_mask);
                o_cert_prefix_digit_sum <=
                    o_cert_prefix_digit_sum +
                    (count_cluster_bits(o_cert_mask) *
                    ({{(32 - $clog2(data_width)){1'b0}}, w_core_replay_digit_idx} + 1'b1));
                if (w_iter_converged) begin
                    o_converged_iter <= o_iter_count + 1'b1;
                end
            end
        end
    end

endmodule
