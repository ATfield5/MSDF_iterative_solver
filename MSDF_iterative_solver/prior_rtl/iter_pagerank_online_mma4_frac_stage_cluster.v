`timescale 1ns / 1ps

// PageRank fractional-only stage cluster using the 4-term v2 online core.
// It matches iter_prior_online_mma8_stream_stage_cluster's external stream
// contract, but each row physically instantiates a 4-term core rather than the
// original 8-slot operator.

module iter_pagerank_online_mma4_frac_stage_cluster #(
    parameter integer num_rows = 32,
    parameter integer degree = 4,
    parameter integer bit_width = 11,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer feed_cycles = data_width + data_width + 8,
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

    wire w_starting;
    wire w_busy_or_start;
    wire [feed_idx_width - 1 : 0] w_feed_idx;
    wire w_operand_phase;
    wire w_feed_active;
    wire [digit_idx_width - 1 : 0] w_operand_digit_idx;
    wire [num_rows - 1 : 0] w_core_frac_valid_rows;
    wire w_capture_sample;
    wire w_capture_last;

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
    assign w_capture_sample =
        w_core_frac_valid_rows[0] && (r_capture_idx < data_width);
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
            wire [degree - 1 : 0] w_coeff_digit_p_terms;
            wire [degree - 1 : 0] w_coeff_digit_n_terms;
            wire w_bias_digit_p;
            wire w_bias_digit_n;

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

            for (ti = 0; ti < degree; ti = ti + 1) begin : gen_terms
                assign w_state_digit_p_terms[ti] =
                    (w_operand_phase && i_valid_digit)
                        ? i_state_digit_p_terms_rows[ri * degree + ti]
                        : 1'b0;
                assign w_state_digit_n_terms[ti] =
                    (w_operand_phase && i_valid_digit)
                        ? i_state_digit_n_terms_rows[ri * degree + ti]
                        : 1'b0;
                assign w_coeff_digit_p_terms[ti] =
                    (w_operand_phase && i_valid_digit)
                        ? w_coeff_p_ext[ti * data_width + (data_width - 1 - w_operand_digit_idx)]
                        : 1'b0;
                assign w_coeff_digit_n_terms[ti] =
                    (w_operand_phase && i_valid_digit)
                        ? w_coeff_n_ext[ti * data_width + (data_width - 1 - w_operand_digit_idx)]
                        : 1'b0;
            end

            assign w_bias_digit_p =
                (w_operand_phase && i_valid_digit)
                    ? w_bias_p_ext[data_width - 1 - w_operand_digit_idx]
                    : 1'b0;
            assign w_bias_digit_n =
                (w_operand_phase && i_valid_digit)
                    ? w_bias_n_ext[data_width - 1 - w_operand_digit_idx]
                    : 1'b0;

            iter_pagerank_online_mma4_frac_core #(
                .bit_width(data_width)
            ) row_core (
                .i_clk(i_clk),
                .i_rst(i_rst || i_clear),
                .i_ena(w_feed_active),
                .i_x_p(w_state_digit_p_terms),
                .i_x_n(w_state_digit_n_terms),
                .i_y_p(w_coeff_digit_p_terms),
                .i_y_n(w_coeff_digit_n_terms),
                .i_a_p(w_bias_digit_p),
                .i_a_n(w_bias_digit_n),
                .o_z_p(o_commit_digit_p_rows[ri]),
                .o_z_n(o_commit_digit_n_rows[ri]),
                .o_frac_valid(w_core_frac_valid_rows[ri])
            );

            assign o_commit_digit_idx_rows[(ri + 1) * digit_idx_width - 1 -:
                digit_idx_width] = r_capture_idx;
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

                if (w_capture_last || (r_feed_idx == feed_cycles)) begin
                    o_busy <= 1'b0;
                end
            end
        end
    end

endmodule
