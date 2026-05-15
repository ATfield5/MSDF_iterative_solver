`timescale 1ns / 1ps

// One P3-SP PageRank stage.  It feeds DATA_WIDTH state/bias digits and then
// ONLINE_DELAY zero-flush cycles.  The core emits DATA_WIDTH committed output
// digits, which can directly drive the next wavefront stage.

module iter_parallel_in_online_mma8_stage_cluster #(
    parameter integer num_rows = 32,
    parameter integer degree = 4,
    parameter integer physical_degree = 8,
    parameter integer bit_width = 30,
    parameter integer data_width = 32,
    parameter integer bias_width = bit_width + 2,
    parameter integer online_delay = 2,
    parameter integer acc_width = 36,
    parameter integer fast2_core = 0,
    parameter integer estimate_selector = 0,
    parameter integer estimate_frac_bits = 6,
    parameter integer estimate_guard_bits = 2,
    parameter integer split_estimate = 1,
    parameter integer redundant_residual = 0,
    parameter integer nonnegative_coeff = 0,
    parameter integer nonnegative_bias = 0,
    parameter integer stallable_input = 1,
    parameter integer output_groups = 1,
    parameter integer feed_cycles = data_width + online_delay,
    parameter integer feed_idx_width = (feed_cycles <= 2) ? 1 : $clog2(feed_cycles + 1),
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_clear,
    input      [num_rows - 1 : 0]                       i_clear_rows,
    input                                               i_start,
    input                                               i_valid_digit,
    input      [digit_idx_width - 1 : 0]                i_digit_idx,
    input      [num_rows * degree - 1 : 0]              i_state_digit_p_terms_rows,
    input      [num_rows * degree - 1 : 0]              i_state_digit_n_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]  i_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]  i_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]          i_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]          i_bias_n_rows,
    output     [num_rows - 1 : 0]                       o_commit_valid_rows,
    output     [num_rows * digit_idx_width - 1 : 0]     o_commit_digit_idx_rows,
    output     [num_rows - 1 : 0]                       o_commit_digit_p_rows,
    output     [num_rows - 1 : 0]                       o_commit_digit_n_rows,
    output     [output_groups * num_rows - 1 : 0]       o_commit_digit_p_group_rows,
    output     [output_groups * num_rows - 1 : 0]       o_commit_digit_n_group_rows,
    output     [num_rows - 1 : 0]                       o_commit_done_rows,
    (* max_fanout = 8 *) output reg                     o_busy
);

    (* max_fanout = 8 *) reg [feed_idx_width - 1 : 0] r_feed_idx;
    reg [digit_idx_width - 1 : 0] r_capture_idx;

    wire w_starting;
    (* max_fanout = 8 *) wire w_busy_or_start;
    (* max_fanout = 8 *) wire [feed_idx_width - 1 : 0] w_feed_idx;
    (* max_fanout = 8 *) wire w_operand_phase;
    (* max_fanout = 8 *) wire w_input_ready;
    (* max_fanout = 8 *) wire w_feed_active;
    wire [digit_idx_width - 1 : 0] w_local_operand_digit_idx;
    (* max_fanout = 8 *) wire [digit_idx_width - 1 : 0] w_operand_digit_idx;
    wire [num_rows - 1 : 0] w_core_valid_rows;
    wire w_capture_sample;
    wire w_capture_last;

    assign w_starting = i_start && !o_busy;
    assign w_busy_or_start = o_busy || w_starting;
    assign w_feed_idx = w_starting ? {feed_idx_width{1'b0}} : r_feed_idx;
    assign w_operand_phase = w_feed_idx < data_width;
    assign w_input_ready =
        (stallable_input != 0) ? ((!w_operand_phase) || i_valid_digit) : 1'b1;
    assign w_feed_active =
        w_busy_or_start &&
        (w_feed_idx < feed_cycles) &&
        w_input_ready;
    assign w_local_operand_digit_idx =
        w_feed_idx[digit_idx_width - 1 : 0];
    assign w_operand_digit_idx = w_operand_phase
        ? ((stallable_input != 0) ? i_digit_idx : w_local_operand_digit_idx)
        : {digit_idx_width{1'b0}};
    assign w_capture_sample = w_core_valid_rows[0] && (r_capture_idx < data_width);
    assign w_capture_last = w_capture_sample && (r_capture_idx == data_width - 1);
    assign o_commit_valid_rows = {num_rows{w_capture_sample}};
    assign o_commit_done_rows = {num_rows{w_capture_last}};

    genvar ri;
    genvar ti;
    genvar gi;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
            wire [physical_degree - 1 : 0] w_state_digit_p_terms;
            wire [physical_degree - 1 : 0] w_state_digit_n_terms;
            wire [physical_degree * bit_width - 1 : 0] w_coeff_p_terms;
            wire [physical_degree * bit_width - 1 : 0] w_coeff_n_terms;
            wire w_bias_digit_p;
            wire w_bias_digit_n;
            wire w_core_z_p;
            wire w_core_z_n;
            wire [output_groups - 1 : 0] w_core_z_p_groups;
            wire [output_groups - 1 : 0] w_core_z_n_groups;
            integer bit_sel;

            always @(*) begin
                bit_sel = data_width - 1 - w_operand_digit_idx;
            end

            for (ti = 0; ti < physical_degree; ti = ti + 1) begin : gen_terms
                if (ti < degree) begin : gen_real_term
                    assign w_state_digit_p_terms[ti] =
                        (w_operand_phase &&
                         ((stallable_input == 0) || i_valid_digit))
                            ? i_state_digit_p_terms_rows[ri * degree + ti]
                            : 1'b0;
                    assign w_state_digit_n_terms[ti] =
                        (w_operand_phase &&
                         ((stallable_input == 0) || i_valid_digit))
                            ? i_state_digit_n_terms_rows[ri * degree + ti]
                            : 1'b0;
                    assign w_coeff_p_terms[ti * bit_width +: bit_width] =
                        i_coeff_p_terms_rows[(ri * degree + ti) * bit_width +: bit_width];
                    assign w_coeff_n_terms[ti * bit_width +: bit_width] =
                        i_coeff_n_terms_rows[(ri * degree + ti) * bit_width +: bit_width];
                end else begin : gen_zero_term
                    assign w_state_digit_p_terms[ti] = 1'b0;
                    assign w_state_digit_n_terms[ti] = 1'b0;
                    assign w_coeff_p_terms[ti * bit_width +: bit_width] = {bit_width{1'b0}};
                    assign w_coeff_n_terms[ti * bit_width +: bit_width] = {bit_width{1'b0}};
                end
            end

            assign w_bias_digit_p =
                (w_operand_phase && ((stallable_input == 0) || i_valid_digit))
                    ? i_bias_p_rows[ri * bias_width + bit_sel]
                    : 1'b0;
            assign w_bias_digit_n =
                (w_operand_phase && ((stallable_input == 0) || i_valid_digit))
                    ? i_bias_n_rows[ri * bias_width + bit_sel]
                    : 1'b0;

            if (fast2_core != 0) begin : gen_fast2_core
                iter_parallel_in_online_mma8_frac_core_fast2 #(
                    .physical_degree(physical_degree),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .frac_bits(data_width - 1),
                    .online_delay(online_delay),
                    .acc_width(acc_width),
                    .feed_count_width(feed_idx_width),
                    .output_groups(output_groups),
                    .estimate_selector(estimate_selector),
                    .estimate_frac_bits(estimate_frac_bits),
                    .estimate_guard_bits(estimate_guard_bits),
                    .split_estimate(split_estimate),
                    .redundant_residual(redundant_residual),
                    .nonnegative_coeff(nonnegative_coeff),
                    .nonnegative_bias(nonnegative_bias)
                ) sp_core (
                    .i_clk(i_clk),
                    .i_rst(i_rst || i_clear_rows[ri]),
                    .i_ena(w_feed_active),
                    .i_x_p(w_state_digit_p_terms),
                    .i_x_n(w_state_digit_n_terms),
                    .i_coeff_p(w_coeff_p_terms),
                    .i_coeff_n(w_coeff_n_terms),
                    .i_bias_p(w_bias_digit_p),
                    .i_bias_n(w_bias_digit_n),
                    .o_z_p(w_core_z_p),
                    .o_z_n(w_core_z_n),
                    .o_valid(w_core_valid_rows[ri]),
                    .o_z_p_groups(w_core_z_p_groups),
                    .o_z_n_groups(w_core_z_n_groups)
                );
            end else begin : gen_base_core
                iter_parallel_in_online_mma8_frac_core #(
                    .physical_degree(physical_degree),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .frac_bits(data_width - 1),
                    .online_delay(online_delay),
                    .acc_width(acc_width),
                    .feed_count_width(feed_idx_width),
                    .output_groups(output_groups),
                    .nonnegative_coeff(nonnegative_coeff),
                    .nonnegative_bias(nonnegative_bias)
                ) sp_core (
                    .i_clk(i_clk),
                    .i_rst(i_rst || i_clear_rows[ri]),
                    .i_ena(w_feed_active),
                    .i_x_p(w_state_digit_p_terms),
                    .i_x_n(w_state_digit_n_terms),
                    .i_coeff_p(w_coeff_p_terms),
                    .i_coeff_n(w_coeff_n_terms),
                    .i_bias_p(w_bias_digit_p),
                    .i_bias_n(w_bias_digit_n),
                    .o_z_p(w_core_z_p),
                    .o_z_n(w_core_z_n),
                    .o_valid(w_core_valid_rows[ri]),
                    .o_z_p_groups(w_core_z_p_groups),
                    .o_z_n_groups(w_core_z_n_groups)
                );
            end

            assign o_commit_digit_idx_rows[(ri + 1) * digit_idx_width - 1 -:
                digit_idx_width] = r_capture_idx;
            assign o_commit_digit_p_rows[ri] = w_core_z_p;
            assign o_commit_digit_n_rows[ri] = w_core_z_n;

            for (gi = 0; gi < output_groups; gi = gi + 1) begin : gen_group_outputs
                assign o_commit_digit_p_group_rows[gi * num_rows + ri] =
                    w_core_z_p_groups[gi];
                assign o_commit_digit_n_group_rows[gi * num_rows + ri] =
                    w_core_z_n_groups[gi];
            end
        end
    endgenerate

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            o_busy <= 1'b0;
            r_feed_idx <= {feed_idx_width{1'b0}};
            r_capture_idx <= {digit_idx_width{1'b0}};
        end else begin
            if (w_starting) begin
                o_busy <= 1'b1;
                r_feed_idx <= w_feed_active
                    ? {{(feed_idx_width - 1){1'b0}}, 1'b1}
                    : {feed_idx_width{1'b0}};
                r_capture_idx <= {digit_idx_width{1'b0}};
            end else if (o_busy) begin
                if (w_feed_active) begin
                    r_feed_idx <= r_feed_idx + 1'b1;
                end

                if (w_capture_sample) begin
                    r_capture_idx <= r_capture_idx + 1'b1;
                end

                if (w_capture_last) begin
                    o_busy <= 1'b0;
                end
            end
        end
    end

endmodule
