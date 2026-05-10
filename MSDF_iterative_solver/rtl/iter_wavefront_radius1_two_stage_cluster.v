`timescale 1ns / 1ps

// Two-stage radius-1 solver-native digit wavefront cluster.
//
// Stage0 computes NUM_ROWS row outputs.  Stage1 consumes the emitted stage0
// digits directly as a radius-1 stencil:
//
//   term0 = left  stage0 row digit
//   term1 = self  stage0 row digit
//   term2 = right stage0 row digit
//   term3 = zero
//
// Boundary rows receive zero for the missing neighbor.  The design proves the
// real target shape: multiple rows, neighbor alignment, no full-word commit
// between consecutive solver iterations.

module iter_wavefront_radius1_two_stage_cluster #(
    parameter integer num_rows = 3,
    parameter integer degree = 4,
    parameter integer bit_width = 5,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer sample_width = 5,
    parameter integer affine_guard_shift = 3,
    parameter integer residual_width = data_width + affine_guard_shift + 1,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                           i_clk,
    input                                           i_rst,
    input                                           i_start,
    input                                           i_valid_digit,
    input      [digit_idx_width - 1 : 0]            i_digit_idx,
    input      [num_rows * degree - 1 : 0]          i_stage0_state_digit_p_terms_rows,
    input      [num_rows * degree - 1 : 0]          i_stage0_state_digit_n_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0] i_stage0_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0] i_stage0_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]      i_stage0_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]      i_stage0_bias_n_rows,
    input      [num_rows * degree * bit_width - 1 : 0] i_stage1_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0] i_stage1_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]      i_stage1_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]      i_stage1_bias_n_rows,
    output     [num_rows - 1 : 0]                   o_stage0_valid_rows,
    output     [num_rows - 1 : 0]                   o_stage0_digit_p_rows,
    output     [num_rows - 1 : 0]                   o_stage0_digit_n_rows,
    output     [num_rows - 1 : 0]                   o_stage1_valid_rows,
    output     [num_rows - 1 : 0]                   o_stage1_digit_p_rows,
    output     [num_rows - 1 : 0]                   o_stage1_digit_n_rows,
    output reg [31 : 0]                             o_stage0_valid_count,
    output reg [31 : 0]                             o_stage1_valid_count,
    output reg                                      o_stage1_started_before_stage0_done,
    output reg                                      o_stage0_done,
    output reg                                      o_stage1_done
);

    reg [digit_idx_width - 1 : 0] r_stage1_digit_idx;
    wire w_stage0_any_valid;
    wire w_stage1_start;
    wire [num_rows * degree - 1 : 0] w_stage1_state_digit_p_terms_rows;
    wire [num_rows * degree - 1 : 0] w_stage1_state_digit_n_terms_rows;

    assign w_stage0_any_valid = o_stage0_valid_rows[0];
    assign w_stage1_start = w_stage0_any_valid && (o_stage0_valid_count == 32'd0);

    genvar ri;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
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
                .i_state_digit_p_terms(i_stage0_state_digit_p_terms_rows[ri * degree +: degree]),
                .i_state_digit_n_terms(i_stage0_state_digit_n_terms_rows[ri * degree +: degree]),
                .i_coeff_p_terms(i_stage0_coeff_p_terms_rows[ri * degree * bit_width +: degree * bit_width]),
                .i_coeff_n_terms(i_stage0_coeff_n_terms_rows[ri * degree * bit_width +: degree * bit_width]),
                .i_bias_p(i_stage0_bias_p_rows[ri * bias_width +: bias_width]),
                .i_bias_n(i_stage0_bias_n_rows[ri * bias_width +: bias_width]),
                .o_valid(o_stage0_valid_rows[ri]),
                .o_x_new_digit_p(o_stage0_digit_p_rows[ri]),
                .o_x_new_digit_n(o_stage0_digit_n_rows[ri]),
                .o_affine_p(),
                .o_affine_n(),
                .o_residual_p(),
                .o_residual_n()
            );

            if (ri == 0) begin : gen_left_boundary
                assign w_stage1_state_digit_p_terms_rows[ri * degree + 0] = 1'b0;
                assign w_stage1_state_digit_n_terms_rows[ri * degree + 0] = 1'b0;
            end else begin : gen_left_neighbor
                assign w_stage1_state_digit_p_terms_rows[ri * degree + 0] =
                    o_stage0_digit_p_rows[ri - 1];
                assign w_stage1_state_digit_n_terms_rows[ri * degree + 0] =
                    o_stage0_digit_n_rows[ri - 1];
            end
            assign w_stage1_state_digit_p_terms_rows[ri * degree + 1] =
                o_stage0_digit_p_rows[ri];
            assign w_stage1_state_digit_n_terms_rows[ri * degree + 1] =
                o_stage0_digit_n_rows[ri];
            if (ri == num_rows - 1) begin : gen_right_boundary
                assign w_stage1_state_digit_p_terms_rows[ri * degree + 2] = 1'b0;
                assign w_stage1_state_digit_n_terms_rows[ri * degree + 2] = 1'b0;
            end else begin : gen_right_neighbor
                assign w_stage1_state_digit_p_terms_rows[ri * degree + 2] =
                    o_stage0_digit_p_rows[ri + 1];
                assign w_stage1_state_digit_n_terms_rows[ri * degree + 2] =
                    o_stage0_digit_n_rows[ri + 1];
            end
            assign w_stage1_state_digit_p_terms_rows[ri * degree + 3] = 1'b0;
            assign w_stage1_state_digit_n_terms_rows[ri * degree + 3] = 1'b0;

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
                .i_valid_digit(w_stage0_any_valid),
                .i_digit_idx(r_stage1_digit_idx),
                .i_state_digit_p_terms(w_stage1_state_digit_p_terms_rows[ri * degree +: degree]),
                .i_state_digit_n_terms(w_stage1_state_digit_n_terms_rows[ri * degree +: degree]),
                .i_coeff_p_terms(i_stage1_coeff_p_terms_rows[ri * degree * bit_width +: degree * bit_width]),
                .i_coeff_n_terms(i_stage1_coeff_n_terms_rows[ri * degree * bit_width +: degree * bit_width]),
                .i_bias_p(i_stage1_bias_p_rows[ri * bias_width +: bias_width]),
                .i_bias_n(i_stage1_bias_n_rows[ri * bias_width +: bias_width]),
                .o_valid(o_stage1_valid_rows[ri]),
                .o_x_new_digit_p(o_stage1_digit_p_rows[ri]),
                .o_x_new_digit_n(o_stage1_digit_n_rows[ri]),
                .o_affine_p(),
                .o_affine_n(),
                .o_residual_p(),
                .o_residual_n()
            );
        end
    endgenerate

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            r_stage1_digit_idx <= {digit_idx_width{1'b0}};
            o_stage0_valid_count <= 32'd0;
            o_stage1_valid_count <= 32'd0;
            o_stage1_started_before_stage0_done <= 1'b0;
            o_stage0_done <= 1'b0;
            o_stage1_done <= 1'b0;
        end else begin
            if (w_stage0_any_valid) begin
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

            if (o_stage1_valid_rows[0]) begin
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
