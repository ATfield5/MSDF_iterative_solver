`timescale 1ns / 1ps

// P4-SP conventional baseline with NUM_ROWS rows in parallel.
//
// Each row owns PHYSICAL_DEGREE full-word MAC slots.  The design computes one
// PageRank iteration for all rows and intentionally does not physically expand
// K wavefront stages.

module iter_parallel_in_conv_mma8_parallel_rows_top #(
    parameter integer num_rows = 32,
    parameter integer physical_degree = 8,
    parameter integer data_width = 32,
    parameter integer coeff_width = 32,
    parameter integer bias_width = 32,
    parameter integer bound_width = 16,
    parameter integer acc_width = 40,
    parameter integer product_width = data_width + coeff_width + 2,
    parameter integer product_shift = data_width,
    parameter integer round_pipeline = 1
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_clear,
    input                                                   i_start,
    input      [num_rows * physical_degree * data_width - 1 : 0]  i_state_p_terms_rows,
    input      [num_rows * physical_degree * data_width - 1 : 0]  i_state_n_terms_rows,
    input      [num_rows * physical_degree * coeff_width - 1 : 0] i_coeff_p_terms_rows,
    input      [num_rows * physical_degree * coeff_width - 1 : 0] i_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_n_rows,
    output                                                  o_done,
    output     [num_rows * data_width - 1 : 0]              o_state_p_rows,
    output     [num_rows * data_width - 1 : 0]              o_state_n_rows,
    output     [num_rows * acc_width - 1 : 0]               o_sum_rows
);

    wire [num_rows - 1 : 0] w_valid_rows;
    wire [num_rows * bound_width - 1 : 0] w_unused_abs_upper_rows;

    assign o_done = &w_valid_rows;

    genvar ri;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
            conv_signed_row_update_delta_slice_pipe #(
                .degree(physical_degree),
                .bit_width(coeff_width),
                .data_width(data_width),
                .bias_width(bias_width),
                .bound_width(bound_width),
                .acc_width(acc_width),
                .product_width(product_width),
                .product_shift(product_shift),
                .round_pipeline(round_pipeline)
            ) row_update (
                .i_clk(i_clk),
                .i_rst(i_rst || i_clear),
                .i_valid(i_start),
                .i_state_p_terms(i_state_p_terms_rows[
                    ri * physical_degree * data_width +: physical_degree * data_width]),
                .i_state_n_terms(i_state_n_terms_rows[
                    ri * physical_degree * data_width +: physical_degree * data_width]),
                .i_coeff_p_terms(i_coeff_p_terms_rows[
                    ri * physical_degree * coeff_width +: physical_degree * coeff_width]),
                .i_coeff_n_terms(i_coeff_n_terms_rows[
                    ri * physical_degree * coeff_width +: physical_degree * coeff_width]),
                .i_bias_p(i_bias_p_rows[ri * bias_width +: bias_width]),
                .i_bias_n(i_bias_n_rows[ri * bias_width +: bias_width]),
                .i_old_state_p({data_width{1'b0}}),
                .i_old_state_n({data_width{1'b0}}),
                .i_tail_bound({bound_width{1'b0}}),
                .o_valid(w_valid_rows[ri]),
                .o_sum(o_sum_rows[ri * acc_width +: acc_width]),
                .o_sum_p(o_state_p_rows[ri * data_width +: data_width]),
                .o_sum_n(o_state_n_rows[ri * data_width +: data_width]),
                .o_abs_upper(w_unused_abs_upper_rows[ri * bound_width +: bound_width])
            );
        end
    endgenerate

endmodule
