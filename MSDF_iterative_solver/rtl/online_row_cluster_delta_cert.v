`timescale 1ns / 1ps

// Cluster-level specialized datapath:
//
//   const-coeff row-update slice x NUM_ROWS
//       -> row-local delta/L_inf bounds
//       -> block-H cluster certification
//
// This module is still functional-first. It establishes the cluster-level
// boundary that the future iteration controller will consume.

module online_row_cluster_delta_cert #(
    parameter integer num_rows = 4,
    parameter integer bit_width = 8,
    parameter integer bound_width = bit_width + 5,
    parameter integer coeff_width = 16,
    parameter integer acc_width = 40,
    parameter integer block_size = 2,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size,
    parameter integer cert_product_pipeline = 0,
    parameter integer cert_operand_pipeline = 0,
    parameter integer cert_compare_pipeline = 0
) (
    input                                       i_clk,
    input                                       i_rst,
    input      [num_rows - 1 : 0]               i_ena_rows,
    input      [num_rows - 1 : 0]               i_x0_p_rows,
    input      [num_rows - 1 : 0]               i_x0_n_rows,
    input      [num_rows - 1 : 0]               i_x1_p_rows,
    input      [num_rows - 1 : 0]               i_x1_n_rows,
    input      [num_rows - 1 : 0]               i_x2_p_rows,
    input      [num_rows - 1 : 0]               i_x2_n_rows,
    input      [num_rows - 1 : 0]               i_x3_p_rows,
    input      [num_rows - 1 : 0]               i_x3_n_rows,
    input      [num_rows * bit_width - 1 : 0]   i_coeff0_vec_p_rows,
    input      [num_rows * bit_width - 1 : 0]   i_coeff0_vec_n_rows,
    input      [num_rows * bit_width - 1 : 0]   i_coeff1_vec_p_rows,
    input      [num_rows * bit_width - 1 : 0]   i_coeff1_vec_n_rows,
    input      [num_rows * bit_width - 1 : 0]   i_coeff2_vec_p_rows,
    input      [num_rows * bit_width - 1 : 0]   i_coeff2_vec_n_rows,
    input      [num_rows * bit_width - 1 : 0]   i_coeff3_vec_p_rows,
    input      [num_rows * bit_width - 1 : 0]   i_coeff3_vec_n_rows,
    input      [num_rows * (bit_width + 2) - 1 : 0] i_bias_vec_p_rows,
    input      [num_rows * (bit_width + 2) - 1 : 0] i_bias_vec_n_rows,
    input      [num_rows * (bit_width + 3) - 1 : 0] i_x_old_p_rows,
    input      [num_rows * (bit_width + 3) - 1 : 0] i_x_old_n_rows,
    input      [bound_width - 1 : 0]            i_tail_bound,
    input      [num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights,
    input      [acc_width - 1 : 0]              i_eta,
    output     [num_rows - 1 : 0]               o_valid_rows,
    output     [num_rows * (bit_width + 3) - 1 : 0] o_sum_p_rows,
    output     [num_rows * (bit_width + 3) - 1 : 0] o_sum_n_rows,
    output     [num_rows * bound_width - 1 : 0] o_abs_upper_rows,
    output     [num_blocks * bound_width - 1 : 0] o_block_bounds,
    output                                      o_cluster_valid,
    output                                      o_cluster_certified,
    output     [acc_width - 1 : 0]              o_cluster_max_error
);

    genvar gi;
    generate
        for (gi = 0; gi < num_rows; gi = gi + 1) begin : gen_rows
            wire                            w_valid;
            wire [bit_width + 2 : 0]       w_sum_p;
            wire [bit_width + 2 : 0]       w_sum_n;
            wire signed [bit_width + 4 : 0] w_delta_word_unused;
            wire [bound_width - 1 : 0]     w_abs_prefix_unused;
            wire [bound_width - 1 : 0]     w_abs_upper;
            wire [bound_width - 1 : 0]     w_abs_lower_unused;
            wire                           w_cert_conv_unused;
            wire                           w_cert_not_unused;
            wire [1 : 0]                   w_cert_state_unused;

            online_row_update_delta_slice #(
                .bit_width(bit_width),
                .bound_width(bound_width)
            ) row_slice (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_ena(i_ena_rows[gi]),
                .i_x0_p(i_x0_p_rows[gi]),
                .i_x0_n(i_x0_n_rows[gi]),
                .i_x1_p(i_x1_p_rows[gi]),
                .i_x1_n(i_x1_n_rows[gi]),
                .i_x2_p(i_x2_p_rows[gi]),
                .i_x2_n(i_x2_n_rows[gi]),
                .i_x3_p(i_x3_p_rows[gi]),
                .i_x3_n(i_x3_n_rows[gi]),
                .i_coeff0_vec_p(i_coeff0_vec_p_rows[(gi + 1) * bit_width - 1 -: bit_width]),
                .i_coeff0_vec_n(i_coeff0_vec_n_rows[(gi + 1) * bit_width - 1 -: bit_width]),
                .i_coeff1_vec_p(i_coeff1_vec_p_rows[(gi + 1) * bit_width - 1 -: bit_width]),
                .i_coeff1_vec_n(i_coeff1_vec_n_rows[(gi + 1) * bit_width - 1 -: bit_width]),
                .i_coeff2_vec_p(i_coeff2_vec_p_rows[(gi + 1) * bit_width - 1 -: bit_width]),
                .i_coeff2_vec_n(i_coeff2_vec_n_rows[(gi + 1) * bit_width - 1 -: bit_width]),
                .i_coeff3_vec_p(i_coeff3_vec_p_rows[(gi + 1) * bit_width - 1 -: bit_width]),
                .i_coeff3_vec_n(i_coeff3_vec_n_rows[(gi + 1) * bit_width - 1 -: bit_width]),
                .i_bias_vec_p(i_bias_vec_p_rows[(gi + 1) * (bit_width + 2) - 1 -: (bit_width + 2)]),
                .i_bias_vec_n(i_bias_vec_n_rows[(gi + 1) * (bit_width + 2) - 1 -: (bit_width + 2)]),
                .i_x_old_p(i_x_old_p_rows[(gi + 1) * (bit_width + 3) - 1 -: (bit_width + 3)]),
                .i_x_old_n(i_x_old_n_rows[(gi + 1) * (bit_width + 3) - 1 -: (bit_width + 3)]),
                .i_tail_bound(i_tail_bound),
                .i_eps_d({bound_width{1'b0}}),
                .o_valid(w_valid),
                .o_sum_p(w_sum_p),
                .o_sum_n(w_sum_n),
                .o_delta_word(w_delta_word_unused),
                .o_abs_prefix(w_abs_prefix_unused),
                .o_abs_upper(w_abs_upper),
                .o_abs_lower(w_abs_lower_unused),
                .o_cert_converged(w_cert_conv_unused),
                .o_cert_not_converged(w_cert_not_unused),
                .o_cert_state(w_cert_state_unused)
            );

            assign o_valid_rows[gi] = w_valid;
            assign o_sum_p_rows[(gi + 1) * (bit_width + 3) - 1 -: (bit_width + 3)] = w_sum_p;
            assign o_sum_n_rows[(gi + 1) * (bit_width + 3) - 1 -: (bit_width + 3)] = w_sum_n;
            assign o_abs_upper_rows[(gi + 1) * bound_width - 1 -: bound_width] = w_abs_upper;
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

endmodule
