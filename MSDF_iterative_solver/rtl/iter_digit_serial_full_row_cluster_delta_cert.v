`timescale 1ns / 1ps

// Cluster wrapper for the full-digit digit-serial row-update bridge.
//
// All rows in the cluster consume the same digit schedule.  After the final
// digit, row full-word sums and delta bounds feed the existing block-H
// certification engine.  This module is the controller-ready boundary for the
// future automatic full-digit runtime mode.

module iter_digit_serial_full_row_cluster_delta_cert #(
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer bound_width = bit_width + 5,
    parameter integer coeff_width = 8,
    parameter integer acc_width = 24,
    parameter integer mac_acc_width = 32,
    parameter integer block_size = 2,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size,
    parameter integer cert_product_pipeline = 0,
    parameter integer cert_operand_pipeline = 0,
    parameter integer cert_compare_pipeline = 0,
    parameter integer enable_prefix_cert = 0,
    parameter integer product_shift = 0,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_start,
    input                                                   i_valid_digit,
    input                                                   i_last_digit,
    input      [digit_idx_width - 1 : 0]                    i_digit_idx,
    input      [num_rows * degree - 1 : 0]                  i_state_digit_p_terms_rows,
    input      [num_rows * degree - 1 : 0]                  i_state_digit_n_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_n_rows,
    input      [num_rows * data_width - 1 : 0]              i_old_state_p_rows,
    input      [num_rows * data_width - 1 : 0]              i_old_state_n_rows,
    input      [bound_width - 1 : 0]                        i_tail_bound,
    input      [num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights,
    input      [acc_width - 1 : 0]                          i_eta,
    output     [num_rows - 1 : 0]                           o_valid_rows,
    output     [num_rows * mac_acc_width - 1 : 0]           o_sum_rows,
    output     [num_rows * data_width - 1 : 0]              o_sum_p_rows,
    output     [num_rows * data_width - 1 : 0]              o_sum_n_rows,
    output     [num_rows * bound_width - 1 : 0]             o_abs_upper_rows,
    output     [num_rows * bound_width - 1 : 0]             o_prefix_abs_upper_rows,
    output     [num_blocks * bound_width - 1 : 0]           o_block_bounds,
    output                                                  o_cluster_valid,
    output                                                  o_cluster_certified,
    output     [acc_width - 1 : 0]                          o_cluster_max_error,
    output                                                  o_prefix_cluster_valid,
    output                                                  o_prefix_cluster_certified,
    output     [acc_width - 1 : 0]                          o_prefix_cluster_max_error
);

    genvar gi;
    wire [num_rows - 1 : 0] w_prefix_valid_rows;
    generate
        for (gi = 0; gi < num_rows; gi = gi + 1) begin : gen_rows
            iter_digit_serial_full_row_update_delta_slice #(
                .degree(degree),
                .bit_width(bit_width),
                .data_width(data_width),
                .bias_width(bias_width),
                .bound_width(bound_width),
                .acc_width(mac_acc_width),
                .enable_prefix_bound(enable_prefix_cert),
                .product_shift(product_shift),
                .digit_idx_width(digit_idx_width)
            ) row_slice (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_start(i_start),
                .i_valid_digit(i_valid_digit),
                .i_last_digit(i_last_digit),
                .i_digit_idx(i_digit_idx),
                .i_state_digit_p_terms(i_state_digit_p_terms_rows[(gi + 1) * degree - 1 -: degree]),
                .i_state_digit_n_terms(i_state_digit_n_terms_rows[(gi + 1) * degree - 1 -: degree]),
                .i_coeff_p_terms(i_coeff_p_terms_rows[(gi + 1) * degree * bit_width - 1 -: degree * bit_width]),
                .i_coeff_n_terms(i_coeff_n_terms_rows[(gi + 1) * degree * bit_width - 1 -: degree * bit_width]),
                .i_bias_p(i_bias_p_rows[(gi + 1) * bias_width - 1 -: bias_width]),
                .i_bias_n(i_bias_n_rows[(gi + 1) * bias_width - 1 -: bias_width]),
                .i_old_state_p(i_old_state_p_rows[(gi + 1) * data_width - 1 -: data_width]),
                .i_old_state_n(i_old_state_n_rows[(gi + 1) * data_width - 1 -: data_width]),
                .i_tail_bound(i_tail_bound),
                .o_busy(),
                .o_valid(o_valid_rows[gi]),
                .o_sum(o_sum_rows[(gi + 1) * mac_acc_width - 1 -: mac_acc_width]),
                .o_sum_p(o_sum_p_rows[(gi + 1) * data_width - 1 -: data_width]),
                .o_sum_n(o_sum_n_rows[(gi + 1) * data_width - 1 -: data_width]),
                .o_abs_upper(o_abs_upper_rows[(gi + 1) * bound_width - 1 -: bound_width]),
                .o_prefix_valid(w_prefix_valid_rows[gi]),
                .o_prefix_abs_upper(o_prefix_abs_upper_rows[(gi + 1) * bound_width - 1 -: bound_width])
            );
        end
    endgenerate

    online_row_cluster_block_cert #(
        .num_rows(num_rows),
        .block_size(block_size),
        .bound_width(bound_width),
        .coeff_width(coeff_width),
        .acc_width(acc_width),
        .num_blocks(num_blocks),
        .cert_product_pipeline(cert_product_pipeline),
        .cert_operand_pipeline(cert_operand_pipeline),
        .cert_compare_pipeline(cert_compare_pipeline)
    ) cluster_cert (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_valid_rows(o_valid_rows),
        .i_row_abs_upper(o_abs_upper_rows),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid(o_cluster_valid),
        .o_block_bounds(o_block_bounds),
        .o_certified(o_cluster_certified),
        .o_max_error(o_cluster_max_error)
    );

    generate
        if (enable_prefix_cert != 0) begin : gen_prefix_cert
            online_row_cluster_block_cert #(
                .num_rows(num_rows),
                .block_size(block_size),
                .bound_width(bound_width),
                .coeff_width(coeff_width),
                .acc_width(acc_width),
                .num_blocks(num_blocks),
                .cert_product_pipeline(cert_product_pipeline),
                .cert_operand_pipeline(cert_operand_pipeline),
                .cert_compare_pipeline(cert_compare_pipeline)
            ) prefix_cert (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_valid_rows(w_prefix_valid_rows),
                .i_row_abs_upper(o_prefix_abs_upper_rows),
                .i_block_weights(i_block_weights),
                .i_eta(i_eta),
                .o_valid(o_prefix_cluster_valid),
                .o_block_bounds(),
                .o_certified(o_prefix_cluster_certified),
                .o_max_error(o_prefix_cluster_max_error)
            );
        end else begin : gen_no_prefix_cert
            assign o_prefix_cluster_valid = 1'b0;
            assign o_prefix_cluster_certified = 1'b0;
            assign o_prefix_cluster_max_error = {acc_width{1'b0}};
        end
    endgenerate

endmodule
