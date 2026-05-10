`timescale 1ns / 1ps

// Prefix-safe issue controller for a local stencil block.
//
// This is the first scheduler-level block for cross-iteration prefix streaming.
// It observes the current prefix depth of the producer iteration and decides
// which rows of the consumer iteration may issue without waiting for full-word
// commit.
//
// Each row has its own selector margin.  A row is issued at most once, on the
// first cycle where:
//
//   tail_bound(digit_idx) * sum(abs(coeff_row)) < row_margin
//
// The controller is conservative.  If a row is already issued, it stays issued
// for the current controller epoch; otherwise it stalls until the safety gate
// passes for that row.

module iter_prefix_safe_issue_controller #(
    parameter integer num_rows = 4,
    parameter integer degree = 3,
    parameter integer data_width = 11,
    parameter integer coeff_width = 8,
    parameter integer margin_width = 24,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer bound_width = data_width,
    parameter integer weighted_width = margin_width,
    parameter integer coeff_sum_width = coeff_width + ((degree <= 2) ? 1 : $clog2(degree))
) (
    input                                                       i_clk,
    input                                                       i_rst,
    input                                                       i_start,
    input                                                       i_valid_prefix,
    input      [digit_idx_width - 1 : 0]                        i_digit_idx,
    input      [num_rows * degree * coeff_width - 1 : 0]        i_coeff_abs_terms_rows,
    input      [num_rows * margin_width - 1 : 0]                i_selection_margin_rows,
    output reg  [num_rows - 1 : 0]                              o_row_issue_pulse,
    output reg  [num_rows - 1 : 0]                              o_row_issued_mask,
    output                                                      o_all_issued,
    output     [num_rows * bound_width - 1 : 0]                 o_tail_bound_rows,
    output     [num_rows * weighted_width - 1 : 0]              o_weighted_tail_rows
);

    wire [num_rows - 1 : 0] w_prefix_safe_rows;
    wire [num_rows * bound_width - 1 : 0] w_tail_bound_rows;
    wire [num_rows * weighted_width - 1 : 0] w_weighted_tail_rows;
    reg [num_rows - 1 : 0] r_issue_next;

    assign o_all_issued = &o_row_issued_mask;
    assign o_tail_bound_rows = w_tail_bound_rows;
    assign o_weighted_tail_rows = w_weighted_tail_rows;

    integer ri_comb;
    always @(*) begin
        r_issue_next = {num_rows{1'b0}};
        for (ri_comb = 0; ri_comb < num_rows; ri_comb = ri_comb + 1) begin
            r_issue_next[ri_comb] =
                i_valid_prefix &&
                !o_row_issued_mask[ri_comb] &&
                w_prefix_safe_rows[ri_comb];
        end
    end

    genvar ri;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_row_gates
            wire [bound_width - 1 : 0] w_tail_bound;
            wire [weighted_width - 1 : 0] w_weighted_tail;

            iter_prefix_safe_stencil_gate #(
                .degree(degree),
                .data_width(data_width),
                .coeff_width(coeff_width),
                .margin_width(margin_width),
                .digit_idx_width(digit_idx_width),
                .coeff_sum_width(coeff_sum_width),
                .bound_width(bound_width),
                .weighted_width(weighted_width)
            ) gate (
                .i_valid(i_valid_prefix),
                .i_digit_idx(i_digit_idx),
                .i_coeff_abs_terms(i_coeff_abs_terms_rows[ri * degree * coeff_width +: degree * coeff_width]),
                .i_selection_margin(i_selection_margin_rows[ri * margin_width +: margin_width]),
                .o_valid(),
                .o_source_tail_bound(w_tail_bound),
                .o_coeff_abs_sum(),
                .o_weighted_tail_bound(w_weighted_tail),
                .o_prefix_safe(w_prefix_safe_rows[ri])
            );

            assign w_tail_bound_rows[ri * bound_width +: bound_width] = w_tail_bound;
            assign w_weighted_tail_rows[ri * weighted_width +: weighted_width] = w_weighted_tail;
        end
    endgenerate

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            o_row_issue_pulse <= {num_rows{1'b0}};
            o_row_issued_mask <= {num_rows{1'b0}};
        end else begin
            o_row_issue_pulse <= r_issue_next;
            o_row_issued_mask <= o_row_issued_mask | r_issue_next;
        end
    end

endmodule
