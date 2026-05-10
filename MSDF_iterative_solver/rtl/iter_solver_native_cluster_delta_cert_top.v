`timescale 1ns / 1ps

// Solver-native digit-stream cluster with inline delta/certification.
//
// This module extends iter_solver_native_cluster_digit_stream_top with the
// certification path needed by the runtime solver.  Delta is computed from the
// same fixed-width digit stream that writes the next state, so certification no
// longer waits for a reconstructed full-word row update.

module iter_solver_native_cluster_delta_cert_top #(
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer bound_width = bit_width + 5,
    parameter integer coeff_width = 16,
    parameter integer acc_width = 40,
    parameter integer block_size = 2,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size,
    parameter integer skip_digits = 8,
    parameter integer affine_guard_shift = 3,
    parameter integer sample_width = 5,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer cert_product_pipeline = 0,
    parameter integer cert_operand_pipeline = 0,
    parameter integer cert_compare_pipeline = 0
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_start,
    input                                                   i_valid_digit,
    input      [num_rows - 1 : 0]                           i_ena_rows,
    input      [digit_idx_width - 1 : 0]                    i_digit_idx,
    input                                                   i_use_replay,
    input                                                   i_clear_write_bank,
    input                                                   i_commit_swap,

    input                                                   i_load_state,
    input                                                   i_load_bank_sel,
    input      [row_idx_width - 1 : 0]                      i_load_row_idx,
    input      [data_width - 1 : 0]                         i_load_state_p,
    input      [data_width - 1 : 0]                         i_load_state_n,

    input      [num_rows * degree * row_idx_width - 1 : 0]  i_src_row_idx,
    input      [num_rows - 1 : 0]                           i_ext_x0_p_rows,
    input      [num_rows - 1 : 0]                           i_ext_x0_n_rows,
    input      [num_rows - 1 : 0]                           i_ext_x1_p_rows,
    input      [num_rows - 1 : 0]                           i_ext_x1_n_rows,
    input      [num_rows - 1 : 0]                           i_ext_x2_p_rows,
    input      [num_rows - 1 : 0]                           i_ext_x2_n_rows,
    input      [num_rows - 1 : 0]                           i_ext_x3_p_rows,
    input      [num_rows - 1 : 0]                           i_ext_x3_n_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_n_rows,
    input      [num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights,
    input      [acc_width - 1 : 0]                          i_eta,
    input      [bound_width - 1 : 0]                        i_tail_bound,

    output     [num_rows - 1 : 0]                           o_replay_x0_p_rows,
    output     [num_rows - 1 : 0]                           o_replay_x0_n_rows,
    output     [num_rows - 1 : 0]                           o_replay_x1_p_rows,
    output     [num_rows - 1 : 0]                           o_replay_x1_n_rows,
    output     [num_rows - 1 : 0]                           o_write_done_rows,
    output     [num_rows * bound_width - 1 : 0]             o_abs_upper_rows,
    output     [num_blocks * bound_width - 1 : 0]           o_block_bounds,
    output                                                  o_cluster_valid,
    output                                                  o_cluster_certified,
    output     [acc_width - 1 : 0]                          o_cluster_max_error,
    output     [num_rows * data_width - 1 : 0]              o_read_state_p_rows,
    output     [num_rows * data_width - 1 : 0]              o_read_state_n_rows
);

    wire [num_rows - 1 : 0] w_replay_x2_p_rows;
    wire [num_rows - 1 : 0] w_replay_x2_n_rows;
    wire [num_rows - 1 : 0] w_replay_x3_p_rows;
    wire [num_rows - 1 : 0] w_replay_x3_n_rows;
    wire [num_rows - 1 : 0] w_write_valid_rows;
    wire [num_rows * digit_idx_width - 1 : 0] w_write_digit_idx_rows;
    wire [num_rows - 1 : 0] w_write_digit_p_rows;
    wire [num_rows - 1 : 0] w_write_digit_n_rows;
    wire [num_rows - 1 : 0] w_delta_valid_rows;
    wire [num_rows - 1 : 0] w_delta_final_rows;

    iter_solver_native_cluster_digit_stream_top #(
        .num_rows(num_rows),
        .degree(degree),
        .bit_width(bit_width),
        .data_width(data_width),
        .bias_width(bias_width),
        .skip_digits(skip_digits),
        .affine_guard_shift(affine_guard_shift),
        .sample_width(sample_width),
        .row_idx_width(row_idx_width),
        .digit_idx_width(digit_idx_width)
    ) cluster_stream (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_ena_rows(i_ena_rows),
        .i_digit_idx(i_digit_idx),
        .i_use_replay(i_use_replay),
        .i_clear_write_bank(i_clear_write_bank),
        .i_commit_swap(i_commit_swap),
        .i_load_state(i_load_state),
        .i_load_bank_sel(i_load_bank_sel),
        .i_load_row_idx(i_load_row_idx),
        .i_load_state_p(i_load_state_p),
        .i_load_state_n(i_load_state_n),
        .i_src_row_idx(i_src_row_idx),
        .i_ext_x0_p_rows(i_ext_x0_p_rows),
        .i_ext_x0_n_rows(i_ext_x0_n_rows),
        .i_ext_x1_p_rows(i_ext_x1_p_rows),
        .i_ext_x1_n_rows(i_ext_x1_n_rows),
        .i_ext_x2_p_rows(i_ext_x2_p_rows),
        .i_ext_x2_n_rows(i_ext_x2_n_rows),
        .i_ext_x3_p_rows(i_ext_x3_p_rows),
        .i_ext_x3_n_rows(i_ext_x3_n_rows),
        .i_coeff_p_terms_rows(i_coeff_p_terms_rows),
        .i_coeff_n_terms_rows(i_coeff_n_terms_rows),
        .i_bias_p_rows(i_bias_p_rows),
        .i_bias_n_rows(i_bias_n_rows),
        .o_replay_x0_p_rows(o_replay_x0_p_rows),
        .o_replay_x0_n_rows(o_replay_x0_n_rows),
        .o_replay_x1_p_rows(o_replay_x1_p_rows),
        .o_replay_x1_n_rows(o_replay_x1_n_rows),
        .o_replay_x2_p_rows(w_replay_x2_p_rows),
        .o_replay_x2_n_rows(w_replay_x2_n_rows),
        .o_replay_x3_p_rows(w_replay_x3_p_rows),
        .o_replay_x3_n_rows(w_replay_x3_n_rows),
        .o_row_valid(),
        .o_row_digit_p(),
        .o_row_digit_n(),
        .o_write_valid_rows(w_write_valid_rows),
        .o_write_digit_idx_rows(w_write_digit_idx_rows),
        .o_write_digit_p_rows(w_write_digit_p_rows),
        .o_write_digit_n_rows(w_write_digit_n_rows),
        .o_write_done_rows(o_write_done_rows),
        .o_read_state_p_rows(o_read_state_p_rows),
        .o_read_state_n_rows(o_read_state_n_rows)
    );

    genvar ri;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_delta_rows
            wire [digit_idx_width - 1 : 0] w_write_idx;
            wire [data_width - 1 : 0] w_old_p_word;
            wire [data_width - 1 : 0] w_old_n_word;
            wire w_old_digit_p;
            wire w_old_digit_n;
            wire [bound_width - 1 : 0] w_abs_upper;
            wire [bound_width : 0] w_abs_upper_with_tail;
            integer bit_sel;

            assign w_write_idx =
                w_write_digit_idx_rows[(ri + 1) * digit_idx_width - 1 -: digit_idx_width];
            assign w_old_p_word =
                o_read_state_p_rows[(ri + 1) * data_width - 1 -: data_width];
            assign w_old_n_word =
                o_read_state_n_rows[(ri + 1) * data_width - 1 -: data_width];
            always @(*) begin
                bit_sel = data_width - 1 - w_write_idx;
            end
            assign w_old_digit_p = w_old_p_word[bit_sel];
            assign w_old_digit_n = w_old_n_word[bit_sel];

            iter_digit_stream_delta_bound #(
                .data_width(data_width),
                .bound_width(bound_width),
                .acc_width(acc_width),
                .final_only(1),
                .digit_idx_width(digit_idx_width)
            ) delta_bound (
                .i_clk(i_clk),
                .i_rst(i_rst || i_clear_write_bank),
                .i_start(w_write_valid_rows[ri] &&
                         (w_write_idx == {digit_idx_width{1'b0}})),
                .i_valid(w_write_valid_rows[ri]),
                .i_digit_idx(w_write_idx),
                .i_new_digit_p(w_write_digit_p_rows[ri]),
                .i_new_digit_n(w_write_digit_n_rows[ri]),
                .i_old_digit_p(w_old_digit_p),
                .i_old_digit_n(w_old_digit_n),
                .o_valid(w_delta_valid_rows[ri]),
                .o_prefix_delta(),
                .o_abs_upper(w_abs_upper),
                .o_final(w_delta_final_rows[ri])
            );

            assign w_abs_upper_with_tail =
                {1'b0, w_abs_upper} + {1'b0, i_tail_bound};
            assign o_abs_upper_rows[(ri + 1) * bound_width - 1 -: bound_width] =
                w_abs_upper_with_tail[bound_width]
                    ? {bound_width{1'b1}}
                    : w_abs_upper_with_tail[bound_width - 1 : 0];
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
        .cert_compare_pipeline(cert_compare_pipeline),
        .input_pipeline(0),
        .output_pipeline(0)
    ) cluster_cert (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_valid_rows(w_delta_valid_rows & w_delta_final_rows),
        .i_row_abs_upper(o_abs_upper_rows),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid(o_cluster_valid),
        .o_block_bounds(o_block_bounds),
        .o_certified(o_cluster_certified),
        .o_max_error(o_cluster_max_error)
    );

endmodule
