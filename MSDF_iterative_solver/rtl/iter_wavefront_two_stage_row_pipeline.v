`timescale 1ns / 1ps

// Two-stage solver-native digit wavefront pipeline.
//
// Stage0 consumes a normal source digit stream and emits x^(k+1) digits.
// Stage1 consumes those emitted digits directly as its term0 source, without
// waiting for stage0 to assemble or commit a full word.  This is the minimal RTL
// checkpoint for true cross-iteration digit streaming:
//
//   stage0 output digit j
//     -> stage1 input digit j
//
// The module intentionally keeps only term0 connected between stages.  It is a
// row-level wavefront proof, not yet a full stencil/multi-row halo scheduler.

module iter_wavefront_two_stage_row_pipeline #(
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
    input      [digit_idx_width - 1 : 0]       i_digit_idx,
    input      [degree - 1 : 0]                i_stage0_state_digit_p_terms,
    input      [degree - 1 : 0]                i_stage0_state_digit_n_terms,
    input      [degree * bit_width - 1 : 0]    i_stage0_coeff_p_terms,
    input      [degree * bit_width - 1 : 0]    i_stage0_coeff_n_terms,
    input      [bias_width - 1 : 0]            i_stage0_bias_p,
    input      [bias_width - 1 : 0]            i_stage0_bias_n,
    input      [degree * bit_width - 1 : 0]    i_stage1_coeff_p_terms,
    input      [degree * bit_width - 1 : 0]    i_stage1_coeff_n_terms,
    input      [bias_width - 1 : 0]            i_stage1_bias_p,
    input      [bias_width - 1 : 0]            i_stage1_bias_n,
    output                                     o_stage0_valid,
    output                                     o_stage0_digit_p,
    output                                     o_stage0_digit_n,
    output                                     o_stage1_valid,
    output                                     o_stage1_digit_p,
    output                                     o_stage1_digit_n,
    output reg [31 : 0]                        o_stage0_valid_count,
    output reg [31 : 0]                        o_stage1_valid_count,
    output reg                                 o_stage1_started_before_stage0_done,
    output reg                                 o_stage0_done,
    output reg                                 o_stage1_done
);

    reg [digit_idx_width - 1 : 0] r_stage1_digit_idx;
    reg [degree - 1 : 0] r_stage1_state_digit_p_terms;
    reg [degree - 1 : 0] r_stage1_state_digit_n_terms;

    wire w_stage1_start;

    assign w_stage1_start = o_stage0_valid &&
        (o_stage0_valid_count == 32'd0);

    iter_solver_native_row_digit_engine #(
        .bit_width(bit_width),
        .degree(degree),
        .data_width(data_width),
        .bias_width(bias_width),
        .sample_width(sample_width),
        .affine_guard_shift(affine_guard_shift),
        .residual_width(residual_width),
        .digit_idx_width(digit_idx_width)
    ) stage0_engine (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_state_digit_p_terms(i_stage0_state_digit_p_terms),
        .i_state_digit_n_terms(i_stage0_state_digit_n_terms),
        .i_coeff_p_terms(i_stage0_coeff_p_terms),
        .i_coeff_n_terms(i_stage0_coeff_n_terms),
        .i_bias_p(i_stage0_bias_p),
        .i_bias_n(i_stage0_bias_n),
        .o_valid(o_stage0_valid),
        .o_x_new_digit_p(o_stage0_digit_p),
        .o_x_new_digit_n(o_stage0_digit_n),
        .o_affine_p(),
        .o_affine_n(),
        .o_residual_p(),
        .o_residual_n()
    );

    iter_solver_native_row_digit_engine #(
        .bit_width(bit_width),
        .degree(degree),
        .data_width(data_width),
        .bias_width(bias_width),
        .sample_width(sample_width),
        .affine_guard_shift(affine_guard_shift),
        .residual_width(residual_width),
        .digit_idx_width(digit_idx_width)
    ) stage1_engine (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(w_stage1_start),
        .i_valid_digit(o_stage0_valid),
        .i_digit_idx(r_stage1_digit_idx),
        .i_state_digit_p_terms(r_stage1_state_digit_p_terms),
        .i_state_digit_n_terms(r_stage1_state_digit_n_terms),
        .i_coeff_p_terms(i_stage1_coeff_p_terms),
        .i_coeff_n_terms(i_stage1_coeff_n_terms),
        .i_bias_p(i_stage1_bias_p),
        .i_bias_n(i_stage1_bias_n),
        .o_valid(o_stage1_valid),
        .o_x_new_digit_p(o_stage1_digit_p),
        .o_x_new_digit_n(o_stage1_digit_n),
        .o_affine_p(),
        .o_affine_n(),
        .o_residual_p(),
        .o_residual_n()
    );

    always @(*) begin
        r_stage1_state_digit_p_terms = {degree{1'b0}};
        r_stage1_state_digit_n_terms = {degree{1'b0}};
        r_stage1_state_digit_p_terms[0] = o_stage0_digit_p;
        r_stage1_state_digit_n_terms[0] = o_stage0_digit_n;
    end

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            r_stage1_digit_idx <= {digit_idx_width{1'b0}};
            o_stage0_valid_count <= 32'd0;
            o_stage1_valid_count <= 32'd0;
            o_stage1_started_before_stage0_done <= 1'b0;
            o_stage0_done <= 1'b0;
            o_stage1_done <= 1'b0;
        end else begin
            if (o_stage0_valid) begin
                if (!o_stage0_done) begin
                    if (o_stage0_valid_count == data_width - 1) begin
                        o_stage0_done <= 1'b1;
                    end
                    o_stage0_valid_count <= o_stage0_valid_count + 1'b1;
                end

                if (!o_stage0_done) begin
                    o_stage1_started_before_stage0_done <= 1'b1;
                end

                if (r_stage1_digit_idx != data_width - 1) begin
                    r_stage1_digit_idx <= r_stage1_digit_idx + 1'b1;
                end
            end

            if (o_stage1_valid) begin
                if (!o_stage1_done) begin
                    if (o_stage1_valid_count == data_width - 1) begin
                        o_stage1_done <= 1'b1;
                    end
                    o_stage1_valid_count <= o_stage1_valid_count + 1'b1;
                end
            end
        end
    end

endmodule
