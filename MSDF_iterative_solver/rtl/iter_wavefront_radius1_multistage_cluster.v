`timescale 1ns / 1ps

// Multi-stage radius-1 solver-native digit wavefront cluster.
//
// Stage 0 consumes an external source digit stream.  Every later stage consumes
// the previous stage's emitted digits through a radius-1 stencil connection:
//
//   term0 = left neighbor, term1 = self, term2 = right neighbor, term3 = zero.
//
// This module is the K-stage extension of
// iter_wavefront_radius1_two_stage_cluster.  It is meant to measure whether the
// digit-stream advantage compounds across several solver iterations.

module iter_wavefront_radius1_multistage_cluster #(
    parameter integer num_stages = 4,
    parameter integer num_rows = 3,
    parameter integer degree = 4,
    parameter integer bit_width = 5,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer sample_width = 5,
    parameter integer affine_guard_shift = 3,
    parameter integer residual_width = data_width + affine_guard_shift + 1,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer inter_stage_delay_cycles = 0
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
    output     [num_stages * num_rows - 1 : 0]          o_stage_valid_rows,
    output     [num_stages * num_rows - 1 : 0]          o_stage_digit_p_rows,
    output     [num_stages * num_rows - 1 : 0]          o_stage_digit_n_rows,
    output     [num_rows - 1 : 0]                       o_final_valid_rows,
    output     [num_rows - 1 : 0]                       o_final_digit_p_rows,
    output     [num_rows - 1 : 0]                       o_final_digit_n_rows,
    output reg [num_stages * 32 - 1 : 0]                o_stage_valid_count,
    output reg [num_stages - 1 : 0]                     o_stage_done,
    output reg [num_stages - 2 : 0]                     o_stage_started_before_prev_done
);

    reg [num_stages * digit_idx_width - 1 : 0] r_stage_digit_idx;
    wire [num_stages - 1 : 0] w_stage_input_valid;
    wire [num_stages - 1 : 0] w_stage_start;
    wire [num_stages * num_rows * degree - 1 : 0] w_stage_state_digit_p_terms;
    wire [num_stages * num_rows * degree - 1 : 0] w_stage_state_digit_n_terms;
    wire [num_stages * num_rows - 1 : 0] w_stage_source_valid_rows;
    wire [num_stages * num_rows - 1 : 0] w_stage_source_digit_p_rows;
    wire [num_stages * num_rows - 1 : 0] w_stage_source_digit_n_rows;

    integer si_seq;

    assign o_final_valid_rows =
        o_stage_valid_rows[(num_stages - 1) * num_rows +: num_rows];
    assign o_final_digit_p_rows =
        o_stage_digit_p_rows[(num_stages - 1) * num_rows +: num_rows];
    assign o_final_digit_n_rows =
        o_stage_digit_n_rows[(num_stages - 1) * num_rows +: num_rows];

    genvar si;
    genvar ri;
    generate
        for (si = 0; si < num_stages; si = si + 1) begin : gen_stage
            if (si == 0) begin : gen_stage0_source
                assign w_stage_input_valid[si] = i_valid_digit;
                assign w_stage_start[si] = i_start;
                for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_stage0_rows
                    assign w_stage_state_digit_p_terms[(si * num_rows + ri) * degree +: degree] =
                        i_stage0_state_digit_p_terms_rows[ri * degree +: degree];
                    assign w_stage_state_digit_n_terms[(si * num_rows + ri) * degree +: degree] =
                        i_stage0_state_digit_n_terms_rows[ri * degree +: degree];
                end
            end else begin : gen_wave_source
                assign w_stage_input_valid[si] =
                    w_stage_source_valid_rows[si * num_rows + 0];
                assign w_stage_start[si] =
                    w_stage_input_valid[si] &&
                    (r_stage_digit_idx[si * digit_idx_width +: digit_idx_width] ==
                        {digit_idx_width{1'b0}});

                for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_wave_rows
                    wire [1 : 0] w_delay_data_in;
                    wire [1 : 0] w_delay_data_out;

                    assign w_delay_data_in = {
                        o_stage_digit_p_rows[(si - 1) * num_rows + ri],
                        o_stage_digit_n_rows[(si - 1) * num_rows + ri]
                    };

                    iter_wavefront_digit_delay_line #(
                        .data_width(2),
                        .delay_cycles(inter_stage_delay_cycles)
                    ) source_delay (
                        .i_clk(i_clk),
                        .i_rst(i_rst || i_start),
                        .i_valid(o_stage_valid_rows[(si - 1) * num_rows + ri]),
                        .i_data(w_delay_data_in),
                        .o_valid(w_stage_source_valid_rows[si * num_rows + ri]),
                        .o_data(w_delay_data_out)
                    );

                    assign w_stage_source_digit_p_rows[si * num_rows + ri] =
                        w_delay_data_out[1];
                    assign w_stage_source_digit_n_rows[si * num_rows + ri] =
                        w_delay_data_out[0];

                    if (ri == 0) begin : gen_left_boundary
                        assign w_stage_state_digit_p_terms[(si * num_rows + ri) * degree + 0] = 1'b0;
                        assign w_stage_state_digit_n_terms[(si * num_rows + ri) * degree + 0] = 1'b0;
                    end else begin : gen_left_neighbor
                        assign w_stage_state_digit_p_terms[(si * num_rows + ri) * degree + 0] =
                            w_stage_source_digit_p_rows[si * num_rows + (ri - 1)];
                        assign w_stage_state_digit_n_terms[(si * num_rows + ri) * degree + 0] =
                            w_stage_source_digit_n_rows[si * num_rows + (ri - 1)];
                    end

                    assign w_stage_state_digit_p_terms[(si * num_rows + ri) * degree + 1] =
                        w_stage_source_digit_p_rows[si * num_rows + ri];
                    assign w_stage_state_digit_n_terms[(si * num_rows + ri) * degree + 1] =
                        w_stage_source_digit_n_rows[si * num_rows + ri];

                    if (ri == num_rows - 1) begin : gen_right_boundary
                        assign w_stage_state_digit_p_terms[(si * num_rows + ri) * degree + 2] = 1'b0;
                        assign w_stage_state_digit_n_terms[(si * num_rows + ri) * degree + 2] = 1'b0;
                    end else begin : gen_right_neighbor
                        assign w_stage_state_digit_p_terms[(si * num_rows + ri) * degree + 2] =
                            w_stage_source_digit_p_rows[si * num_rows + (ri + 1)];
                        assign w_stage_state_digit_n_terms[(si * num_rows + ri) * degree + 2] =
                            w_stage_source_digit_n_rows[si * num_rows + (ri + 1)];
                    end

                    assign w_stage_state_digit_p_terms[(si * num_rows + ri) * degree + 3] = 1'b0;
                    assign w_stage_state_digit_n_terms[(si * num_rows + ri) * degree + 3] = 1'b0;
                end
            end

            for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_row_engines
                iter_solver_native_row_digit_engine #(
                    .bit_width(bit_width),
                    .degree(degree),
                    .data_width(data_width),
                    .bias_width(bias_width),
                    .sample_width(sample_width),
                    .affine_guard_shift(affine_guard_shift),
                    .residual_width(residual_width),
                    .digit_idx_width(digit_idx_width)
                ) row_engine (
                    .i_clk(i_clk),
                    .i_rst(i_rst),
                    .i_start(w_stage_start[si]),
                    .i_valid_digit(w_stage_input_valid[si]),
                    .i_digit_idx((si == 0) ? i_digit_idx :
                        r_stage_digit_idx[si * digit_idx_width +: digit_idx_width]),
                    .i_state_digit_p_terms(
                        w_stage_state_digit_p_terms[(si * num_rows + ri) * degree +: degree]),
                    .i_state_digit_n_terms(
                        w_stage_state_digit_n_terms[(si * num_rows + ri) * degree +: degree]),
                    .i_coeff_p_terms(
                        i_coeff_p_terms_stages[(si * num_rows + ri) * degree * bit_width +: degree * bit_width]),
                    .i_coeff_n_terms(
                        i_coeff_n_terms_stages[(si * num_rows + ri) * degree * bit_width +: degree * bit_width]),
                    .i_bias_p(
                        i_bias_p_stages[(si * num_rows + ri) * bias_width +: bias_width]),
                    .i_bias_n(
                        i_bias_n_stages[(si * num_rows + ri) * bias_width +: bias_width]),
                    .o_valid(o_stage_valid_rows[si * num_rows + ri]),
                    .o_x_new_digit_p(o_stage_digit_p_rows[si * num_rows + ri]),
                    .o_x_new_digit_n(o_stage_digit_n_rows[si * num_rows + ri]),
                    .o_affine_p(),
                    .o_affine_n(),
                    .o_residual_p(),
                    .o_residual_n()
                );
            end
        end
    endgenerate

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            r_stage_digit_idx <= {num_stages * digit_idx_width{1'b0}};
            o_stage_valid_count <= {num_stages * 32{1'b0}};
            o_stage_done <= {num_stages{1'b0}};
            o_stage_started_before_prev_done <= {(num_stages - 1){1'b0}};
        end else begin
            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (si_seq > 0 && w_stage_input_valid[si_seq]) begin
                    if (!o_stage_done[si_seq - 1]) begin
                        o_stage_started_before_prev_done[si_seq - 1] <= 1'b1;
                    end

                    if (r_stage_digit_idx[si_seq * digit_idx_width +: digit_idx_width] !=
                        data_width - 1) begin
                        r_stage_digit_idx[si_seq * digit_idx_width +: digit_idx_width] <=
                            r_stage_digit_idx[si_seq * digit_idx_width +: digit_idx_width] + 1'b1;
                    end
                end

                if (o_stage_valid_rows[si_seq * num_rows + 0]) begin
                    if (!o_stage_done[si_seq]) begin
                        if (o_stage_valid_count[si_seq * 32 +: 32] == data_width - 1) begin
                            o_stage_done[si_seq] <= 1'b1;
                        end
                        o_stage_valid_count[si_seq * 32 +: 32] <=
                            o_stage_valid_count[si_seq * 32 +: 32] + 1'b1;
                    end
                end
            end
        end
    end

endmodule
