`timescale 1ns / 1ps

// Solver-native row digit engine checkpoint.
//
// This module is the first integrated boundary for the new mainline:
//   fixed-coefficient no-bias contribution
//   + streamed bias digit
//   + residual/output-update loop
//   -> x_new digit stream
//
// It is intentionally kept as a row-level engine, not a runtime top.  The
// current acceptance target is interface correctness and timing of the digit
// stream.  Non-zero numerical equivalence to the full-digit bridge remains the
// next checkpoint because contribution scaling/delay must be paper-derived.

module iter_solver_native_row_digit_engine #(
    parameter integer bit_width = 8,
    parameter integer degree = 4,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer sample_width = 5,
    parameter integer affine_guard_shift = 3,
    parameter integer residual_width = data_width + affine_guard_shift + 1,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                      i_clk,
    input                                      i_rst,
    input                                      i_start,
    input                                      i_valid_digit,
    input      [digit_idx_width-1:0]           i_digit_idx,
    input      [degree-1:0]                    i_state_digit_p_terms,
    input      [degree-1:0]                    i_state_digit_n_terms,
    input      [degree*bit_width-1:0]          i_coeff_p_terms,
    input      [degree*bit_width-1:0]          i_coeff_n_terms,
    input      [bias_width-1:0]                i_bias_p,
    input      [bias_width-1:0]                i_bias_n,
    output                                     o_valid,
    output                                     o_x_new_digit_p,
    output                                     o_x_new_digit_n,
    output     [data_width-1:0]                o_affine_p,
    output     [data_width-1:0]                o_affine_n,
    output     [residual_width-1:0]            o_residual_p,
    output     [residual_width-1:0]            o_residual_n
);

    localparam integer no_bias_width = bit_width + 2;
    localparam integer scaled_affine_width = data_width + affine_guard_shift;
    localparam integer no_bias_pad_width = scaled_affine_width - no_bias_width - affine_guard_shift;

    wire w_bias_valid;
    wire w_bias_digit_p;
    wire w_bias_digit_n;
    reg  r_bias_digit_p;
    reg  r_bias_digit_n;
    reg  r_start_d1;

    wire w_no_bias_valid;
    wire [no_bias_width-1:0] w_no_bias_p;
    wire [no_bias_width-1:0] w_no_bias_n;
    wire [scaled_affine_width-1:0] w_no_bias_ext_p;
    wire [scaled_affine_width-1:0] w_no_bias_ext_n;
    wire [scaled_affine_width-1:0] w_bias_vec_p;
    wire [scaled_affine_width-1:0] w_bias_vec_n;
    wire [scaled_affine_width-1:0] w_affine_p;
    wire [scaled_affine_width-1:0] w_affine_n;

    iter_streamed_bias_source #(
        .bias_width(bias_width),
        .stream_width(data_width),
        .msb_first(1),
        .digit_idx_width(digit_idx_width)
    ) bias_source (
        .i_valid(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_bias_p(i_bias_p),
        .i_bias_n(i_bias_n),
        .o_valid(w_bias_valid),
        .o_bias_digit_p(w_bias_digit_p),
        .o_bias_digit_n(w_bias_digit_n)
    );

    iter_online_affine_no_bias_core #(
        .bit_width(bit_width),
        .degree(degree)
    ) no_bias_core (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(i_valid_digit),
        .i_state_digit_p_terms(i_state_digit_p_terms),
        .i_state_digit_n_terms(i_state_digit_n_terms),
        .i_coeff_p_terms(i_coeff_p_terms),
        .i_coeff_n_terms(i_coeff_n_terms),
        .o_valid(w_no_bias_valid),
        .o_sum_p(w_no_bias_p),
        .o_sum_n(w_no_bias_n)
    );

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_bias_digit_p <= 1'b0;
            r_bias_digit_n <= 1'b0;
            r_start_d1 <= 1'b0;
        end else begin
            if (w_bias_valid) begin
                r_bias_digit_p <= w_bias_digit_p;
                r_bias_digit_n <= w_bias_digit_n;
            end else begin
                r_bias_digit_p <= 1'b0;
                r_bias_digit_n <= 1'b0;
            end
            r_start_d1 <= i_start && i_valid_digit;
        end
    end

    assign w_no_bias_ext_p = {{no_bias_pad_width{1'b0}}, w_no_bias_p, {affine_guard_shift{1'b0}}};
    assign w_no_bias_ext_n = {{no_bias_pad_width{1'b0}}, w_no_bias_n, {affine_guard_shift{1'b0}}};
    assign w_bias_vec_p = {{(scaled_affine_width-affine_guard_shift-1){1'b0}},
        r_bias_digit_p, {affine_guard_shift{1'b0}}};
    assign w_bias_vec_n = {{(scaled_affine_width-affine_guard_shift-1){1'b0}},
        r_bias_digit_n, {affine_guard_shift{1'b0}}};

    iter_parallel_online_adder #(
        .bit_width(scaled_affine_width)
    ) add_streamed_bias (
        .i_x_p(w_no_bias_ext_p),
        .i_x_n(w_no_bias_ext_n),
        .i_y_p(w_bias_vec_p),
        .i_y_n(w_bias_vec_n),
        .i_c_p(1'b0),
        .i_c_n(1'b0),
        .o_z_p(w_affine_p),
        .o_z_n(w_affine_n),
        .o_c_p(),
        .o_c_n()
    );

    iter_online_affine_digit_core #(
        .affine_width(scaled_affine_width),
        .sample_width(sample_width),
        .residual_width(residual_width),
        .sample_offset(affine_guard_shift)
    ) digit_core (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(r_start_d1),
        .i_valid(w_no_bias_valid),
        .i_affine_p(w_affine_p),
        .i_affine_n(w_affine_n),
        .o_valid(o_valid),
        .o_z_p(o_x_new_digit_p),
        .o_z_n(o_x_new_digit_n),
        .o_residual_p(o_residual_p),
        .o_residual_n(o_residual_n)
    );

    assign o_affine_p = w_affine_p[data_width-1:0];
    assign o_affine_n = w_affine_n[data_width-1:0];

endmodule
