`timescale 1ns / 1ps

// K-stage committed-state wavefront with final-iteration delta certification.
//
// Certification checks the last solver step inside the fused super-step:
//   delta = x^(k+K) - x^(k+K-1)
//
// It does not compare the final state against the super-step input x^k.  This
// keeps the convergence meaning compatible with the original per-iteration
// solver rule while still allowing the K stages to run as a digit wavefront.

module iter_wavefront_commit_last_delta_cert_top #(
    parameter integer num_stages = 4,
    parameter integer num_rows = 3,
    parameter integer degree = 4,
    parameter integer bit_width = 5,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer bound_width = bit_width + 5,
    parameter integer coeff_width = 8,
    parameter integer acc_width = 24,
    parameter integer block_size = 2,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size,
    parameter integer skip_digits = 4,
    parameter integer sample_width = 5,
    parameter integer affine_guard_shift = 3,
    parameter integer residual_width = data_width + affine_guard_shift + 1,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer source_rows = num_rows,
    parameter integer src_idx_width = row_idx_width,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer inter_stage_delay_cycles = 0,
    parameter integer inter_stage_source_mode = 0,
    parameter integer cert_product_pipeline = 0,
    parameter integer cert_operand_pipeline = 0,
    parameter integer cert_compare_pipeline = 0
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_start,
    input                                               i_valid_digit,
    input      [digit_idx_width - 1 : 0]                i_digit_idx,
    input      [num_rows * degree - 1 : 0]              i_stage0_state_digit_p_terms_rows,
    input      [num_rows * degree - 1 : 0]              i_stage0_state_digit_n_terms_rows,
    input      [num_stages * num_rows * degree * bit_width - 1 : 0] i_coeff_p_terms_stages,
    input      [num_stages * num_rows * degree * bit_width - 1 : 0] i_coeff_n_terms_stages,
    input      [num_stages * num_rows * bias_width - 1 : 0] i_bias_p_stages,
    input      [num_stages * num_rows * bias_width - 1 : 0] i_bias_n_stages,
    input      [num_rows * degree * src_idx_width - 1 : 0] i_stage_src_row_idx,
    input      [num_stages * source_rows - 1 : 0]          i_external_stage_source_p_rows,
    input      [num_stages * source_rows - 1 : 0]          i_external_stage_source_n_rows,
    input      [num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights,
    input      [acc_width - 1 : 0]                       i_eta,
    input      [bound_width - 1 : 0]                     i_tail_bound,
    output     [num_rows - 1 : 0]                        o_final_valid_rows,
    output     [num_rows * digit_idx_width - 1 : 0]      o_final_digit_idx_rows,
    output     [num_rows - 1 : 0]                        o_final_digit_p_rows,
    output     [num_rows - 1 : 0]                        o_final_digit_n_rows,
    output     [num_rows * bound_width - 1 : 0]          o_abs_upper_rows,
    output     [num_blocks * bound_width - 1 : 0]        o_block_bounds,
    output                                              o_cluster_valid,
    output                                              o_cluster_certified,
    output     [acc_width - 1 : 0]                       o_cluster_max_error,
    output     [num_stages * num_rows - 1 : 0]           o_stage_commit_valid_rows,
    output     [num_stages * num_rows * digit_idx_width - 1 : 0] o_stage_commit_digit_idx_rows,
    output     [num_stages * num_rows - 1 : 0]           o_stage_commit_digit_p_rows,
    output     [num_stages * num_rows - 1 : 0]           o_stage_commit_digit_n_rows,
    output     [num_stages * 32 - 1 : 0]                 o_stage_valid_count,
    output     [num_stages - 1 : 0]                      o_stage_done,
    output     [num_stages - 2 : 0]                      o_stage_started_before_prev_done
);

    localparam integer prev_stage_idx = num_stages - 2;
    localparam integer final_stage_idx = num_stages - 1;

    wire [num_stages * num_rows - 1 : 0] w_stage_commit_done_rows;
    reg [num_rows * data_width - 1 : 0] r_prev_stage_p_rows;
    reg [num_rows * data_width - 1 : 0] r_prev_stage_n_rows;
    wire [num_rows - 1 : 0] w_delta_valid_rows;
    wire [num_rows - 1 : 0] w_delta_final_rows;

    integer ri_seq;
    integer bit_sel_seq;

    iter_wavefront_radius1_commit_multistage_cluster #(
        .num_stages(num_stages),
        .num_rows(num_rows),
        .degree(degree),
        .bit_width(bit_width),
        .data_width(data_width),
        .bias_width(bias_width),
        .skip_digits(skip_digits),
        .sample_width(sample_width),
        .affine_guard_shift(affine_guard_shift),
        .residual_width(residual_width),
        .digit_idx_width(digit_idx_width),
        .row_idx_width(row_idx_width),
        .source_rows(source_rows),
        .src_idx_width(src_idx_width),
        .inter_stage_delay_cycles(inter_stage_delay_cycles),
        .inter_stage_source_mode(inter_stage_source_mode)
    ) wavefront (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_stage0_state_digit_p_terms_rows(i_stage0_state_digit_p_terms_rows),
        .i_stage0_state_digit_n_terms_rows(i_stage0_state_digit_n_terms_rows),
        .i_coeff_p_terms_stages(i_coeff_p_terms_stages),
        .i_coeff_n_terms_stages(i_coeff_n_terms_stages),
        .i_bias_p_stages(i_bias_p_stages),
        .i_bias_n_stages(i_bias_n_stages),
        .i_stage_src_row_idx(i_stage_src_row_idx),
        .i_external_stage_source_p_rows(i_external_stage_source_p_rows),
        .i_external_stage_source_n_rows(i_external_stage_source_n_rows),
        .o_stage_commit_valid_rows(o_stage_commit_valid_rows),
        .o_stage_commit_digit_idx_rows(o_stage_commit_digit_idx_rows),
        .o_stage_commit_digit_p_rows(o_stage_commit_digit_p_rows),
        .o_stage_commit_digit_n_rows(o_stage_commit_digit_n_rows),
        .o_stage_commit_done_rows(w_stage_commit_done_rows),
        .o_final_valid_rows(o_final_valid_rows),
        .o_final_digit_idx_rows(o_final_digit_idx_rows),
        .o_final_digit_p_rows(o_final_digit_p_rows),
        .o_final_digit_n_rows(o_final_digit_n_rows),
        .o_stage_valid_count(o_stage_valid_count),
        .o_stage_done(o_stage_done),
        .o_stage_started_before_prev_done(o_stage_started_before_prev_done)
    );

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            r_prev_stage_p_rows <= {num_rows * data_width{1'b0}};
            r_prev_stage_n_rows <= {num_rows * data_width{1'b0}};
        end else begin
            for (ri_seq = 0; ri_seq < num_rows; ri_seq = ri_seq + 1) begin
                if (o_stage_commit_valid_rows[prev_stage_idx * num_rows + ri_seq]) begin
                    bit_sel_seq = o_stage_commit_digit_idx_rows[
                        (prev_stage_idx * num_rows + ri_seq) * digit_idx_width +:
                        digit_idx_width];
                    r_prev_stage_p_rows[ri_seq * data_width + bit_sel_seq] <=
                        o_stage_commit_digit_p_rows[prev_stage_idx * num_rows + ri_seq];
                    r_prev_stage_n_rows[ri_seq * data_width + bit_sel_seq] <=
                        o_stage_commit_digit_n_rows[prev_stage_idx * num_rows + ri_seq];
                end
            end
        end
    end

    genvar ri;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_delta_rows
            wire [digit_idx_width - 1 : 0] w_final_idx;
            wire w_prev_digit_p;
            wire w_prev_digit_n;
            wire [bound_width - 1 : 0] w_abs_upper;
            wire [bound_width : 0] w_abs_upper_with_tail;

            assign w_final_idx =
                o_final_digit_idx_rows[ri * digit_idx_width +: digit_idx_width];
            assign w_prev_digit_p = r_prev_stage_p_rows[ri * data_width + w_final_idx];
            assign w_prev_digit_n = r_prev_stage_n_rows[ri * data_width + w_final_idx];

            iter_digit_stream_delta_bound #(
                .data_width(data_width),
                .bound_width(bound_width),
                .acc_width(acc_width),
                .final_only(1),
                .digit_idx_width(digit_idx_width)
            ) delta_bound (
                .i_clk(i_clk),
                .i_rst(i_rst || i_start),
                .i_start(o_final_valid_rows[ri] &&
                         (w_final_idx == {digit_idx_width{1'b0}})),
                .i_valid(o_final_valid_rows[ri]),
                .i_digit_idx(w_final_idx),
                .i_new_digit_p(o_final_digit_p_rows[ri]),
                .i_new_digit_n(o_final_digit_n_rows[ri]),
                .i_old_digit_p(w_prev_digit_p),
                .i_old_digit_n(w_prev_digit_n),
                .o_valid(w_delta_valid_rows[ri]),
                .o_prefix_delta(),
                .o_abs_upper(w_abs_upper),
                .o_final(w_delta_final_rows[ri])
            );

            assign w_abs_upper_with_tail =
                {1'b0, w_abs_upper} + {1'b0, i_tail_bound};
            assign o_abs_upper_rows[ri * bound_width +: bound_width] =
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
