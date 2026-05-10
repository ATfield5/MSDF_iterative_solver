`timescale 1ns / 1ps

// Binary-I/O wrapper for the runtime-loadable online solver.
//
// External contract:
// - state, coefficients, and bias are signed two's-complement binary values;
// - certification parameters remain unsigned packed binary values;
// - the internal runtime core keeps the existing differential rail datapath.

module iter_dense_small_runtime_binary_io_top #(
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
    parameter integer state_bin_width = data_width + 1,
    parameter integer coeff_bin_width = bit_width + 1,
    parameter integer bias_width = bit_width + 2,
    parameter integer bias_bin_width = bias_width + 1,
    parameter integer row_datapath_mode = 0,
    parameter integer mac_acc_width = 32,
    parameter integer conv_mac_pipeline = 0,
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
    parameter integer cluster_addr_width = (num_total_clusters <= 2) ? 1 : $clog2(num_total_clusters),
    parameter integer cluster_slot_width = (num_clusters <= 2) ? 1 : $clog2(num_clusters),
    parameter integer valid_width = num_rows * degree,
    parameter integer src_width = num_rows * degree * src_idx_width,
    parameter integer coeff_terms_width = num_rows * degree * bit_width,
    parameter integer coeff_bin_terms_width = num_rows * degree * coeff_bin_width,
    parameter integer bias_vec_width = num_rows * bias_width,
    parameter integer bias_bin_vec_width = num_rows * bias_bin_width,
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
    input      [valid_width - 1 : 0]                    i_cfg_valid_mask,
    input      [src_width - 1 : 0]                      i_cfg_src_row_idx,
    input      [coeff_bin_terms_width - 1 : 0]          i_cfg_coeff_terms_bin,
    input      [bias_bin_vec_width - 1 : 0]             i_cfg_bias_rows_bin,
    input      [cert_payload_width - 1 : 0]             i_cfg_cert_word,
    input                                               i_load_window,
    input                                               i_cfg_state_we,
    input      [cluster_slot_width - 1 : 0]             i_cfg_state_cluster_slot,
    input                                               i_cfg_state_bank_sel,
    input      [row_idx_width - 1 : 0]                  i_cfg_state_row_idx,
    input signed [state_bin_width - 1 : 0]              i_cfg_state_bin,
    input                                               i_start_iter,
    input                                               i_commit_iter,
    input      [cluster_addr_width - 1 : 0]             i_base_cluster_idx,
    input      [num_clusters - 1 : 0]                   i_use_replay_clusters,
    input      [$clog2(data_width) - 1 : 0]             i_replay_digit_idx,
    input      [num_clusters * num_rows - 1 : 0]        i_issue_rows_clusters,
    input      [num_clusters * bound_width - 1 : 0]     i_tail_bound_clusters,
    input                                               i_counter_clear,
    output                                              o_window_valid,
    output                                              o_window_busy,
    output     [31 : 0]                                 o_total_cycles,
    output     [31 : 0]                                 o_issue_cycles,
    output     [31 : 0]                                 o_cert_wait_cycles,
    output     [31 : 0]                                 o_iter_count,
    output     [31 : 0]                                 o_converged_iter,
    output     [31 : 0]                                 o_cfg_template_write_count,
    output     [31 : 0]                                 o_cfg_cert_write_count,
    output     [31 : 0]                                 o_cfg_state_write_count,
    output     [31 : 0]                                 o_window_load_count,
    output     [31 : 0]                                 o_window_busy_cycles,
    output     [31 : 0]                                 o_window_ready_cycles,
    output     [num_clusters * num_rows * state_bin_width - 1 : 0] o_x_old_bin_rows_clusters,
    output     [num_clusters - 1 : 0]                   o_cluster_valid,
    output     [num_clusters - 1 : 0]                   o_cluster_certified,
    output     [num_clusters * acc_width - 1 : 0]       o_cluster_max_error,
    output                                              o_iter_done,
    output                                              o_iter_converged,
    output                                              o_iter_continue,
    output     [num_clusters - 1 : 0]                   o_seen_mask,
    output     [num_clusters - 1 : 0]                   o_cert_mask
);

    localparam integer off_valid = 0;
    localparam integer off_src = off_valid + valid_width;
    localparam integer off_coeff_p = off_src + src_width;
    localparam integer off_coeff_n = off_coeff_p + coeff_terms_width;
    localparam integer off_bias_p = off_coeff_n + coeff_terms_width;
    localparam integer off_bias_n = off_bias_p + bias_vec_width;

    wire [template_payload_width - 1 : 0] w_cfg_template_word;
    wire [coeff_terms_width - 1 : 0] w_cfg_coeff_p_terms;
    wire [coeff_terms_width - 1 : 0] w_cfg_coeff_n_terms;
    wire [bias_vec_width - 1 : 0] w_cfg_bias_p_rows;
    wire [bias_vec_width - 1 : 0] w_cfg_bias_n_rows;
    wire [data_width - 1 : 0] w_cfg_state_p;
    wire [data_width - 1 : 0] w_cfg_state_n;
    wire [num_clusters * num_rows * data_width - 1 : 0] w_x_old_p_rows_clusters;
    wire [num_clusters * num_rows * data_width - 1 : 0] w_x_old_n_rows_clusters;

    assign w_cfg_template_word[off_valid +: valid_width] = i_cfg_valid_mask;
    assign w_cfg_template_word[off_src +: src_width] = i_cfg_src_row_idx;
    assign w_cfg_template_word[off_coeff_p +: coeff_terms_width] = w_cfg_coeff_p_terms;
    assign w_cfg_template_word[off_coeff_n +: coeff_terms_width] = w_cfg_coeff_n_terms;
    assign w_cfg_template_word[off_bias_p +: bias_vec_width] = w_cfg_bias_p_rows;
    assign w_cfg_template_word[off_bias_n +: bias_vec_width] = w_cfg_bias_n_rows;

    iter_signed_to_rail #(
        .in_width(state_bin_width),
        .rail_width(data_width)
    ) state_in_codec (
        .i_value(i_cfg_state_bin),
        .o_value_p(w_cfg_state_p),
        .o_value_n(w_cfg_state_n)
    );

    genvar ci;
    genvar ri;
    genvar ti;
    generate
        for (ti = 0; ti < num_rows * degree; ti = ti + 1) begin : gen_coeff_codec
            iter_signed_to_rail #(
                .in_width(coeff_bin_width),
                .rail_width(bit_width)
            ) coeff_codec (
                .i_value(i_cfg_coeff_terms_bin[(ti + 1) * coeff_bin_width - 1 -: coeff_bin_width]),
                .o_value_p(w_cfg_coeff_p_terms[(ti + 1) * bit_width - 1 -: bit_width]),
                .o_value_n(w_cfg_coeff_n_terms[(ti + 1) * bit_width - 1 -: bit_width])
            );
        end

        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_bias_codec
            iter_signed_to_rail #(
                .in_width(bias_bin_width),
                .rail_width(bias_width)
            ) bias_codec (
                .i_value(i_cfg_bias_rows_bin[(ri + 1) * bias_bin_width - 1 -: bias_bin_width]),
                .o_value_p(w_cfg_bias_p_rows[(ri + 1) * bias_width - 1 -: bias_width]),
                .o_value_n(w_cfg_bias_n_rows[(ri + 1) * bias_width - 1 -: bias_width])
            );
        end

        for (ci = 0; ci < num_clusters; ci = ci + 1) begin : gen_out_clusters
            for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_out_rows
                localparam integer flat_row = ci * num_rows + ri;
                iter_rail_to_signed #(
                    .rail_width(data_width),
                    .out_width(state_bin_width)
                ) state_out_codec (
                    .i_value_p(w_x_old_p_rows_clusters[(flat_row + 1) * data_width - 1 -: data_width]),
                    .i_value_n(w_x_old_n_rows_clusters[(flat_row + 1) * data_width - 1 -: data_width]),
                    .o_value(o_x_old_bin_rows_clusters[(flat_row + 1) * state_bin_width - 1 -: state_bin_width])
                );
            end
        end
    endgenerate

    iter_dense_small_runtime_top #(
        .num_total_clusters(num_total_clusters),
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
        .row_idx_width(row_idx_width),
        .src_idx_width(src_idx_width),
        .global_source_replay(global_source_replay),
        .halo_source_replay(halo_source_replay),
        .halo_cluster_radius(halo_cluster_radius),
        .halo_replay_mode(halo_replay_mode),
        .halo_replay_output_register(halo_replay_output_register),
        .cert_product_pipeline(cert_product_pipeline),
        .cert_operand_pipeline(cert_operand_pipeline),
        .cert_compare_pipeline(cert_compare_pipeline),
        .cluster_addr_width(cluster_addr_width),
        .cluster_slot_width(cluster_slot_width),
        .bias_width(bias_width),
        .valid_width(valid_width),
        .src_width(src_width),
        .coeff_terms_width(coeff_terms_width),
        .bias_vec_width(bias_vec_width),
        .template_payload_width(template_payload_width),
        .block_weights_width(block_weights_width),
        .cert_payload_width(cert_payload_width),
        .runtime_mem_style(runtime_mem_style)
    ) core (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_cfg_template_we(i_cfg_template_we),
        .i_cfg_cert_we(i_cfg_cert_we),
        .i_cfg_cluster_addr(i_cfg_cluster_addr),
        .i_cfg_template_word(w_cfg_template_word),
        .i_cfg_cert_word(i_cfg_cert_word),
        .i_load_window(i_load_window),
        .i_cfg_state_we(i_cfg_state_we),
        .i_cfg_state_cluster_slot(i_cfg_state_cluster_slot),
        .i_cfg_state_bank_sel(i_cfg_state_bank_sel),
        .i_cfg_state_row_idx(i_cfg_state_row_idx),
        .i_cfg_state_p(w_cfg_state_p),
        .i_cfg_state_n(w_cfg_state_n),
        .i_start_iter(i_start_iter),
        .i_commit_iter(i_commit_iter),
        .i_base_cluster_idx(i_base_cluster_idx),
        .i_use_replay_clusters(i_use_replay_clusters),
        .i_replay_digit_idx(i_replay_digit_idx),
        .i_issue_rows_clusters(i_issue_rows_clusters),
        .i_x0_p_rows_clusters({num_clusters * num_rows{1'b0}}),
        .i_x0_n_rows_clusters({num_clusters * num_rows{1'b0}}),
        .i_x1_p_rows_clusters({num_clusters * num_rows{1'b0}}),
        .i_x1_n_rows_clusters({num_clusters * num_rows{1'b0}}),
        .i_x2_p_rows_clusters({num_clusters * num_rows{1'b0}}),
        .i_x2_n_rows_clusters({num_clusters * num_rows{1'b0}}),
        .i_x3_p_rows_clusters({num_clusters * num_rows{1'b0}}),
        .i_x3_n_rows_clusters({num_clusters * num_rows{1'b0}}),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_counter_clear(i_counter_clear),
        .o_window_valid(o_window_valid),
        .o_window_busy(o_window_busy),
        .o_total_cycles(o_total_cycles),
        .o_issue_cycles(o_issue_cycles),
        .o_cert_wait_cycles(o_cert_wait_cycles),
        .o_iter_count(o_iter_count),
        .o_converged_iter(o_converged_iter),
        .o_cfg_template_write_count(o_cfg_template_write_count),
        .o_cfg_cert_write_count(o_cfg_cert_write_count),
        .o_cfg_state_write_count(o_cfg_state_write_count),
        .o_window_load_count(o_window_load_count),
        .o_window_busy_cycles(o_window_busy_cycles),
        .o_window_ready_cycles(o_window_ready_cycles),
        .o_template_words_clusters(),
        .o_cert_param_words_clusters(),
        .o_sched_row_active_clusters(),
        .o_read_bank_sel_clusters(),
        .o_drv_x0_p_rows_clusters(),
        .o_drv_x0_n_rows_clusters(),
        .o_drv_x1_p_rows_clusters(),
        .o_drv_x1_n_rows_clusters(),
        .o_drv_x2_p_rows_clusters(),
        .o_drv_x2_n_rows_clusters(),
        .o_drv_x3_p_rows_clusters(),
        .o_drv_x3_n_rows_clusters(),
        .o_cluster_valid(o_cluster_valid),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error),
        .o_x_old_p_rows_clusters(w_x_old_p_rows_clusters),
        .o_x_old_n_rows_clusters(w_x_old_n_rows_clusters),
        .o_iter_done(o_iter_done),
        .o_iter_converged(o_iter_converged),
        .o_iter_continue(o_iter_continue),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask(o_cert_mask)
    );

endmodule
