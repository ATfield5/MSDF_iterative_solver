`timescale 1ns / 1ps

// Prefix-safe gate for stencil-style digit streaming.
//
// This module decides whether the current source prefix is safe to feed into a
// downstream online selector before the full source word has completed.
//
// For aligned radix-2 signed-digit sources:
//
//   tail_bound(p) = 2^(DATA_WIDTH-1-p) - 1
//
// The worst-case row-update uncertainty is:
//
//   weighted_tail = tail_bound * sum(abs(coeff_t))
//
// A prefix is safe only if the uncertainty is strictly smaller than the
// selector margin supplied by the downstream row engine.
//
// This is a scheduling gate.  It does not modify digits and does not reduce the
// final precision.

module iter_prefix_safe_stencil_gate #(
    parameter integer degree = 3,
    parameter integer data_width = 11,
    parameter integer coeff_width = 8,
    parameter integer margin_width = 24,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer coeff_sum_width = coeff_width + ((degree <= 2) ? 1 : $clog2(degree)),
    parameter integer bound_width = data_width,
    parameter integer weighted_width = margin_width,
    parameter integer product_width = weighted_width + coeff_sum_width
) (
    input                                           i_valid,
    input      [digit_idx_width - 1 : 0]            i_digit_idx,
    input      [degree * coeff_width - 1 : 0]       i_coeff_abs_terms,
    input      [margin_width - 1 : 0]               i_selection_margin,
    output                                          o_valid,
    output reg [bound_width - 1 : 0]                o_source_tail_bound,
    output reg [coeff_sum_width - 1 : 0]            o_coeff_abs_sum,
    output reg [weighted_width - 1 : 0]             o_weighted_tail_bound,
    output                                          o_prefix_safe
);

    integer ti;
    integer remaining_bits;
    reg [coeff_width - 1 : 0] r_coeff_term;
    reg [coeff_sum_width - 1 : 0] r_coeff_sum;
    reg [weighted_width - 1 : 0] r_tail_ext;
    reg [product_width - 1 : 0] r_weighted_full;

    assign o_valid = i_valid;
    assign o_prefix_safe =
        i_valid &&
        (i_selection_margin != {margin_width{1'b0}}) &&
        (o_weighted_tail_bound < i_selection_margin);

    always @(*) begin
        r_coeff_sum = {coeff_sum_width{1'b0}};
        for (ti = 0; ti < degree; ti = ti + 1) begin
            r_coeff_term = i_coeff_abs_terms[ti * coeff_width +: coeff_width];
            r_coeff_sum = r_coeff_sum + r_coeff_term;
        end
        o_coeff_abs_sum = r_coeff_sum;
    end

    always @(*) begin
        remaining_bits = data_width - 1 - i_digit_idx;
        if (remaining_bits <= 0) begin
            o_source_tail_bound = {bound_width{1'b0}};
        end else if (remaining_bits >= bound_width) begin
            o_source_tail_bound = {bound_width{1'b1}};
        end else begin
            o_source_tail_bound =
                ({{(bound_width - 1){1'b0}}, 1'b1} << remaining_bits) -
                {{(bound_width - 1){1'b0}}, 1'b1};
        end
    end

    always @(*) begin
        r_tail_ext = {{(weighted_width - bound_width){1'b0}}, o_source_tail_bound};
        r_weighted_full = r_tail_ext * o_coeff_abs_sum;
        if (|r_weighted_full[product_width - 1 : weighted_width]) begin
            o_weighted_tail_bound = {weighted_width{1'b1}};
        end else begin
            o_weighted_tail_bound = r_weighted_full[weighted_width - 1 : 0];
        end
    end

endmodule
