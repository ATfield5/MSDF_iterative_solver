`timescale 1ns / 1ps

// One committed solver-native wavefront stage.
//
// This is the runtime-compatible stage boundary:
//   source digit stream
//     -> solver-native row digit engines
//     -> drain cycles for online latency
//     -> commit adapters
//     -> fixed-width committed state digit stream
//
// Unlike the raw wavefront proof, only committed digits are exposed to the next
// stage.  This matches ROW_DATAPATH_MODE=3's state-bank write contract.

module iter_wavefront_commit_stage_cluster #(
    parameter integer num_rows = 3,
    parameter integer degree = 4,
    parameter integer bit_width = 5,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer skip_digits = 4,
    parameter integer sample_width = 5,
    parameter integer affine_guard_shift = 3,
    parameter integer residual_width = data_width + affine_guard_shift + 1,
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
    output     [num_rows - 1 : 0]                       o_raw_valid_rows,
    output     [num_rows - 1 : 0]                       o_raw_digit_p_rows,
    output     [num_rows - 1 : 0]                       o_raw_digit_n_rows,
    output     [num_rows - 1 : 0]                       o_commit_valid_rows,
    output     [num_rows * digit_idx_width - 1 : 0]     o_commit_digit_idx_rows,
    output     [num_rows - 1 : 0]                       o_commit_digit_p_rows,
    output     [num_rows - 1 : 0]                       o_commit_digit_n_rows,
    output     [num_rows - 1 : 0]                       o_commit_done_rows
);

    reg r_drain_active;
    reg [digit_idx_width - 1 : 0] r_drain_count;
    wire w_input_last_digit;
    wire w_drain_done;
    wire w_engine_valid_digit;
    wire [digit_idx_width - 1 : 0] w_engine_digit_idx;
    wire [num_rows * degree - 1 : 0] w_engine_state_p_terms_rows;
    wire [num_rows * degree - 1 : 0] w_engine_state_n_terms_rows;
    wire [num_rows * bias_width - 1 : 0] w_engine_bias_p_rows;
    wire [num_rows * bias_width - 1 : 0] w_engine_bias_n_rows;

    assign w_input_last_digit = i_valid_digit && (i_digit_idx == data_width - 1);
    assign w_drain_done = r_drain_active && (r_drain_count == skip_digits - 1);
    assign w_engine_valid_digit = i_valid_digit || r_drain_active;
    assign w_engine_digit_idx = r_drain_active ? (data_width - 1) : i_digit_idx;
    assign w_engine_state_p_terms_rows =
        r_drain_active ? {num_rows * degree{1'b0}} : i_state_digit_p_terms_rows;
    assign w_engine_state_n_terms_rows =
        r_drain_active ? {num_rows * degree{1'b0}} : i_state_digit_n_terms_rows;
    assign w_engine_bias_p_rows =
        r_drain_active ? {num_rows * bias_width{1'b0}} : i_bias_p_rows;
    assign w_engine_bias_n_rows =
        r_drain_active ? {num_rows * bias_width{1'b0}} : i_bias_n_rows;

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            r_drain_active <= 1'b0;
            r_drain_count <= {digit_idx_width{1'b0}};
        end else begin
            if (w_input_last_digit && (skip_digits != 0)) begin
                r_drain_active <= 1'b1;
                r_drain_count <= {digit_idx_width{1'b0}};
            end else if (r_drain_active) begin
                if (w_drain_done) begin
                    r_drain_active <= 1'b0;
                    r_drain_count <= {digit_idx_width{1'b0}};
                end else begin
                    r_drain_count <= r_drain_count + 1'b1;
                end
            end
        end
    end

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
            ) row_engine (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_start(i_start && i_valid_digit),
                .i_valid_digit(w_engine_valid_digit),
                .i_digit_idx(w_engine_digit_idx),
                .i_state_digit_p_terms(w_engine_state_p_terms_rows[ri * degree +: degree]),
                .i_state_digit_n_terms(w_engine_state_n_terms_rows[ri * degree +: degree]),
                .i_coeff_p_terms(i_coeff_p_terms_rows[ri * degree * bit_width +: degree * bit_width]),
                .i_coeff_n_terms(i_coeff_n_terms_rows[ri * degree * bit_width +: degree * bit_width]),
                .i_bias_p(w_engine_bias_p_rows[ri * bias_width +: bias_width]),
                .i_bias_n(w_engine_bias_n_rows[ri * bias_width +: bias_width]),
                .o_valid(o_raw_valid_rows[ri]),
                .o_x_new_digit_p(o_raw_digit_p_rows[ri]),
                .o_x_new_digit_n(o_raw_digit_n_rows[ri]),
                .o_affine_p(),
                .o_affine_n(),
                .o_residual_p(),
                .o_residual_n()
            );

            iter_solver_native_commit_adapter #(
                .state_width(data_width),
                .skip_digits(skip_digits),
                .digit_idx_width(digit_idx_width)
            ) commit_adapter (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_clear(i_clear),
                .i_valid(o_raw_valid_rows[ri]),
                .i_digit_p(o_raw_digit_p_rows[ri]),
                .i_digit_n(o_raw_digit_n_rows[ri]),
                .o_write_valid(o_commit_valid_rows[ri]),
                .o_write_digit_idx(o_commit_digit_idx_rows[(ri + 1) *
                    digit_idx_width - 1 -: digit_idx_width]),
                .o_write_digit_p(o_commit_digit_p_rows[ri]),
                .o_write_digit_n(o_commit_digit_n_rows[ri]),
                .o_done(o_commit_done_rows[ri])
            );
        end
    endgenerate

endmodule
