`timescale 1ns / 1ps

// One prior-operator digit-stream PageRank stage.
//
// This stage keeps the original MSDF_MUL_ADD_8 recurrence but exposes a
// committed digit-stream output instead of assembling a full word.  It is meant
// to be cascaded: stage s+1 can consume o_commit_digit_* from stage s as soon
// as the first committed digit is available.
//
// Contract:
//   - The operator is reset by i_rst/i_clear before a super-step.
//   - i_start may be asserted in the same cycle as the first input digit.
//   - The first DATA_WIDTH input digits are operand digits.
//   - The stage then autonomously feeds zero flush digits until DATA_WIDTH
//     output digits have been captured from the prior operator's fraction
//     stream.

module iter_prior_online_mma8_stream_stage_cluster #(
    parameter integer num_rows = 32,
    parameter integer degree = 4,
    parameter integer bit_width = 11,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer capture_unit = 0,
    parameter integer feed_cycles = data_width + data_width + 8,
    parameter integer valid_latency = 4,
    parameter integer feed_idx_width = (feed_cycles <= 2) ? 1 : $clog2(feed_cycles + 1),
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_clear,
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
    output     [num_rows - 1 : 0]                       o_commit_done_rows,
    output reg                                          o_busy
);

    reg [feed_idx_width - 1 : 0] r_feed_idx;
    reg [digit_idx_width - 1 : 0] r_capture_idx;
    reg [valid_latency : 0] r_feed_valid_pipe;

    wire w_starting;
    wire w_busy_or_start;
    wire [feed_idx_width - 1 : 0] w_feed_idx;
    wire w_operand_phase;
    wire w_feed_active;
    wire [digit_idx_width - 1 : 0] w_operand_digit_idx;
    wire w_capture_flag;
    wire w_capture_sample;
    wire w_capture_last;
    wire [num_rows - 1 : 0] w_prior_z_p_rows;
    wire [num_rows - 1 : 0] w_prior_z_n_rows;
    wire [num_rows - 1 : 0] w_prior_unit_rows;
    wire [num_rows - 1 : 0] w_prior_frac_rows;

    assign w_starting = i_start && !o_busy;
    assign w_busy_or_start = o_busy || w_starting;
    assign w_feed_idx = w_starting ? {feed_idx_width{1'b0}} : r_feed_idx;
    assign w_operand_phase = w_feed_idx < data_width;
    assign w_feed_active =
        w_busy_or_start &&
        (w_feed_idx < feed_cycles) &&
        ((!w_operand_phase) || i_valid_digit);
    assign w_operand_digit_idx = w_operand_phase
        ? i_digit_idx
        : {digit_idx_width{1'b0}};
    assign w_capture_flag =
        ((capture_unit != 0) && w_prior_unit_rows[0]) || w_prior_frac_rows[0];
    assign w_capture_sample =
        r_feed_valid_pipe[valid_latency] &&
        w_capture_flag &&
        (r_capture_idx < data_width);
    assign w_capture_last = w_capture_sample && (r_capture_idx == data_width - 1);
    assign o_commit_valid_rows = {num_rows{w_capture_sample}};
    assign o_commit_done_rows = {num_rows{w_capture_last}};

    genvar ri;
    genvar ti;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
            wire [degree * data_width - 1 : 0] w_coeff_p_ext;
            wire [degree * data_width - 1 : 0] w_coeff_n_ext;
            wire [data_width - 1 : 0] w_bias_p_ext;
            wire [data_width - 1 : 0] w_bias_n_ext;
            wire [degree - 1 : 0] w_state_digit_p_terms;
            wire [degree - 1 : 0] w_state_digit_n_terms;
            wire w_bias_digit_p;
            wire w_bias_digit_n;
            integer bit_sel;

            for (ti = 0; ti < degree; ti = ti + 1) begin : gen_coeff_ext
                assign w_coeff_p_ext[ti * data_width +: data_width] =
                    {{(data_width - bit_width){1'b0}},
                     i_coeff_p_terms_rows[(ri * degree + ti) * bit_width +: bit_width]};
                assign w_coeff_n_ext[ti * data_width +: data_width] =
                    {{(data_width - bit_width){1'b0}},
                     i_coeff_n_terms_rows[(ri * degree + ti) * bit_width +: bit_width]};
            end

            assign w_bias_p_ext =
                {{(data_width - bias_width){1'b0}},
                 i_bias_p_rows[ri * bias_width +: bias_width]};
            assign w_bias_n_ext =
                {{(data_width - bias_width){1'b0}},
                 i_bias_n_rows[ri * bias_width +: bias_width]};

            always @(*) begin
                bit_sel = data_width - 1 - w_operand_digit_idx;
            end

            for (ti = 0; ti < degree; ti = ti + 1) begin : gen_state_terms
                assign w_state_digit_p_terms[ti] =
                    (w_operand_phase && i_valid_digit)
                        ? i_state_digit_p_terms_rows[ri * degree + ti]
                        : 1'b0;
                assign w_state_digit_n_terms[ti] =
                    (w_operand_phase && i_valid_digit)
                        ? i_state_digit_n_terms_rows[ri * degree + ti]
                        : 1'b0;
            end

            assign w_bias_digit_p =
                (w_operand_phase && i_valid_digit) ? w_bias_p_ext[bit_sel] : 1'b0;
            assign w_bias_digit_n =
                (w_operand_phase && i_valid_digit) ? w_bias_n_ext[bit_sel] : 1'b0;

            if (degree <= 8) begin : gen_prior_mma8_row
                iter_prior_online_mma8_row_kernel #(
                    .degree(degree),
                    .bit_width(data_width),
                    .digit_idx_width(digit_idx_width)
                ) prior_row (
                    .i_clk(i_clk),
                    .i_rst(i_rst || i_clear),
                    .i_valid_digit(w_feed_active),
                    .i_digit_idx(w_operand_digit_idx),
                    .i_state_digit_p_terms(w_state_digit_p_terms),
                    .i_state_digit_n_terms(w_state_digit_n_terms),
                    .i_coeff_p_terms(w_coeff_p_ext),
                    .i_coeff_n_terms(w_coeff_n_ext),
                    .i_bias_digit_p(w_bias_digit_p),
                    .i_bias_digit_n(w_bias_digit_n),
                    .o_z_p(w_prior_z_p_rows[ri]),
                    .o_z_n(w_prior_z_n_rows[ri]),
                    .o_int(),
                    .o_unit(w_prior_unit_rows[ri]),
                    .o_frac(w_prior_frac_rows[ri])
                );
            end else begin : gen_prior_mma32_row
                iter_prior_online_mma32_native_row_kernel #(
                    .degree(degree),
                    .bit_width(data_width),
                    .digit_idx_width(digit_idx_width)
                ) prior_row (
                    .i_clk(i_clk),
                    .i_rst(i_rst || i_clear),
                    .i_valid_digit(w_feed_active),
                    .i_digit_idx(w_operand_digit_idx),
                    .i_state_digit_p_terms(w_state_digit_p_terms),
                    .i_state_digit_n_terms(w_state_digit_n_terms),
                    .i_coeff_p_terms(w_coeff_p_ext),
                    .i_coeff_n_terms(w_coeff_n_ext),
                    .i_bias_digit_p(w_bias_digit_p),
                    .i_bias_digit_n(w_bias_digit_n),
                    .o_z_p(w_prior_z_p_rows[ri]),
                    .o_z_n(w_prior_z_n_rows[ri]),
                    .o_int(),
                    .o_unit(w_prior_unit_rows[ri]),
                    .o_frac(w_prior_frac_rows[ri])
                );
            end

            assign o_commit_digit_idx_rows[(ri + 1) * digit_idx_width - 1 -:
                digit_idx_width] = r_capture_idx;
            assign o_commit_digit_p_rows[ri] = w_prior_z_p_rows[ri];
            assign o_commit_digit_n_rows[ri] = w_prior_z_n_rows[ri];
        end
    endgenerate

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            o_busy <= 1'b0;
            r_feed_idx <= {feed_idx_width{1'b0}};
            r_capture_idx <= {digit_idx_width{1'b0}};
            r_feed_valid_pipe <= {(valid_latency + 1){1'b0}};
        end else begin
            r_feed_valid_pipe <= {
                r_feed_valid_pipe[valid_latency - 1 : 0],
                w_feed_active
            };

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

                if (w_capture_last ||
                    ((r_feed_idx == feed_cycles) &&
                     (r_feed_valid_pipe == {(valid_latency + 1){1'b0}}))) begin
                    o_busy <= 1'b0;
                end
            end
        end
    end

endmodule
