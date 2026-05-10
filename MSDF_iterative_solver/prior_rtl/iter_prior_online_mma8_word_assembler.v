`timescale 1ns / 1ps

// Autonomous word-level wrapper around the prior paper's MSDF_MUL_ADD_8.
//
// The original operator is a digit-stream online inner-product.  It expects
// i_ena to remain high after the operand digits have been presented so the
// internal online pipeline can emit unit/fraction output digits.  This wrapper
// makes that behavior explicit:
//
//   start
//     -> feed BIT_WIDTH operand digits
//     -> feed zero flush digits while the prior operator emits z[j]
//     -> capture DATA_WIDTH unit/fraction digits into a rail-coded word
//
// It is the missing P2 boundary between the original operator and the current
// runtime shell.  It still preserves a full-word assembly boundary, therefore
// it is intentionally different from the solver-native digit-stream commit
// path.

module iter_prior_online_mma8_word_assembler #(
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer data_width = 11,
    // capture_unit=1 preserves the earlier integer bring-up behavior.
    // capture_unit=0 is the prior-paper fractional stream contract: input
    // operands are fraction digits, so output state should start from the
    // first fractional digit rather than the unit marker.
    parameter integer capture_unit = 1,
    parameter integer feed_cycles = bit_width + data_width + 8,
    parameter integer valid_latency = 4,
    parameter integer feed_idx_width = (feed_cycles <= 2) ? 1 : $clog2(feed_cycles + 1),
    parameter integer digit_idx_width = (bit_width <= 2) ? 1 : $clog2(bit_width),
    parameter integer capture_idx_width = (data_width <= 2) ? 1 : $clog2(data_width + 1)
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_start,
    input      [degree * bit_width - 1 : 0]             i_state_p_terms,
    input      [degree * bit_width - 1 : 0]             i_state_n_terms,
    input      [degree * bit_width - 1 : 0]             i_coeff_p_terms,
    input      [degree * bit_width - 1 : 0]             i_coeff_n_terms,
    input      [bit_width - 1 : 0]                      i_bias_p,
    input      [bit_width - 1 : 0]                      i_bias_n,
    output reg                                          o_busy,
    output reg                                          o_valid,
    output reg [data_width - 1 : 0]                     o_sum_p,
    output reg [data_width - 1 : 0]                     o_sum_n,
    output     [capture_idx_width - 1 : 0]              o_captured_digits
);

    reg [feed_idx_width - 1 : 0] r_feed_idx;
    reg [capture_idx_width - 1 : 0] r_capture_idx;
    reg [valid_latency : 0] r_feed_valid_pipe;
    reg r_prior_rst;
    reg [degree - 1 : 0] r_state_digit_p_terms;
    reg [degree - 1 : 0] r_state_digit_n_terms;
    reg [digit_idx_width - 1 : 0] r_digit_idx;
    reg r_bias_digit_p;
    reg r_bias_digit_n;
    wire w_feed_active;
    wire w_operand_phase;
    wire w_capture_sample;
    wire w_prior_z_p;
    wire w_prior_z_n;
    wire w_prior_int;
    wire w_prior_unit;
    wire w_prior_frac;
    integer ti;
    integer bit_sel;
    integer cap_bit_sel;

    assign w_feed_active = o_busy && !r_prior_rst && (r_feed_idx < feed_cycles);
    assign w_operand_phase = r_feed_idx < bit_width;
    assign w_capture_sample = r_feed_valid_pipe[valid_latency] &&
        (((capture_unit != 0) && w_prior_unit) || w_prior_frac) &&
        (r_capture_idx < data_width);
    assign o_captured_digits = r_capture_idx;

    always @(*) begin
        bit_sel = bit_width - 1 - r_feed_idx;
        r_state_digit_p_terms = {degree{1'b0}};
        r_state_digit_n_terms = {degree{1'b0}};
        r_digit_idx = {digit_idx_width{1'b0}};
        r_bias_digit_p = 1'b0;
        r_bias_digit_n = 1'b0;

        if (w_operand_phase) begin
            r_digit_idx = r_feed_idx[digit_idx_width - 1 : 0];
            r_bias_digit_p = i_bias_p[bit_sel];
            r_bias_digit_n = i_bias_n[bit_sel];
            for (ti = 0; ti < degree; ti = ti + 1) begin
                r_state_digit_p_terms[ti] =
                    i_state_p_terms[ti * bit_width + bit_sel];
                r_state_digit_n_terms[ti] =
                    i_state_n_terms[ti * bit_width + bit_sel];
            end
        end
    end

    iter_prior_online_mma8_row_kernel #(
        .degree(degree),
        .bit_width(bit_width),
        .digit_idx_width(digit_idx_width)
    ) prior_row (
        .i_clk(i_clk),
        .i_rst(i_rst || r_prior_rst),
        .i_valid_digit(w_feed_active),
        .i_digit_idx(r_digit_idx),
        .i_state_digit_p_terms(r_state_digit_p_terms),
        .i_state_digit_n_terms(r_state_digit_n_terms),
        .i_coeff_p_terms(i_coeff_p_terms),
        .i_coeff_n_terms(i_coeff_n_terms),
        .i_bias_digit_p(r_bias_digit_p),
        .i_bias_digit_n(r_bias_digit_n),
        .o_z_p(w_prior_z_p),
        .o_z_n(w_prior_z_n),
        .o_int(w_prior_int),
        .o_unit(w_prior_unit),
        .o_frac(w_prior_frac)
    );

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_busy <= 1'b0;
            o_valid <= 1'b0;
            o_sum_p <= {data_width{1'b0}};
            o_sum_n <= {data_width{1'b0}};
            r_feed_idx <= {feed_idx_width{1'b0}};
            r_capture_idx <= {capture_idx_width{1'b0}};
            r_feed_valid_pipe <= {(valid_latency + 1){1'b0}};
            r_prior_rst <= 1'b1;
        end else begin
            o_valid <= 1'b0;
            r_prior_rst <= 1'b0;
            r_feed_valid_pipe <= {r_feed_valid_pipe[valid_latency - 1 : 0], w_feed_active};

            if (i_start && !o_busy) begin
                o_busy <= 1'b1;
                o_sum_p <= {data_width{1'b0}};
                o_sum_n <= {data_width{1'b0}};
                r_feed_idx <= {feed_idx_width{1'b0}};
                r_capture_idx <= {capture_idx_width{1'b0}};
                r_feed_valid_pipe <= {(valid_latency + 1){1'b0}};
                // The original MSDF_MUL_ADD_8 has persistent append/full
                // state, so every word-level operation must restart it.
                r_prior_rst <= 1'b1;
            end else if (o_busy) begin
                if (w_feed_active) begin
                    r_feed_idx <= r_feed_idx + 1'b1;
                end

                if (w_capture_sample) begin
                    cap_bit_sel = data_width - 1 - r_capture_idx;
                    o_sum_p[cap_bit_sel] <= w_prior_z_p;
                    o_sum_n[cap_bit_sel] <= w_prior_z_n;
                    r_capture_idx <= r_capture_idx + 1'b1;
                end

                if ((r_capture_idx == data_width) ||
                    ((r_feed_idx == feed_cycles) &&
                     (r_feed_valid_pipe == {(valid_latency + 1){1'b0}}))) begin
                    o_busy <= 1'b0;
                    o_valid <= 1'b1;
                end
            end
        end
    end

endmodule
