`timescale 1ns / 1ps

// Continuous-feedback PageRank pipeline for the P3-SP parallel-in online MAC.
//
// The final-stage committed digit packet is written into a feedback FIFO and
// consumed by stage 0 as the next PageRank operand stream.  This implements a
// bounded physical K-stage loop instead of unrolling an unbounded number of
// PageRank iterations.
//
// Convergence follows the original PageRank paper condition used by the prior
// work:
//
//     max_i |r_i(k+1) - r_i(k)| <= 2^-q
//
// In this fixed-point RTL contract, 2^-q is represented as one raw LSB, so the
// default threshold is i_linf_eta = 1.

module iter_parallel_in_online_mma8_global_feedback_top #(
    parameter integer num_stages = 4,
    parameter integer num_rows = 32,
    parameter integer degree = 4,
    parameter integer physical_degree = 8,
    parameter integer bit_width = 30,
    parameter integer data_width = 32,
    parameter integer bias_width = bit_width + 2,
    parameter integer online_delay = 2,
    parameter integer acc_width = 64,
    parameter integer core_acc_width = 36,
    parameter integer fast2_core = 0,
    parameter integer estimate_selector = 0,
    parameter integer estimate_frac_bits = 6,
    parameter integer estimate_guard_bits = 2,
    parameter integer split_estimate = 1,
    parameter integer redundant_residual = 0,
    parameter integer nonnegative_coeff = 0,
    parameter integer nonnegative_bias = 0,
    parameter integer source_onehot = 0,
    parameter integer src_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer feedback_fifo_depth = 128,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer fifo_ptr_width = (feedback_fifo_depth <= 2) ? 1 : $clog2(feedback_fifo_depth),
    parameter integer fifo_count_width = (feedback_fifo_depth <= 2) ? 2 : $clog2(feedback_fifo_depth + 1),
    parameter integer converged_stage_width = (num_stages <= 2) ? 1 : $clog2(num_stages)
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_clear,
    input                                                   i_start,
    input                                                   i_valid_digit,
    input      [digit_idx_width - 1 : 0]                    i_digit_idx,
    input      [num_rows - 1 : 0]                           i_stage0_state_digit_p_rows,
    input      [num_rows - 1 : 0]                           i_stage0_state_digit_n_rows,
    input      [num_rows * degree * src_idx_width - 1 : 0]  i_src_row_idx_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_n_rows,
    input      [acc_width - 1 : 0]                          i_linf_eta,
    input                                                   i_stop_on_converged,
    output     [num_rows - 1 : 0]                           o_final_valid_rows,
    output     [num_rows * digit_idx_width - 1 : 0]         o_final_digit_idx_rows,
    output     [num_rows - 1 : 0]                           o_final_digit_p_rows,
    output     [num_rows - 1 : 0]                           o_final_digit_n_rows,
    output     [num_rows - 1 : 0]                           o_final_done_rows,
    output     [num_stages * num_rows - 1 : 0]              o_stage_valid_rows,
    output     [num_stages * num_rows * digit_idx_width - 1 : 0] o_stage_digit_idx_rows,
    output     [num_stages * num_rows - 1 : 0]              o_stage_digit_p_rows,
    output     [num_stages * num_rows - 1 : 0]              o_stage_digit_n_rows,
    output     [num_stages * num_rows - 1 : 0]              o_stage_done_rows,
    output reg [num_stages * 32 - 1 : 0]                    o_stage_valid_count,
    output reg [num_stages * 32 - 1 : 0]                    o_stage_linf_valid_count,
    output reg [num_stages * acc_width - 1 : 0]             o_stage_linf_delta,
    output reg [num_stages - 1 : 0]                         o_stage_linf_valid,
    output reg [num_stages - 1 : 0]                         o_stage_done,
    output reg [num_stages - 2 : 0]                         o_stage_started_before_prev_done,
    output reg [31 : 0]                                     o_superstep_count,
    output reg [31 : 0]                                     o_feedback_fifo_stall,
    output reg [31 : 0]                                     o_cert_late_cycles,
    output reg [num_stages * 32 - 1 : 0]                    o_converged_stage_histogram,
    output reg [31 : 0]                                     o_speculative_kill_digits,
    output reg                                              o_converged,
    output reg [converged_stage_width - 1 : 0]              o_converged_stage
);

    localparam [fifo_count_width - 1 : 0] FIFO_DEPTH_VALUE =
        feedback_fifo_depth[fifo_count_width - 1 : 0];
    localparam integer linf_group_size = 4;
    localparam integer linf_num_groups = (num_rows + linf_group_size - 1) / linf_group_size;
    localparam integer linf_mid_group_size = 2;
    localparam integer linf_num_mid_groups =
        (linf_num_groups + linf_mid_group_size - 1) / linf_mid_group_size;
    localparam integer stage_digit_group_size = 4;
    localparam integer stage_digit_groups =
        (num_rows + stage_digit_group_size - 1) / stage_digit_group_size;

    wire [num_stages - 1 : 0] w_stage_input_valid;
    wire [num_stages - 1 : 0] w_stage_start;
    wire [num_stages - 1 : 0] w_stage_busy;
    wire [num_stages * digit_idx_width - 1 : 0] w_stage_digit_idx;
    wire [num_stages * num_rows * degree - 1 : 0] w_stage_state_p_terms;
    wire [num_stages * num_rows * degree - 1 : 0] w_stage_state_n_terms;
    wire [num_stages * stage_digit_groups * num_rows - 1 : 0]
        w_stage_digit_p_group_rows;
    wire [num_stages * stage_digit_groups * num_rows - 1 : 0]
        w_stage_digit_n_group_rows;

    reg r_external_active;
    reg [digit_idx_width - 1 : 0] r_external_count;
    (* max_fanout = 4 *) reg r_feedback_operand_active;
    reg [digit_idx_width - 1 : 0] r_feedback_count;
    reg r_stop_requested;

    reg [digit_idx_width - 1 : 0] r_fifo_idx [0 : feedback_fifo_depth - 1];
    reg [num_rows - 1 : 0] r_fifo_p [0 : feedback_fifo_depth - 1];
    reg [num_rows - 1 : 0] r_fifo_n [0 : feedback_fifo_depth - 1];
    reg [fifo_ptr_width - 1 : 0] r_fifo_wr_ptr;
    reg [fifo_ptr_width - 1 : 0] r_fifo_rd_ptr;
    reg [fifo_count_width - 1 : 0] r_fifo_count;
    reg r_feedback_buf_valid;
    reg [digit_idx_width - 1 : 0] r_feedback_buf_idx;
    reg r_feedback_buf_first;
    reg [num_rows - 1 : 0] r_feedback_buf_p;
    reg [num_rows - 1 : 0] r_feedback_buf_n;
    reg [num_rows * degree - 1 : 0] r_feedback_terms_p;
    reg [num_rows * degree - 1 : 0] r_feedback_terms_n;
    // PageRank templates are static while a solve is running.  Decode source
    // row indices into one-hot masks off the digit critical path so each
    // stage-to-stage term select is an AND/OR data mux, not a dynamic bit
    // select with index decode in the same cycle.
    reg [num_rows * degree * num_rows - 1 : 0] r_src_onehot_terms;

    reg [num_rows * data_width - 1 : 0] r_stage_old_p [0 : num_stages - 1];
    reg [num_rows * data_width - 1 : 0] r_stage_old_n [0 : num_stages - 1];
    reg [num_rows * data_width - 1 : 0] r_stage_new_p [0 : num_stages - 1];
    reg [num_rows * data_width - 1 : 0] r_stage_new_n [0 : num_stages - 1];
    reg signed [data_width : 0] r_stage_old_value [0 : num_stages - 1][0 : num_rows - 1];
    reg signed [data_width : 0] r_stage_new_value [0 : num_stages - 1][0 : num_rows - 1];
    reg [num_stages - 1 : 0] r_linf_pending;
    reg [num_stages - 1 : 0] r_linf_abs_valid;
    reg [num_stages - 1 : 0] r_linf_group_valid;
    reg [num_stages - 1 : 0] r_linf_mid_valid;
    reg [num_stages - 1 : 0] r_linf_global_valid;
    reg [31 : 0] r_linf_abs_delta [0 : num_stages - 1][0 : num_rows - 1];
    reg [31 : 0] r_linf_group_max [0 : num_stages - 1][0 : linf_num_groups - 1];
    reg [31 : 0] r_linf_mid_max [0 : num_stages - 1][0 : linf_num_mid_groups - 1];
    reg [31 : 0] r_linf_global_max [0 : num_stages - 1];
    reg [num_stages - 1 : 0] r_stage_local_clear;
    reg [num_stages * num_rows - 1 : 0] r_stage_local_clear_rows;

    wire w_final_valid;
    wire w_final_done;
    wire w_fifo_empty;
    wire w_fifo_full;
    wire [digit_idx_width - 1 : 0] w_fifo_head_idx;
    wire [num_rows - 1 : 0] w_fifo_head_p;
    wire [num_rows - 1 : 0] w_fifo_head_n;
    wire w_feedback_buf_fill;
    wire w_feedback_start;
    wire w_feedback_consume;
    wire w_fifo_write;
    wire w_fifo_has_room;
    wire [num_rows - 1 : 0] w_stage0_source_p_rows;
    wire [num_rows - 1 : 0] w_stage0_source_n_rows;

    integer si_seq;
    integer ri_seq;
    integer bit_sel_seq;
    integer fifo_i;
    integer row_new_value;
    integer row_old_value;
    integer row_delta_value;
    integer row_linf_next;
    integer digit_value;
    integer group_idx;
    integer group_base;
    integer group_max_next;
    integer mid_idx;
    integer mid_base;
    integer fb_row_idx;
    integer fb_term_idx;
    integer fb_src_row;
    integer src_dec_row_idx;
    integer src_dec_term_idx;
    integer src_dec_row_value;

    assign o_final_valid_rows =
        o_stage_valid_rows[(num_stages - 1) * num_rows +: num_rows];
    assign o_final_digit_idx_rows =
        o_stage_digit_idx_rows[(num_stages - 1) *
            num_rows * digit_idx_width +: num_rows * digit_idx_width];
    assign o_final_digit_p_rows =
        o_stage_digit_p_rows[(num_stages - 1) * num_rows +: num_rows];
    assign o_final_digit_n_rows =
        o_stage_digit_n_rows[(num_stages - 1) * num_rows +: num_rows];
    assign o_final_done_rows =
        o_stage_done_rows[(num_stages - 1) * num_rows +: num_rows];

    assign w_final_valid = o_final_valid_rows[0];
    assign w_final_done = o_final_done_rows[0];
    assign w_fifo_empty = (r_fifo_count == {fifo_count_width{1'b0}});
    assign w_fifo_full = (r_fifo_count == FIFO_DEPTH_VALUE);
    assign w_fifo_head_idx = r_fifo_idx[r_fifo_rd_ptr];
    assign w_fifo_head_p = r_fifo_p[r_fifo_rd_ptr];
    assign w_fifo_head_n = r_fifo_n[r_fifo_rd_ptr];
    assign w_feedback_buf_fill =
        (!r_feedback_buf_valid || w_feedback_consume) &&
        !w_fifo_empty &&
        !r_external_active;
    assign w_feedback_start =
        !r_feedback_operand_active &&
        !w_stage_busy[0] &&
        !w_stage_busy[1] &&
        r_feedback_buf_valid &&
        r_feedback_buf_first;
    assign w_feedback_consume =
        (r_feedback_operand_active || w_feedback_start) &&
        r_feedback_buf_valid;
    assign w_fifo_has_room =
        (r_fifo_count < FIFO_DEPTH_VALUE) || w_feedback_buf_fill;
    assign w_fifo_write = w_final_valid && !r_stop_requested &&
        w_fifo_has_room;
    assign w_stage0_source_p_rows =
        r_feedback_buf_valid ? r_feedback_buf_p :
        i_stage0_state_digit_p_rows;
    assign w_stage0_source_n_rows =
        r_feedback_buf_valid ? r_feedback_buf_n :
        i_stage0_state_digit_n_rows;

    function integer sd_digit_value;
        input p_digit;
        input n_digit;
        begin
            if (p_digit && !n_digit) begin
                sd_digit_value = 1;
            end else if (n_digit && !p_digit) begin
                sd_digit_value = -1;
            end else begin
                sd_digit_value = 0;
            end
        end
    endfunction

    genvar si;
    genvar ri;
    genvar ti;
    generate
        for (si = 0; si < num_stages; si = si + 1) begin : gen_stage
            if (si == 0) begin : gen_stage0_source
                assign w_stage_input_valid[si] =
                    r_feedback_buf_valid ?
                        w_feedback_consume : i_valid_digit;
                assign w_stage_start[si] =
                    r_feedback_buf_valid ?
                        w_feedback_start : i_start;
                assign w_stage_digit_idx[si * digit_idx_width +: digit_idx_width] =
                    r_feedback_buf_valid ?
                        r_feedback_count : i_digit_idx;

                for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
                    wire w_stage0_feedback_row;
                    assign w_stage0_feedback_row = r_feedback_buf_valid;

                    for (ti = 0; ti < degree; ti = ti + 1) begin : gen_terms
                        wire [src_idx_width - 1 : 0] w_src_row;
                        wire [num_rows - 1 : 0] w_src_mask;
                        assign w_src_row =
                            i_src_row_idx_rows[(ri * degree + ti) *
                                src_idx_width +: src_idx_width];
                        assign w_src_mask =
                            r_src_onehot_terms[(ri * degree + ti) *
                                num_rows +: num_rows];
                        assign w_stage_state_p_terms[(si * num_rows + ri) *
                            degree + ti] =
                            w_stage0_feedback_row
                                ? r_feedback_terms_p[ri * degree + ti]
                                : ((source_onehot != 0)
                                    ? |(i_stage0_state_digit_p_rows & w_src_mask)
                                    : ((w_src_row < num_rows)
                                        ? i_stage0_state_digit_p_rows[w_src_row]
                                        : 1'b0));
                        assign w_stage_state_n_terms[(si * num_rows + ri) *
                            degree + ti] =
                            w_stage0_feedback_row
                                ? r_feedback_terms_n[ri * degree + ti]
                                : ((source_onehot != 0)
                                    ? |(i_stage0_state_digit_n_rows & w_src_mask)
                                    : ((w_src_row < num_rows)
                                        ? i_stage0_state_digit_n_rows[w_src_row]
                                        : 1'b0));
                    end
                end
            end else begin : gen_prev_stage_source
                assign w_stage_input_valid[si] =
                    o_stage_valid_rows[(si - 1) * num_rows + 0];
                assign w_stage_digit_idx[si * digit_idx_width +: digit_idx_width] =
                    o_stage_digit_idx_rows[(si - 1) * num_rows *
                        digit_idx_width +: digit_idx_width];
                assign w_stage_start[si] =
                    w_stage_input_valid[si] &&
                    (w_stage_digit_idx[si * digit_idx_width +: digit_idx_width] ==
                     {digit_idx_width{1'b0}});

                for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
                    localparam integer dest_group =
                        ri / stage_digit_group_size;

                    for (ti = 0; ti < degree; ti = ti + 1) begin : gen_terms
                        wire [src_idx_width - 1 : 0] w_src_row;
                        wire [num_rows - 1 : 0] w_src_mask;
                        wire [num_rows - 1 : 0] w_prev_group_p;
                        wire [num_rows - 1 : 0] w_prev_group_n;
                        assign w_src_row =
                            i_src_row_idx_rows[(ri * degree + ti) *
                                src_idx_width +: src_idx_width];
                        assign w_src_mask =
                            r_src_onehot_terms[(ri * degree + ti) *
                                num_rows +: num_rows];
                        assign w_prev_group_p =
                            w_stage_digit_p_group_rows[
                                ((si - 1) * stage_digit_groups + dest_group) *
                                num_rows +: num_rows];
                        assign w_prev_group_n =
                            w_stage_digit_n_group_rows[
                                ((si - 1) * stage_digit_groups + dest_group) *
                                num_rows +: num_rows];
                        assign w_stage_state_p_terms[(si * num_rows + ri) *
                            degree + ti] =
                            (source_onehot != 0)
                                ? |(w_prev_group_p & w_src_mask)
                                : ((w_src_row < num_rows)
                                    ? w_prev_group_p[w_src_row]
                                    : 1'b0);
                        assign w_stage_state_n_terms[(si * num_rows + ri) *
                            degree + ti] =
                            (source_onehot != 0)
                                ? |(w_prev_group_n & w_src_mask)
                                : ((w_src_row < num_rows)
                                    ? w_prev_group_n[w_src_row]
                                    : 1'b0);
                    end
                end
            end

            iter_parallel_in_online_mma8_stage_cluster #(
                .num_rows(num_rows),
                .degree(degree),
                .physical_degree(physical_degree),
                .bit_width(bit_width),
                .data_width(data_width),
                .bias_width(bias_width),
                .online_delay(online_delay),
                .acc_width(core_acc_width),
                .fast2_core(fast2_core),
                .estimate_selector(estimate_selector),
                .estimate_frac_bits(estimate_frac_bits),
                .estimate_guard_bits(estimate_guard_bits),
                .split_estimate(split_estimate),
                .redundant_residual(redundant_residual),
                .nonnegative_coeff(nonnegative_coeff),
                .nonnegative_bias(nonnegative_bias),
                .stallable_input(0),
                .output_groups(stage_digit_groups),
                .digit_idx_width(digit_idx_width)
            ) stage_cluster (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_clear(i_clear || r_stage_local_clear[si]),
                .i_clear_rows(r_stage_local_clear_rows[si * num_rows +:
                    num_rows]),
                .i_start(w_stage_start[si]),
                .i_valid_digit(w_stage_input_valid[si]),
                .i_digit_idx(w_stage_digit_idx[si * digit_idx_width +:
                    digit_idx_width]),
                .i_state_digit_p_terms_rows(w_stage_state_p_terms[
                    si * num_rows * degree +: num_rows * degree]),
                .i_state_digit_n_terms_rows(w_stage_state_n_terms[
                    si * num_rows * degree +: num_rows * degree]),
                .i_coeff_p_terms_rows(i_coeff_p_terms_rows),
                .i_coeff_n_terms_rows(i_coeff_n_terms_rows),
                .i_bias_p_rows(i_bias_p_rows),
                .i_bias_n_rows(i_bias_n_rows),
                .o_commit_valid_rows(o_stage_valid_rows[si * num_rows +:
                    num_rows]),
                .o_commit_digit_idx_rows(o_stage_digit_idx_rows[si * num_rows *
                    digit_idx_width +: num_rows * digit_idx_width]),
                .o_commit_digit_p_rows(o_stage_digit_p_rows[si * num_rows +:
                    num_rows]),
                .o_commit_digit_n_rows(o_stage_digit_n_rows[si * num_rows +:
                    num_rows]),
                .o_commit_digit_p_group_rows(w_stage_digit_p_group_rows[
                    si * stage_digit_groups * num_rows +:
                    stage_digit_groups * num_rows]),
                .o_commit_digit_n_group_rows(w_stage_digit_n_group_rows[
                    si * stage_digit_groups * num_rows +:
                    stage_digit_groups * num_rows]),
                .o_commit_done_rows(o_stage_done_rows[si * num_rows +:
                    num_rows]),
                .o_busy(w_stage_busy[si])
            );
        end
    endgenerate

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            r_external_active <= 1'b0;
            r_external_count <= {digit_idx_width{1'b0}};
            r_feedback_operand_active <= 1'b0;
            r_feedback_count <= {digit_idx_width{1'b0}};
            r_stop_requested <= 1'b0;
            r_fifo_wr_ptr <= {fifo_ptr_width{1'b0}};
            r_fifo_rd_ptr <= {fifo_ptr_width{1'b0}};
            r_fifo_count <= {fifo_count_width{1'b0}};
            r_feedback_buf_valid <= 1'b0;
            r_feedback_buf_idx <= {digit_idx_width{1'b0}};
            r_feedback_buf_first <= 1'b0;
            r_feedback_buf_p <= {num_rows{1'b0}};
            r_feedback_buf_n <= {num_rows{1'b0}};
            r_feedback_terms_p <= {num_rows * degree{1'b0}};
            r_feedback_terms_n <= {num_rows * degree{1'b0}};
            r_src_onehot_terms <= {num_rows * degree * num_rows{1'b0}};
            o_stage_valid_count <= {num_stages * 32{1'b0}};
            o_stage_linf_valid_count <= {num_stages * 32{1'b0}};
            o_stage_linf_delta <= {num_stages * acc_width{1'b0}};
            o_stage_linf_valid <= {num_stages{1'b0}};
            o_stage_done <= {num_stages{1'b0}};
            o_stage_started_before_prev_done <= {(num_stages - 1){1'b0}};
            o_superstep_count <= 32'd0;
            o_feedback_fifo_stall <= 32'd0;
            o_cert_late_cycles <= 32'd0;
            o_converged_stage_histogram <= {num_stages * 32{1'b0}};
            o_speculative_kill_digits <= 32'd0;
            o_converged <= 1'b0;
            o_converged_stage <= {converged_stage_width{1'b0}};
            r_linf_pending <= {num_stages{1'b0}};
            r_linf_abs_valid <= {num_stages{1'b0}};
            r_linf_group_valid <= {num_stages{1'b0}};
            r_linf_mid_valid <= {num_stages{1'b0}};
            r_linf_global_valid <= {num_stages{1'b0}};
            r_stage_local_clear <= {num_stages{1'b0}};
            r_stage_local_clear_rows <= {num_stages * num_rows{1'b0}};
            for (fifo_i = 0; fifo_i < feedback_fifo_depth; fifo_i = fifo_i + 1) begin
                r_fifo_idx[fifo_i] <= {digit_idx_width{1'b0}};
                r_fifo_p[fifo_i] <= {num_rows{1'b0}};
                r_fifo_n[fifo_i] <= {num_rows{1'b0}};
            end
            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                r_stage_old_p[si_seq] <= {num_rows * data_width{1'b0}};
                r_stage_old_n[si_seq] <= {num_rows * data_width{1'b0}};
                r_stage_new_p[si_seq] <= {num_rows * data_width{1'b0}};
                r_stage_new_n[si_seq] <= {num_rows * data_width{1'b0}};
                r_linf_global_max[si_seq] <= 32'd0;
                for (ri_seq = 0; ri_seq < num_rows; ri_seq = ri_seq + 1) begin
                    r_stage_old_value[si_seq][ri_seq] <= {(data_width + 1){1'b0}};
                    r_stage_new_value[si_seq][ri_seq] <= {(data_width + 1){1'b0}};
                    r_linf_abs_delta[si_seq][ri_seq] <= 32'd0;
                end
                for (group_idx = 0; group_idx < linf_num_groups; group_idx = group_idx + 1) begin
                    r_linf_group_max[si_seq][group_idx] <= 32'd0;
                end
                for (mid_idx = 0; mid_idx < linf_num_mid_groups; mid_idx = mid_idx + 1) begin
                    r_linf_mid_max[si_seq][mid_idx] <= 32'd0;
                end
            end
        end else begin
            o_stage_linf_valid <= {num_stages{1'b0}};
            r_stage_local_clear <= {num_stages{1'b0}};
            r_stage_local_clear_rows <= {num_stages * num_rows{1'b0}};

            for (src_dec_row_idx = 0; src_dec_row_idx < num_rows;
                 src_dec_row_idx = src_dec_row_idx + 1) begin
                for (src_dec_term_idx = 0; src_dec_term_idx < degree;
                     src_dec_term_idx = src_dec_term_idx + 1) begin
                    src_dec_row_value =
                        i_src_row_idx_rows[(src_dec_row_idx * degree +
                            src_dec_term_idx) * src_idx_width +:
                            src_idx_width];
                    r_src_onehot_terms[(src_dec_row_idx * degree +
                        src_dec_term_idx) * num_rows +: num_rows] <=
                        {num_rows{1'b0}};
                    if (src_dec_row_value < num_rows) begin
                        r_src_onehot_terms[(src_dec_row_idx * degree +
                            src_dec_term_idx) * num_rows +
                            src_dec_row_value] <= 1'b1;
                    end
                end
            end

            if (i_start) begin
                r_external_active <= 1'b1;
                r_external_count <= {digit_idx_width{1'b0}};
            end

            if (i_valid_digit && (r_external_active || i_start)) begin
                if ((r_external_active ? r_external_count :
                    {digit_idx_width{1'b0}}) == data_width - 1) begin
                    r_external_active <= 1'b0;
                    r_external_count <= {digit_idx_width{1'b0}};
                end else begin
                    r_external_count <= (r_external_active ? r_external_count :
                        {digit_idx_width{1'b0}}) + 1'b1;
                end
            end

            if (w_feedback_start) begin
                r_feedback_operand_active <= 1'b1;
                r_feedback_count <= {digit_idx_width{1'b0}};
            end

            if (w_feedback_consume) begin
                if (r_feedback_count == data_width - 1) begin
                    r_feedback_operand_active <= 1'b0;
                    r_feedback_count <= {digit_idx_width{1'b0}};
                end else begin
                    r_feedback_count <= r_feedback_count + 1'b1;
                end
            end else if ((r_feedback_operand_active || w_feedback_start) &&
                         !r_feedback_buf_valid) begin
                o_feedback_fifo_stall <= o_feedback_fifo_stall + 1'b1;
            end

            if (w_final_valid && !r_stop_requested) begin
                if (w_fifo_has_room) begin
                    r_fifo_idx[r_fifo_wr_ptr] <=
                        o_final_digit_idx_rows[digit_idx_width - 1 : 0];
                    r_fifo_p[r_fifo_wr_ptr] <= o_final_digit_p_rows;
                    r_fifo_n[r_fifo_wr_ptr] <= o_final_digit_n_rows;
                    r_fifo_wr_ptr <= r_fifo_wr_ptr + 1'b1;
                end else begin
                    o_feedback_fifo_stall <= o_feedback_fifo_stall + 1'b1;
                end
            end else if (w_final_valid && r_stop_requested) begin
                o_speculative_kill_digits <= o_speculative_kill_digits + 1'b1;
            end

            if (w_feedback_buf_fill) begin
                r_feedback_buf_valid <= 1'b1;
                r_feedback_buf_idx <= w_fifo_head_idx;
                r_feedback_buf_first <=
                    (w_fifo_head_idx == {digit_idx_width{1'b0}});
                r_feedback_buf_p <= w_fifo_head_p;
                r_feedback_buf_n <= w_fifo_head_n;
                for (fb_row_idx = 0; fb_row_idx < num_rows;
                     fb_row_idx = fb_row_idx + 1) begin
                    for (fb_term_idx = 0; fb_term_idx < degree;
                         fb_term_idx = fb_term_idx + 1) begin
                        fb_src_row =
                            i_src_row_idx_rows[(fb_row_idx * degree +
                                fb_term_idx) * src_idx_width +: src_idx_width];
                        if (fb_src_row < num_rows) begin
                            r_feedback_terms_p[fb_row_idx * degree +
                                fb_term_idx] <= w_fifo_head_p[fb_src_row];
                            r_feedback_terms_n[fb_row_idx * degree +
                                fb_term_idx] <= w_fifo_head_n[fb_src_row];
                        end else begin
                            r_feedback_terms_p[fb_row_idx * degree +
                                fb_term_idx] <= 1'b0;
                            r_feedback_terms_n[fb_row_idx * degree +
                                fb_term_idx] <= 1'b0;
                        end
                    end
                end
                r_fifo_rd_ptr <= r_fifo_rd_ptr + 1'b1;
            end else if (w_feedback_consume) begin
                r_feedback_buf_valid <= 1'b0;
            end

            case ({w_fifo_write, w_feedback_buf_fill})
                2'b10: r_fifo_count <= r_fifo_count + 1'b1;
                2'b01: r_fifo_count <= r_fifo_count - 1'b1;
                default: r_fifo_count <= r_fifo_count;
            endcase

            if (w_final_done) begin
                o_superstep_count <= o_superstep_count + 1'b1;
            end

            if ((|r_linf_pending) || (|r_linf_abs_valid) ||
                (|r_linf_group_valid) || (|r_linf_mid_valid) ||
                (|r_linf_global_valid)) begin
                o_cert_late_cycles <= o_cert_late_cycles + 1'b1;
            end

            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (si_seq > 0 && w_stage_start[si_seq] &&
                    !o_stage_done[si_seq - 1]) begin
                    o_stage_started_before_prev_done[si_seq - 1] <= 1'b1;
                end

                if (o_stage_valid_rows[si_seq * num_rows + 0]) begin
                    o_stage_valid_count[si_seq * 32 +: 32] <=
                        o_stage_valid_count[si_seq * 32 +: 32] + 1'b1;
                end

                if (o_stage_done_rows[si_seq * num_rows + 0]) begin
                    o_stage_done[si_seq] <= 1'b1;
                    r_linf_pending[si_seq] <= 1'b1;
                    r_stage_local_clear[si_seq] <= 1'b1;
                    r_stage_local_clear_rows[si_seq * num_rows +:
                        num_rows] <= {num_rows{1'b1}};
                end
            end

            if (w_stage_input_valid[0]) begin
                bit_sel_seq = data_width - 1 -
                    w_stage_digit_idx[0 +: digit_idx_width];
                for (ri_seq = 0; ri_seq < num_rows; ri_seq = ri_seq + 1) begin
                    r_stage_old_p[0][ri_seq * data_width + bit_sel_seq] <=
                        w_stage0_source_p_rows[ri_seq];
                    r_stage_old_n[0][ri_seq * data_width + bit_sel_seq] <=
                        w_stage0_source_n_rows[ri_seq];
                    digit_value = sd_digit_value(
                        w_stage0_source_p_rows[ri_seq],
                        w_stage0_source_n_rows[ri_seq]);
                    if (w_stage_digit_idx[0 +: digit_idx_width] ==
                        {digit_idx_width{1'b0}}) begin
                        r_stage_old_value[0][ri_seq] <= digit_value;
                    end else begin
                        r_stage_old_value[0][ri_seq] <=
                            (r_stage_old_value[0][ri_seq] <<< 1) + digit_value;
                    end
                end
            end

            for (si_seq = 1; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (o_stage_valid_rows[(si_seq - 1) * num_rows + 0]) begin
                    bit_sel_seq = data_width - 1 -
                        o_stage_digit_idx_rows[(si_seq - 1) * num_rows *
                            digit_idx_width +: digit_idx_width];
                    for (ri_seq = 0; ri_seq < num_rows; ri_seq = ri_seq + 1) begin
                        r_stage_old_p[si_seq][ri_seq * data_width +
                            bit_sel_seq] <=
                            o_stage_digit_p_rows[(si_seq - 1) * num_rows +
                                ri_seq];
                        r_stage_old_n[si_seq][ri_seq * data_width +
                            bit_sel_seq] <=
                            o_stage_digit_n_rows[(si_seq - 1) * num_rows +
                                ri_seq];
                        digit_value = sd_digit_value(
                            o_stage_digit_p_rows[(si_seq - 1) * num_rows +
                                ri_seq],
                            o_stage_digit_n_rows[(si_seq - 1) * num_rows +
                                ri_seq]);
                        if (o_stage_digit_idx_rows[(si_seq - 1) * num_rows *
                            digit_idx_width +: digit_idx_width] ==
                            {digit_idx_width{1'b0}}) begin
                            r_stage_old_value[si_seq][ri_seq] <= digit_value;
                        end else begin
                            r_stage_old_value[si_seq][ri_seq] <=
                                (r_stage_old_value[si_seq][ri_seq] <<< 1) +
                                digit_value;
                        end
                    end
                end
            end

            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (o_stage_valid_rows[si_seq * num_rows + 0]) begin
                    bit_sel_seq = data_width - 1 -
                        o_stage_digit_idx_rows[si_seq * num_rows *
                            digit_idx_width +: digit_idx_width];
                    for (ri_seq = 0; ri_seq < num_rows; ri_seq = ri_seq + 1) begin
                        r_stage_new_p[si_seq][ri_seq * data_width +
                            bit_sel_seq] <=
                            o_stage_digit_p_rows[si_seq * num_rows + ri_seq];
                        r_stage_new_n[si_seq][ri_seq * data_width +
                            bit_sel_seq] <=
                            o_stage_digit_n_rows[si_seq * num_rows + ri_seq];
                        digit_value = sd_digit_value(
                            o_stage_digit_p_rows[si_seq * num_rows + ri_seq],
                            o_stage_digit_n_rows[si_seq * num_rows + ri_seq]);
                        if (o_stage_digit_idx_rows[si_seq * num_rows *
                            digit_idx_width +: digit_idx_width] ==
                            {digit_idx_width{1'b0}}) begin
                            r_stage_new_value[si_seq][ri_seq] <= digit_value;
                        end else begin
                            r_stage_new_value[si_seq][ri_seq] <=
                                (r_stage_new_value[si_seq][ri_seq] <<< 1) +
                                digit_value;
                        end
                    end
                end
            end

            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (r_linf_pending[si_seq]) begin
                    for (ri_seq = 0; ri_seq < num_rows; ri_seq = ri_seq + 1) begin
                        row_new_value = r_stage_new_value[si_seq][ri_seq];
                        row_old_value = r_stage_old_value[si_seq][ri_seq];
                        row_delta_value = row_new_value - row_old_value;
                        if (row_delta_value < 0) begin
                            row_delta_value = -row_delta_value;
                        end
                        r_linf_abs_delta[si_seq][ri_seq] <= row_delta_value[31:0];
                    end
                    r_linf_abs_valid[si_seq] <= 1'b1;
                    r_linf_pending[si_seq] <= 1'b0;
                end
            end

            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (r_linf_abs_valid[si_seq]) begin
                    for (group_idx = 0; group_idx < linf_num_groups;
                         group_idx = group_idx + 1) begin
                        group_max_next = 0;
                        group_base = group_idx * linf_group_size;
                        for (ri_seq = 0; ri_seq < linf_group_size;
                             ri_seq = ri_seq + 1) begin
                            if ((group_base + ri_seq) < num_rows &&
                                r_linf_abs_delta[si_seq][group_base + ri_seq] >
                                    group_max_next[31:0]) begin
                                group_max_next =
                                    r_linf_abs_delta[si_seq][group_base + ri_seq];
                            end
                        end
                        r_linf_group_max[si_seq][group_idx] <=
                            group_max_next[31:0];
                    end
                    r_linf_group_valid[si_seq] <= 1'b1;
                    r_linf_abs_valid[si_seq] <= 1'b0;
                end
            end

            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (r_linf_group_valid[si_seq]) begin
                    for (mid_idx = 0; mid_idx < linf_num_mid_groups;
                         mid_idx = mid_idx + 1) begin
                        group_max_next = 0;
                        mid_base = mid_idx * linf_mid_group_size;
                        for (group_idx = 0; group_idx < linf_mid_group_size;
                             group_idx = group_idx + 1) begin
                            if ((mid_base + group_idx) < linf_num_groups &&
                                r_linf_group_max[si_seq][mid_base + group_idx] >
                                    group_max_next[31:0]) begin
                                group_max_next =
                                    r_linf_group_max[si_seq][mid_base + group_idx];
                            end
                        end
                        r_linf_mid_max[si_seq][mid_idx] <=
                            group_max_next[31:0];
                    end
                    r_linf_mid_valid[si_seq] <= 1'b1;
                    r_linf_group_valid[si_seq] <= 1'b0;
                end
            end

            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (r_linf_mid_valid[si_seq]) begin
                    row_linf_next = 0;
                    for (mid_idx = 0; mid_idx < linf_num_mid_groups;
                         mid_idx = mid_idx + 1) begin
                        if (r_linf_mid_max[si_seq][mid_idx] >
                            row_linf_next[31:0]) begin
                            row_linf_next =
                                r_linf_mid_max[si_seq][mid_idx];
                        end
                    end
                    r_linf_global_max[si_seq] <= row_linf_next[31:0];
                    r_linf_global_valid[si_seq] <= 1'b1;
                    r_linf_mid_valid[si_seq] <= 1'b0;
                end
            end

            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (r_linf_global_valid[si_seq]) begin
                    o_stage_linf_delta[si_seq * acc_width +: acc_width] <=
                        {{(acc_width - 32){1'b0}}, r_linf_global_max[si_seq]};
                    o_stage_linf_valid[si_seq] <= 1'b1;
                    o_stage_linf_valid_count[si_seq * 32 +: 32] <=
                        o_stage_linf_valid_count[si_seq * 32 +: 32] + 1'b1;
                    r_linf_global_valid[si_seq] <= 1'b0;

                    if (!o_converged &&
                        (r_linf_global_max[si_seq] <= i_linf_eta)) begin
                        o_converged <= 1'b1;
                        o_converged_stage <=
                            si_seq[converged_stage_width - 1 : 0];
                        o_converged_stage_histogram[si_seq * 32 +: 32] <=
                            o_converged_stage_histogram[si_seq * 32 +: 32] +
                            1'b1;
                        if (i_stop_on_converged) begin
                            r_stop_requested <= 1'b1;
                            o_speculative_kill_digits <=
                            o_speculative_kill_digits + r_fifo_count;
                            r_fifo_count <= {fifo_count_width{1'b0}};
                            r_fifo_rd_ptr <= r_fifo_wr_ptr;
                            r_feedback_buf_valid <= 1'b0;
                            r_feedback_buf_first <= 1'b0;
                            r_feedback_operand_active <= 1'b0;
                        end
                    end
                end
            end
        end
    end

endmodule
