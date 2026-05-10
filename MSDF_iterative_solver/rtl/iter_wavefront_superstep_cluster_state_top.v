`timescale 1ns / 1ps

// Runtime-adjacent committed wavefront super-step cluster.
//
// This shell adds the state-bank boundary around the committed K-stage
// wavefront:
//   state replay or external source stream
//     -> K-stage committed wavefront
//     -> last internal delta certification
//     -> final committed digits written into inactive state bank
//
// It is the intended building block for a future ROW_DATAPATH_MODE=4
// WAVEFRONT_SUPERSTEP_K runtime mode.

module iter_wavefront_superstep_cluster_state_top #(
    parameter integer superstep_stages = 4,
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
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_start,
    input                                                   i_valid_digit,
    input      [digit_idx_width - 1 : 0]                    i_digit_idx,
    input                                                   i_use_replay,
    input                                                   i_clear_write_bank,
    input                                                   i_commit_swap,

    input                                                   i_load_state,
    input                                                   i_load_bank_sel,
    input      [row_idx_width - 1 : 0]                      i_load_row_idx,
    input      [data_width - 1 : 0]                         i_load_state_p,
    input      [data_width - 1 : 0]                         i_load_state_n,

    input      [num_rows * degree * src_idx_width - 1 : 0]  i_src_row_idx,
    input      [superstep_stages * source_rows - 1 : 0]     i_inter_stage_source_p_rows,
    input      [superstep_stages * source_rows - 1 : 0]     i_inter_stage_source_n_rows,
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
    output     [num_rows - 1 : 0]                           o_replay_x2_p_rows,
    output     [num_rows - 1 : 0]                           o_replay_x2_n_rows,
    output     [num_rows - 1 : 0]                           o_replay_x3_p_rows,
    output     [num_rows - 1 : 0]                           o_replay_x3_n_rows,
    output     [num_rows - 1 : 0]                           o_final_valid_rows,
    output     [num_rows * digit_idx_width - 1 : 0]          o_final_digit_idx_rows,
    output     [num_rows - 1 : 0]                           o_final_digit_p_rows,
    output     [num_rows - 1 : 0]                           o_final_digit_n_rows,
    output     [num_rows * data_width - 1 : 0]              o_read_state_p_rows,
    output     [num_rows * data_width - 1 : 0]              o_read_state_n_rows,
    output                                                  o_cluster_valid,
    output                                                  o_cluster_certified,
    output     [acc_width - 1 : 0]                          o_cluster_max_error,
    output     [superstep_stages * num_rows - 1 : 0]         o_stage_commit_valid_rows,
    output     [superstep_stages * num_rows * digit_idx_width - 1 : 0] o_stage_commit_digit_idx_rows,
    output     [superstep_stages * num_rows - 1 : 0]         o_stage_commit_digit_p_rows,
    output     [superstep_stages * num_rows - 1 : 0]         o_stage_commit_digit_n_rows,
    output     [superstep_stages - 1 : 0]                   o_stage_done
);

    wire [num_rows - 1 : 0] w_src_x0_p_rows;
    wire [num_rows - 1 : 0] w_src_x0_n_rows;
    wire [num_rows - 1 : 0] w_src_x1_p_rows;
    wire [num_rows - 1 : 0] w_src_x1_n_rows;
    wire [num_rows - 1 : 0] w_src_x2_p_rows;
    wire [num_rows - 1 : 0] w_src_x2_n_rows;
    wire [num_rows - 1 : 0] w_src_x3_p_rows;
    wire [num_rows - 1 : 0] w_src_x3_n_rows;
    wire [num_rows * degree - 1 : 0] w_stage0_state_p_terms_rows;
    wire [num_rows * degree - 1 : 0] w_stage0_state_n_terms_rows;
    wire [num_rows * degree * row_idx_width - 1 : 0] w_local_src_row_idx;
    wire [superstep_stages * num_rows * degree * bit_width - 1 : 0] w_coeff_p_terms_stages;
    wire [superstep_stages * num_rows * degree * bit_width - 1 : 0] w_coeff_n_terms_stages;
    wire [superstep_stages * num_rows * bias_width - 1 : 0] w_bias_p_stages;
    wire [superstep_stages * num_rows * bias_width - 1 : 0] w_bias_n_stages;

    assign w_src_x0_p_rows = i_use_replay ? o_replay_x0_p_rows : i_ext_x0_p_rows;
    assign w_src_x0_n_rows = i_use_replay ? o_replay_x0_n_rows : i_ext_x0_n_rows;
    assign w_src_x1_p_rows = i_use_replay ? o_replay_x1_p_rows : i_ext_x1_p_rows;
    assign w_src_x1_n_rows = i_use_replay ? o_replay_x1_n_rows : i_ext_x1_n_rows;
    assign w_src_x2_p_rows = i_use_replay ? o_replay_x2_p_rows : i_ext_x2_p_rows;
    assign w_src_x2_n_rows = i_use_replay ? o_replay_x2_n_rows : i_ext_x2_n_rows;
    assign w_src_x3_p_rows = i_use_replay ? o_replay_x3_p_rows : i_ext_x3_p_rows;
    assign w_src_x3_n_rows = i_use_replay ? o_replay_x3_n_rows : i_ext_x3_n_rows;

    genvar si;
    genvar ri;
    genvar ti;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_local_src_rows
            for (ti = 0; ti < degree; ti = ti + 1) begin : gen_local_src_terms
                assign w_local_src_row_idx[(ri * degree + ti) * row_idx_width +: row_idx_width] =
                    i_src_row_idx[(ri * degree + ti) * src_idx_width +: row_idx_width];
            end
        end

        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_stage0_pack
            assign w_stage0_state_p_terms_rows[ri * degree + 0] = w_src_x0_p_rows[ri];
            assign w_stage0_state_n_terms_rows[ri * degree + 0] = w_src_x0_n_rows[ri];
            assign w_stage0_state_p_terms_rows[ri * degree + 1] = w_src_x1_p_rows[ri];
            assign w_stage0_state_n_terms_rows[ri * degree + 1] = w_src_x1_n_rows[ri];
            assign w_stage0_state_p_terms_rows[ri * degree + 2] = w_src_x2_p_rows[ri];
            assign w_stage0_state_n_terms_rows[ri * degree + 2] = w_src_x2_n_rows[ri];
            assign w_stage0_state_p_terms_rows[ri * degree + 3] = w_src_x3_p_rows[ri];
            assign w_stage0_state_n_terms_rows[ri * degree + 3] = w_src_x3_n_rows[ri];
        end

        for (si = 0; si < superstep_stages; si = si + 1) begin : gen_stage_params
            assign w_coeff_p_terms_stages[si * num_rows * degree * bit_width +:
                num_rows * degree * bit_width] = i_coeff_p_terms_rows;
            assign w_coeff_n_terms_stages[si * num_rows * degree * bit_width +:
                num_rows * degree * bit_width] = i_coeff_n_terms_rows;
            assign w_bias_p_stages[si * num_rows * bias_width +:
                num_rows * bias_width] = i_bias_p_rows;
            assign w_bias_n_stages[si * num_rows * bias_width +:
                num_rows * bias_width] = i_bias_n_rows;
        end
    endgenerate

    iter_wavefront_commit_last_delta_cert_top #(
        .num_stages(superstep_stages),
        .num_rows(num_rows),
        .degree(degree),
        .bit_width(bit_width),
        .data_width(data_width),
        .bias_width(bias_width),
        .bound_width(bound_width),
        .coeff_width(coeff_width),
        .acc_width(acc_width),
        .block_size(block_size),
        .num_blocks(num_blocks),
        .skip_digits(skip_digits),
        .sample_width(sample_width),
        .affine_guard_shift(affine_guard_shift),
        .row_idx_width(row_idx_width),
        .source_rows(source_rows),
        .src_idx_width(src_idx_width),
        .digit_idx_width(digit_idx_width),
        .inter_stage_delay_cycles(inter_stage_delay_cycles),
        .inter_stage_source_mode(inter_stage_source_mode),
        .cert_product_pipeline(cert_product_pipeline),
        .cert_operand_pipeline(cert_operand_pipeline),
        .cert_compare_pipeline(cert_compare_pipeline)
    ) superstep_core (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_stage0_state_digit_p_terms_rows(w_stage0_state_p_terms_rows),
        .i_stage0_state_digit_n_terms_rows(w_stage0_state_n_terms_rows),
        .i_coeff_p_terms_stages(w_coeff_p_terms_stages),
        .i_coeff_n_terms_stages(w_coeff_n_terms_stages),
        .i_bias_p_stages(w_bias_p_stages),
        .i_bias_n_stages(w_bias_n_stages),
        .i_stage_src_row_idx(i_src_row_idx),
        .i_external_stage_source_p_rows(i_inter_stage_source_p_rows),
        .i_external_stage_source_n_rows(i_inter_stage_source_n_rows),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .i_tail_bound(i_tail_bound),
        .o_final_valid_rows(o_final_valid_rows),
        .o_final_digit_idx_rows(o_final_digit_idx_rows),
        .o_final_digit_p_rows(o_final_digit_p_rows),
        .o_final_digit_n_rows(o_final_digit_n_rows),
        .o_abs_upper_rows(),
        .o_block_bounds(),
        .o_cluster_valid(o_cluster_valid),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error),
        .o_stage_commit_valid_rows(o_stage_commit_valid_rows),
        .o_stage_commit_digit_idx_rows(o_stage_commit_digit_idx_rows),
        .o_stage_commit_digit_p_rows(o_stage_commit_digit_p_rows),
        .o_stage_commit_digit_n_rows(o_stage_commit_digit_n_rows),
        .o_stage_valid_count(),
        .o_stage_done(o_stage_done),
        .o_stage_started_before_prev_done()
    );

    iter_digit_stream_state_replay_top #(
        .num_rows(num_rows),
        .degree(degree),
        .data_width(data_width),
        .msb_first(1),
        .row_idx_width(row_idx_width),
        .digit_idx_width(digit_idx_width)
    ) state_replay (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_commit_swap(i_commit_swap),
        .i_clear_write_bank(i_clear_write_bank),
        .i_load_state(i_load_state),
        .i_load_bank_sel(i_load_bank_sel),
        .i_load_row_idx(i_load_row_idx),
        .i_load_state_p(i_load_state_p),
        .i_load_state_n(i_load_state_n),
        .i_write_digit_valid_rows(o_final_valid_rows),
        .i_write_digit_idx(o_final_digit_idx_rows[digit_idx_width - 1 : 0]),
        .i_write_digit_p_rows(o_final_digit_p_rows),
        .i_write_digit_n_rows(o_final_digit_n_rows),
        .i_replay_digit_idx(i_digit_idx),
        .i_src_row_idx(w_local_src_row_idx),
        .o_read_bank_sel(),
        .o_read_state_p_rows(o_read_state_p_rows),
        .o_read_state_n_rows(o_read_state_n_rows),
        .o_x0_p_rows(o_replay_x0_p_rows),
        .o_x0_n_rows(o_replay_x0_n_rows),
        .o_x1_p_rows(o_replay_x1_p_rows),
        .o_x1_n_rows(o_replay_x1_n_rows),
        .o_x2_p_rows(o_replay_x2_p_rows),
        .o_x2_n_rows(o_replay_x2_n_rows),
        .o_x3_p_rows(o_replay_x3_p_rows),
        .o_x3_n_rows(o_replay_x3_n_rows)
    );

endmodule
