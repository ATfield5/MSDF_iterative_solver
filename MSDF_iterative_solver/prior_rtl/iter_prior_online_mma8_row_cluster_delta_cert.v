`timescale 1ns / 1ps

// P2 prior-online cluster wrapper.
//
// This module is the immediate predecessor of a runtime-shell P2 baseline:
// it uses the original MSDF_MUL_ADD_8 operator through the explicit word
// assembler, then performs the same full-word delta/certification boundary as
// a prior online solver would have before the next iteration.

module iter_prior_online_mma8_row_cluster_delta_cert #(
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer capture_unit = 1,
    parameter integer bound_width = bit_width + 5,
    parameter integer coeff_width = 8,
    parameter integer acc_width = 24,
    parameter integer block_size = 1,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size,
    parameter integer cert_product_pipeline = 0,
    parameter integer cert_operand_pipeline = 0,
    parameter integer cert_compare_pipeline = 0
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_start,
    input      [num_rows * degree * data_width - 1 : 0]     i_state_p_terms_rows,
    input      [num_rows * degree * data_width - 1 : 0]     i_state_n_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_n_rows,
    input      [num_rows * data_width - 1 : 0]              i_old_state_p_rows,
    input      [num_rows * data_width - 1 : 0]              i_old_state_n_rows,
    input      [bound_width - 1 : 0]                        i_tail_bound,
    input      [num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights,
    input      [acc_width - 1 : 0]                          i_eta,
    output reg [num_rows - 1 : 0]                           o_valid_rows,
    output     [num_rows * data_width - 1 : 0]              o_sum_p_rows,
    output     [num_rows * data_width - 1 : 0]              o_sum_n_rows,
    output reg [num_rows * bound_width - 1 : 0]             o_abs_upper_rows,
    output     [num_blocks * bound_width - 1 : 0]           o_block_bounds,
    output                                                  o_cluster_valid,
    output                                                  o_cluster_certified,
    output     [acc_width - 1 : 0]                          o_cluster_max_error
);

    function automatic signed [acc_width - 1 : 0] rail_value;
        input [data_width - 1 : 0] p_word;
        input [data_width - 1 : 0] n_word;
        begin
            rail_value =
                $signed({1'b0, p_word}) -
                $signed({1'b0, n_word});
        end
    endfunction

    function automatic [bound_width - 1 : 0] sat_bound;
        input [acc_width - 1 : 0] value;
        begin
            if (value >= (1 << bound_width)) begin
                sat_bound = {bound_width{1'b1}};
            end else begin
                sat_bound = value[bound_width - 1 : 0];
            end
        end
    endfunction

    genvar ri;
    genvar ti;
    wire [num_rows - 1 : 0] w_valid_rows_raw;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
            wire [degree * data_width - 1 : 0] w_coeff_p_terms_ext;
            wire [degree * data_width - 1 : 0] w_coeff_n_terms_ext;
            wire [data_width - 1 : 0] w_bias_p_ext;
            wire [data_width - 1 : 0] w_bias_n_ext;

            for (ti = 0; ti < degree; ti = ti + 1) begin : gen_coeff_ext
                assign w_coeff_p_terms_ext[ti * data_width +: data_width] =
                    {{(data_width - bit_width){1'b0}},
                     i_coeff_p_terms_rows[(ri * degree + ti) * bit_width +: bit_width]};
                assign w_coeff_n_terms_ext[ti * data_width +: data_width] =
                    {{(data_width - bit_width){1'b0}},
                     i_coeff_n_terms_rows[(ri * degree + ti) * bit_width +: bit_width]};
            end

            assign w_bias_p_ext =
                {{(data_width - bias_width){1'b0}},
                 i_bias_p_rows[ri * bias_width +: bias_width]};
            assign w_bias_n_ext =
                {{(data_width - bias_width){1'b0}},
                 i_bias_n_rows[ri * bias_width +: bias_width]};

            iter_prior_online_mma8_word_assembler #(
                .degree(degree),
                .bit_width(data_width),
                .data_width(data_width),
                .capture_unit(capture_unit)
            ) row_asm (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_start(i_start),
                .i_state_p_terms(i_state_p_terms_rows[(ri + 1) * degree * data_width - 1 -: degree * data_width]),
                .i_state_n_terms(i_state_n_terms_rows[(ri + 1) * degree * data_width - 1 -: degree * data_width]),
                .i_coeff_p_terms(w_coeff_p_terms_ext),
                .i_coeff_n_terms(w_coeff_n_terms_ext),
                .i_bias_p(w_bias_p_ext),
                .i_bias_n(w_bias_n_ext),
                .o_busy(),
                .o_valid(w_valid_rows_raw[ri]),
                .o_sum_p(o_sum_p_rows[(ri + 1) * data_width - 1 -: data_width]),
                .o_sum_n(o_sum_n_rows[(ri + 1) * data_width - 1 -: data_width]),
                .o_captured_digits()
            );
        end
    endgenerate

    // The word assemblers update o_sum_p/o_sum_n on the same edge as their
    // raw valid pulse.  Delay the public valid by one cycle so certification
    // and state commit sample stable row words.
    always @(posedge i_clk) begin
        if (i_rst) begin
            o_valid_rows <= {num_rows{1'b0}};
        end else begin
            o_valid_rows <= w_valid_rows_raw;
        end
    end

    integer ai;
    reg signed [acc_width - 1 : 0] r_new_value;
    reg signed [acc_width - 1 : 0] r_old_value;
    reg signed [acc_width - 1 : 0] r_delta_value;
    reg [acc_width - 1 : 0] r_abs_delta;
    reg [acc_width - 1 : 0] r_abs_with_tail;

    always @(*) begin
        o_abs_upper_rows = {num_rows * bound_width{1'b0}};
        for (ai = 0; ai < num_rows; ai = ai + 1) begin
            r_new_value = rail_value(
                o_sum_p_rows[(ai + 1) * data_width - 1 -: data_width],
                o_sum_n_rows[(ai + 1) * data_width - 1 -: data_width]);
            r_old_value = rail_value(
                i_old_state_p_rows[(ai + 1) * data_width - 1 -: data_width],
                i_old_state_n_rows[(ai + 1) * data_width - 1 -: data_width]);
            r_delta_value = r_new_value - r_old_value;
            r_abs_delta = r_delta_value[acc_width - 1]
                ? (~r_delta_value + 1'b1)
                : r_delta_value;
            r_abs_with_tail = r_abs_delta + i_tail_bound;
            o_abs_upper_rows[(ai + 1) * bound_width - 1 -: bound_width] =
                sat_bound(r_abs_with_tail);
        end
    end

    online_row_cluster_block_cert #(
        .num_rows(num_rows),
        .block_size(block_size),
        .bound_width(bound_width),
        .coeff_width(coeff_width),
        .acc_width(acc_width),
        .num_blocks(num_blocks),
        .cert_product_pipeline(cert_product_pipeline),
        .cert_operand_pipeline(cert_operand_pipeline),
        .cert_compare_pipeline(cert_compare_pipeline),
        .input_pipeline(0),
        .output_pipeline(0)
    ) cluster_cert (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_valid_rows(o_valid_rows),
        .i_row_abs_upper(o_abs_upper_rows),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid(o_cluster_valid),
        .o_block_bounds(o_block_bounds),
        .o_certified(o_cluster_certified),
        .o_max_error(o_cluster_max_error)
    );

`ifdef PRIOR_CLUSTER_DEBUG
    always @(posedge i_clk) begin
        if (!i_rst && o_cluster_valid) begin
            $display("PRIOR_CLUSTER_DEBUG valid_rows=%b sum_p=%h sum_n=%h abs=%h max=%0d",
                o_valid_rows, o_sum_p_rows, o_sum_n_rows, o_abs_upper_rows,
                o_cluster_max_error);
        end
    end
`endif

endmodule
