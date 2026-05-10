`timescale 1ns / 1ps

// Conventional DSP-MAC row cluster plus the same block-H certification engine
// used by the online solver path. This module is a datapath baseline: it does
// not include runtime template/state banks.

module conv_row_cluster_delta_cert #(
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
    parameter integer mac_pipeline = 0,
    parameter integer product_shift = 0,
    parameter integer round_pipeline = 0,
    parameter integer cert_operand_pipeline = 0
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_valid,
    input      [num_rows * degree * data_width - 1 : 0]     i_state_p_terms_rows,
    input      [num_rows * degree * data_width - 1 : 0]     i_state_n_terms_rows,
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
    output                                                  o_cluster_valid,
    output                                                  o_cluster_certified,
    output     [acc_width - 1 : 0]                          o_cluster_max_error
);

    genvar gi;
    generate
        for (gi = 0; gi < num_rows; gi = gi + 1) begin : gen_rows
            wire w_valid;
            wire signed [mac_acc_width - 1 : 0] w_sum;
            wire [data_width - 1 : 0] w_sum_p;
            wire [data_width - 1 : 0] w_sum_n;
            wire [bound_width - 1 : 0] w_abs_upper;

            if (mac_pipeline == 0) begin : gen_unpiped_row
                conv_signed_row_update_delta_slice #(
                    .degree(degree),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .bias_width(bias_width),
                    .bound_width(bound_width),
                    .acc_width(mac_acc_width),
                    .product_shift(product_shift)
                ) row_slice (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_valid(i_valid),
                    .i_state_p_terms(i_state_p_terms_rows[(gi + 1) * degree * data_width - 1 -: degree * data_width]),
                    .i_state_n_terms(i_state_n_terms_rows[(gi + 1) * degree * data_width - 1 -: degree * data_width]),
                    .i_coeff_p_terms(i_coeff_p_terms_rows[(gi + 1) * degree * bit_width - 1 -: degree * bit_width]),
                    .i_coeff_n_terms(i_coeff_n_terms_rows[(gi + 1) * degree * bit_width - 1 -: degree * bit_width]),
                    .i_bias_p(i_bias_p_rows[(gi + 1) * bias_width - 1 -: bias_width]),
                    .i_bias_n(i_bias_n_rows[(gi + 1) * bias_width - 1 -: bias_width]),
                    .i_old_state_p(i_old_state_p_rows[(gi + 1) * data_width - 1 -: data_width]),
                    .i_old_state_n(i_old_state_n_rows[(gi + 1) * data_width - 1 -: data_width]),
                    .i_tail_bound(i_tail_bound),
                    .o_valid(w_valid),
                    .o_sum(w_sum),
                    .o_sum_p(w_sum_p),
                    .o_sum_n(w_sum_n),
                    .o_abs_upper(w_abs_upper)
                );
            end else begin : gen_piped_row
                conv_signed_row_update_delta_slice_pipe #(
                    .degree(degree),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .bias_width(bias_width),
                    .bound_width(bound_width),
                    .acc_width(mac_acc_width),
                    .product_shift(product_shift),
                    .round_pipeline(round_pipeline)
                ) row_slice (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_valid(i_valid),
                    .i_state_p_terms(i_state_p_terms_rows[(gi + 1) * degree * data_width - 1 -: degree * data_width]),
                    .i_state_n_terms(i_state_n_terms_rows[(gi + 1) * degree * data_width - 1 -: degree * data_width]),
                    .i_coeff_p_terms(i_coeff_p_terms_rows[(gi + 1) * degree * bit_width - 1 -: degree * bit_width]),
                    .i_coeff_n_terms(i_coeff_n_terms_rows[(gi + 1) * degree * bit_width - 1 -: degree * bit_width]),
                    .i_bias_p(i_bias_p_rows[(gi + 1) * bias_width - 1 -: bias_width]),
                    .i_bias_n(i_bias_n_rows[(gi + 1) * bias_width - 1 -: bias_width]),
                    .i_old_state_p(i_old_state_p_rows[(gi + 1) * data_width - 1 -: data_width]),
                    .i_old_state_n(i_old_state_n_rows[(gi + 1) * data_width - 1 -: data_width]),
                    .i_tail_bound(i_tail_bound),
                    .o_valid(w_valid),
                    .o_sum(w_sum),
                    .o_sum_p(w_sum_p),
                    .o_sum_n(w_sum_n),
                    .o_abs_upper(w_abs_upper)
                );
            end

            assign o_valid_rows[gi] = w_valid;
            assign o_sum_rows[(gi + 1) * mac_acc_width - 1 -: mac_acc_width] = w_sum;
            assign o_sum_p_rows[(gi + 1) * data_width - 1 -: data_width] = w_sum_p;
            assign o_sum_n_rows[(gi + 1) * data_width - 1 -: data_width] = w_sum_n;
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
        .cert_product_pipeline(0),
        .cert_operand_pipeline(cert_operand_pipeline),
        .cert_compare_pipeline(0)
    ) cluster_cert (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_valid_rows(o_valid_rows),
        .i_row_abs_upper(o_abs_upper_rows),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid(o_cluster_valid),
        .o_block_bounds(),
        .o_certified(o_cluster_certified),
        .o_max_error(o_cluster_max_error)
    );

endmodule
